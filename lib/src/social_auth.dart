part of '../main.dart';

// Facebook sign-in.
//
// WHY THERE IS NO facebook SDK DEPENDENCY HERE. The obvious way to do this is
// the flutter_facebook_auth package, which pulls in Meta's native SDK. That
// route needs a Client Token, an Android key hash registered with Meta for both
// the debug and the release keystore, manifest entries, and a ContentProvider
// that initialises at app start — a launch-time crash risk on a live
// marketplace, for a login button.
//
// firebase_auth can do the whole flow itself: signInWithPopup on the web and
// signInWithProvider (a Custom Tab against Firebase's own OAuth handler) on
// Android. Both go through
// https://markethub-80276.firebaseapp.com/__/auth/handler, which already exists
// and is already an authorised domain. So this file is the entire integration:
// no native config, no extra package, nothing new that can fail at startup.

/// The Facebook access token from the most recent sign-in, if any.
///
/// Kept in memory only — deliberately not persisted. It is a bearer credential
/// for a third party, it expires anyway, and the only thing we use it for is an
/// optional friends lookup during the session in which the user signed in.
String? facebookAccessToken;

/// Signs in with Facebook, returning the credential.
///
/// A guest is UPGRADED rather than replaced: [linkWithProvider] keeps the same
/// uid, so a browsing guest who has favourites, a cart or a half-finished
/// listing does not silently lose them by signing in. If that account has
/// already been claimed we fall back to a plain sign-in, which is the only
/// thing left to do.
Future<UserCredential> signInWithFacebook() async {
  final provider = FacebookAuthProvider()
    // 'email' lets us match the Facebook identity to an existing PakBazar
    // account. 'public_profile' is granted by default but naming it keeps the
    // consent screen honest about what we read.
    ..addScope('email')
    ..addScope('public_profile');

  final auth = FirebaseAuth.instance;
  final guest = auth.currentUser;

  UserCredential cred;
  if (guest != null && guest.isAnonymous) {
    try {
      cred = kIsWeb
          ? await guest.linkWithPopup(provider)
          : await guest.linkWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      // The Facebook account already has a PakBazar account of its own. The
      // guest session is the throwaway one, so sign in to the real account.
      if (e.code == 'credential-already-in-use' ||
          e.code == 'provider-already-linked' ||
          e.code == 'email-already-in-use') {
        cred = kIsWeb
            ? await auth.signInWithPopup(provider)
            : await auth.signInWithProvider(provider);
      } else {
        rethrow;
      }
    }
  } else {
    cred = kIsWeb
        ? await auth.signInWithPopup(provider)
        : await auth.signInWithProvider(provider);
  }

  final token = cred.credential?.accessToken;
  if (token != null) facebookAccessToken = token;
  await _saveFacebookId(cred.user);
  return cred;
}

/// The project's WEB OAuth client.
///
/// Passed to Google Sign-In as the SERVER client id, which is what decides the
/// audience of the ID token it hands back. Firebase will only accept a token
/// minted for this client — get it wrong and sign-in fails at the very last
/// step, after the user has already picked their account, which is the most
/// annoying possible place to fail.
const String kGoogleServerClientId =
    '541505846653-0mngf37raalnfhth2dana49laa6egg9g.apps.googleusercontent.com';

bool _googleReady = false;

/// Signs in with Google.
///
/// WHY THIS IS THE NATIVE FLOW AND FACEBOOK IS NOT. Facebook goes through
/// Firebase's generic OAuth handler in a Custom Tab, which needs no native
/// configuration at all — and that is why it was used there. The same trick
/// does NOT work reliably for Google: Google refuses OAuth from an embedded
/// WebView, and the Custom Tab is only used when the device has a browser that
/// supports one. On a device without it the flow silently falls back to a
/// WebView and Google rejects it. So Google gets the native picker, which is
/// also the account chooser people expect to see.
///
/// It needs an Android OAuth client, which needs a SHA-1 registered for the
/// signing key — and this is where it was actually broken. Both certificates
/// were registered in Firebase, but android/app/google-services.json in this
/// repo was downloaded BEFORE that happened, so the file shipped in the app
/// carried only a web client for com.pakbazar24.app and no Android one. Adding
/// a SHA to Firebase does not update the file you already have; it has to be
/// downloaded again.
///
/// A guest is UPGRADED rather than replaced, so somebody who has been browsing
/// with a cart or favourites keeps them.
Future<UserCredential> signInWithGoogle() async {
  final auth = FirebaseAuth.instance;

  if (kIsWeb) return _googleOnWeb(auth);

  // Native first. If the device cannot do it — no Play Services, an unusual
  // Android build, a platform the plugin does not implement — fall back to the
  // Custom Tab flow rather than leaving the button dead. Two ways in beats one
  // way that works on most phones.
  if (GoogleSignIn.instance.supportsAuthenticate()) {
    try {
      return await _googleNative(auth);
    } on FirebaseAuthException {
      // A real Firebase refusal — wrong token audience, disabled account, an
      // email already taken. Falling back would only ask the user to pick
      // their account a second time and fail identically.
      rethrow;
    } catch (e) {
      // Anything else is the NATIVE layer failing, not the sign-in being
      // refused: a missing SHA on some build, Play Services out of date, a
      // device with none. The web handler needs none of that.
      if (e.toString().contains('canceled') ||
          e.toString().contains('cancelled')) {
        rethrow; // the user closed the picker; do not reopen it
      }
      recordHandledError(
        e,
        StackTrace.current,
        context: 'native Google sign-in failed, falling back to the web flow',
      );
    }
  }
  return _googleViaHandler(auth);
}

/// Google sign-in on the website.
///
/// MEASURED, not reasoned about, because the reasoning was wrong twice.
///
/// Only markethub-80276.firebaseapp.com can host this flow. pakbazar24.com is
/// an authorised DOMAIN in Firebase Auth, which is a different list from the
/// two Google actually checks, and it is on neither:
///
///   * as a redirect URI      -> Error 400: redirect_uri_mismatch
///     (pointed authDomain at our own host, clicked the button, read the page)
///   * as a JavaScript origin -> "[GSI_LOGGER]: The given origin is not
///     allowed for the given client ID"
///     (loaded Google Identity Services on the live site and called
///     renderButton)
///
/// So a same-origin popup and Google's own button are both unavailable until
/// our host is added to those two lists in the Google Cloud console. There is
/// no API for it: clientauthconfig.googleapis.com and oauth2.googleapis.com
/// both 404 for a service account.
///
/// THE COOP WARNING IS NOT THE BUG. This console line —
///
///   Cross-Origin-Opener-Policy policy would block the window.closed call.
///
/// — is what sent an earlier attempt off after authDomain, which is how the
/// redirect_uri mismatch got shipped. It comes from accounts.google.com, which
/// sends Cross-Origin-Opener-Policy-REPORT-ONLY: same-origin. Report-only
/// enforces nothing. Our own handler sends no COOP header at all. Both checked
/// with curl; the warning still appears with our header removed, so it is
/// Google's noise and every Firebase site sees it.
///
/// A popup is preferred because it is one page load rather than three and it
/// keeps the user where they were. The redirect is the fallback for a browser
/// that refuses the window, which is the one thing a popup cannot survive.
Future<UserCredential> _googleOnWeb(FirebaseAuth auth) async {
  final provider = GoogleAuthProvider()
    ..addScope('email')
    ..addScope('profile');
  final guest = auth.currentUser;

  try {
    // Linking keeps a browsing guest's uid, so their cart and favourites
    // survive signing in.
    if (guest != null && guest.isAnonymous) {
      try {
        return await guest.linkWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (!_alreadyClaimed(e)) rethrow;
      }
    }
    return await auth.signInWithPopup(provider);
  } on FirebaseAuthException catch (e) {
    if (!_popupUnavailable(e)) rethrow;
    // No window to be had. A redirect needs none.
    await _googleViaRedirect(auth);
    throw FirebaseAuthException(
      code: 'redirect-in-progress',
      message: 'Taking you to Google to sign in…',
    );
  }
}

/// The browser would not give us a window — as opposed to the user closing it,
/// or Google refusing the sign-in. Only these are worth a second attempt by
/// another route.
bool _popupUnavailable(FirebaseAuthException e) => const {
  'popup-blocked',
  'operation-not-supported-in-this-environment',
  'web-storage-unsupported',
}.contains(e.code);

/// Starts the web sign-in by navigating to Google.
///
/// The fallback for a browser that will not open a popup. It goes to the same
/// registered handler and comes back to completeWebSignIn() on the next load.
///
/// Second choice rather than first: it costs a full page load each way, and
/// the return leg is the flow Google specifically warns about under storage
/// partitioning. Worth having anyway — a blocked popup is otherwise a dead
/// button with nothing behind it.
Future<void> _googleViaRedirect(FirebaseAuth auth) async {
  final provider = GoogleAuthProvider()
    ..addScope('email')
    ..addScope('profile');
  final guest = auth.currentUser;
  // Linking keeps a browsing guest's uid, so their cart and favourites survive
  // signing in. If that Google account already has an account of its own the
  // link fails on the way back, and completeWebSignIn sorts it out there.
  if (guest != null && guest.isAnonymous) {
    return guest.linkWithRedirect(provider);
  }
  return auth.signInWithRedirect(provider);
}

/// Finishes a web sign-in that started with a redirect.
///
/// Called once at startup. Harmless and fast when there is no sign-in pending
/// — it resolves to null. On the way back from Google it is what actually
/// signs the user in, so a failure here is a failed sign-in and is reported.
Future<void> completeWebSignIn() async {
  if (!kIsWeb) return;
  final auth = FirebaseAuth.instance;
  try {
    await auth.getRedirectResult();
  } on FirebaseAuthException catch (e, st) {
    // The guest we tried to upgrade cannot have this Google account, because
    // it already belongs to a real one. The credential comes back with the
    // error, so the user is signed into their own account without being sent
    // to Google a second time.
    final credential = e.credential;
    if (_alreadyClaimed(e) && credential != null) {
      try {
        await auth.signInWithCredential(credential);
        return;
      } catch (inner, innerSt) {
        recordHandledError(
          inner,
          innerSt,
          context: 'signing in with an already-claimed Google credential',
        );
        return;
      }
    }
    recordHandledError(e, st, context: 'completing a web Google sign-in');
  } catch (e, st) {
    recordHandledError(e, st, context: 'completing a web Google sign-in');
  }
}

/// The native account picker.
Future<UserCredential> _googleNative(FirebaseAuth auth) async {
  if (!_googleReady) {
    await GoogleSignIn.instance.initialize(
      serverClientId: kGoogleServerClientId,
    );
    _googleReady = true;
  }

  final account = await GoogleSignIn.instance.authenticate();
  final idToken = account.authentication.idToken;
  if (idToken == null) {
    // Nothing to hand Firebase. A clear failure beats a silent one that leaves
    // the button spinning for ever.
    throw FirebaseAuthException(
      code: 'missing-id-token',
      message: 'Google did not return a sign-in token. Please try again.',
    );
  }
  return _finish(auth, GoogleAuthProvider.credential(idToken: idToken));
}

/// Firebase's own OAuth handler, in a Custom Tab.
///
/// The fallback, and the flow Google sign-in used before the native picker was
/// added. It needs no native configuration at all, which is exactly why it is
/// worth keeping for the devices where the native path cannot run.
Future<UserCredential> _googleViaHandler(FirebaseAuth auth) async {
  final provider = GoogleAuthProvider()
    ..addScope('email')
    ..addScope('profile');
  final guest = auth.currentUser;
  if (guest != null && guest.isAnonymous) {
    try {
      return await guest.linkWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (!_alreadyClaimed(e)) rethrow;
    }
  }
  return auth.signInWithProvider(provider);
}

/// Links the credential onto a browsing guest, or signs in with it.
Future<UserCredential> _finish(
  FirebaseAuth auth,
  AuthCredential credential,
) async {
  final guest = auth.currentUser;
  if (guest != null && guest.isAnonymous) {
    try {
      return await guest.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (!_alreadyClaimed(e)) rethrow;
      // That Google account already has a PakBazar account of its own, and the
      // guest session is the throwaway one.
    }
  }
  return auth.signInWithCredential(credential);
}

bool _alreadyClaimed(FirebaseAuthException e) =>
    e.code == 'credential-already-in-use' ||
    e.code == 'provider-already-linked' ||
    e.code == 'email-already-in-use';

/// Records this account's Facebook id so friends can find each other.
///
/// The id stored is Facebook's APP-SCOPED id: it is unique to this app and
/// cannot be used to look the person up on Facebook or in any other app, which
/// is why it is safe to keep on the public profile document. It has to live
/// somewhere queryable — matching a friend list against accounts is a
/// whereIn query across users, and a private subcollection cannot serve that.
///
/// Best-effort: a profile write must never turn a successful login into a
/// failed one.
///
/// This deliberately will NOT create the profile document. ensureUserDoc()
/// treats an existing `users/{uid}` as "already onboarded" and skips both the
/// profile fields and the private contact record — so a merge:true write here
/// racing ahead of it would leave every new Facebook account with nothing but a
/// facebookId and no email on file. For a brand new account we do nothing and
/// let ensureUserDoc() write the id as part of the profile it creates.
Future<void> _saveFacebookId(User? user) async {
  final id = facebookIdOf(user);
  if (user == null || id == null) return;
  try {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    if (!(await ref.get()).exists) return;
    await ref.set({'facebookId': id}, SetOptions(merge: true));
  } catch (_) {}
}

/// This account's Facebook app-scoped id, if it has a Facebook provider linked.
String? facebookIdOf(User? user) => user?.providerData
    .where((p) => p.providerId == 'facebook.com')
    .firstOrNull
    ?.uid;

/// Turns a sign-in failure into something a person can act on.
///
/// The one that matters is account-exists-with-different-credential: it means
/// the person already has a PakBazar account on that email address with a
/// password, and Firebase will not silently merge the two. Saying "an error
/// occurred" there strands them; telling them which door to use does not.
String friendlySignInError(Object e, {String provider = 'Google'}) {
  // The user closing the account picker is not an error and must not produce a
  // red banner. Google's own cancellation comes back as a GoogleSignInException
  // rather than a FirebaseAuthException, so it is matched by name — the type is
  // in the plugin, and importing it here to catch a cancellation is not worth
  // the coupling.
  final text = e.toString();
  if (text.contains('canceled') || text.contains('cancelled')) return '';

  if (e is! FirebaseAuthException) {
    return 'Could not sign in with $provider. Please try again.';
  }
  return switch (e.code) {
    'account-exists-with-different-credential' =>
      'You already have an account on this email address. Sign in with your '
          'email and password instead — you can connect $provider afterwards '
          'from your profile.',
    // The browser is on its way to Google. Not a failure, and there is no
    // banner worth showing on a page that is about to be replaced.
    'redirect-in-progress' => '',
    'popup-closed-by-user' ||
    'cancelled-popup-request' ||
    'web-context-canceled' ||
    'user-cancelled' => '',
    'popup-blocked' =>
      'Your browser blocked the $provider window. Allow pop-ups for this site '
          'and try again.',
    'network-request-failed' => 'No internet connection. Please try again.',
    'too-many-requests' =>
      'Too many attempts. Please try again in a few minutes.',
    'operation-not-allowed' =>
      '$provider sign-in is not enabled for this app right now.',
    'user-disabled' => 'This account has been disabled.',
    'missing-id-token' =>
      'Google did not complete the sign-in. Please try again.',
    _ => e.message ?? 'Could not sign in with $provider. Please try again.',
  };
}

/// Facebook friends who ALSO use PakBazar, as (facebook id, name) pairs.
///
/// This is the whole of what Facebook will give any app. The full friend list
/// has been unavailable since Graph API v2.0 in 2014: /me/friends returns only
/// friends who have themselves logged into this same app and granted the
/// permission. So this list is empty until PakBazar has friends-of-friends
/// using it, and that is a platform rule, not a bug to fix here.
///
/// Returns an empty list on any failure — a missing friends list must never
/// break a game screen.
Future<List<({String id, String name})>> facebookFriendIds() async {
  final token = facebookAccessToken;
  if (token == null) return const [];
  try {
    final uri = Uri.https('graph.facebook.com', '/v21.0/me/friends', {
      'fields': 'id,name',
      'limit': '100',
      'access_token': token,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const [];
    final body = jsonDecode(res.body);
    if (body is! Map || body['data'] is! List) return const [];
    return [
      for (final f in body['data'] as List)
        if (f is Map && f['id'] != null)
          (id: f['id'].toString(), name: (f['name'] ?? 'Friend').toString()),
    ];
  } catch (_) {
    return const [];
  }
}

/// A Facebook friend who has a PakBazar account.
typedef FacebookFriend = ({String uid, String name});

/// Facebook friends who also have a PakBazar account, ready to be invited.
///
/// Two steps: ask Facebook which friends use this app, then match those
/// app-scoped ids against the `facebookId` we stored on each profile at
/// sign-in. The whereIn query is capped at 30 ids per batch because Firestore
/// will not take more.
Future<List<FacebookFriend>> facebookFriendsOnPakBazar() async {
  final friends = await facebookFriendIds();
  if (friends.isEmpty) return const [];
  final me = FirebaseAuth.instance.currentUser?.uid;
  final out = <FacebookFriend>[];
  try {
    for (var i = 0; i < friends.length; i += 30) {
      final batch = friends
          .skip(i)
          .take(30)
          .map((f) => f.id)
          .toList(growable: false);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('facebookId', whereIn: batch)
          .get();
      for (final doc in snap.docs) {
        if (doc.id == me) continue;
        final data = doc.data();
        final name = (data['name'] ?? data['sellerName'] ?? '')
            .toString()
            .trim();
        out.add((
          uid: doc.id,
          // Prefer the PakBazar display name; fall back to the Facebook one so
          // a player with no profile name is still recognisable.
          name: name.isNotEmpty
              ? name
              : friends
                    .firstWhere(
                      (f) => f.id == data['facebookId'],
                      orElse: () => (id: '', name: 'Friend'),
                    )
                    .name,
        ));
      }
    }
  } catch (_) {
    return out;
  }
  return out;
}

/// The Facebook button, in Facebook's own blue.
///
/// Deliberately styled to their brand rather than ours: a sign-in button that
/// does not look like the service it signs you into reads as a phishing screen,
/// and this one appears before the user has any reason to trust the page.
class FacebookSignInButton extends StatelessWidget {
  const FacebookSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.label = 'Continue with Facebook',
  });

  final VoidCallback? onPressed;
  final bool busy;
  final String label;

  static const Color brandBlue = Color(0xFF1877F2);

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: busy ? null : onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: brandBlue,
      foregroundColor: Colors.white,
      disabledBackgroundColor: brandBlue.withValues(alpha: 0.5),
      disabledForegroundColor: Colors.white70,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const _FacebookGlyph(size: 20),
    label: Text(
      label,
      style: AppType.body.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The Facebook "f", drawn as a path.
///
/// Two earlier attempts failed on the live site and both failures were only
/// visible in a screenshot of the real thing, never in a test:
///
///  * Text('f') in Georgia — Android does not have Georgia, so it would have
///    silently fallen back to some other face on most of these devices.
///  * Icons.facebook — the codepoint is not in the Material icon font this app
///    ships, so the button rendered with no mark on it at all.
///
/// A path depends on no font and no icon set, so it renders identically on
/// Android, iOS and the web, and it scales with the button.
class _FacebookGlyph extends StatelessWidget {
  const _FacebookGlyph({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _FacebookGlyphPainter());
}

class _FacebookGlyphPainter extends CustomPainter {
  /// The letter in a unit box, traced anticlockwise from the foot of the stem:
  /// up the stem, out and back along the crossbar, up into the ascender, over
  /// the hook, and back down the far side.
  static const List<Offset> _outline = [
    Offset(0.42, 1.00),
    Offset(0.42, 0.56),
    Offset(0.26, 0.56),
    Offset(0.26, 0.40),
    Offset(0.42, 0.40),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);

    final path = Path()..moveTo(_outline.first.dx * w, _outline.first.dy * h);
    for (final o in _outline.skip(1)) {
      path.lineTo(o.dx * w, o.dy * h);
    }
    path
      // The ascender rises out of the crossbar and hooks right over the top.
      ..lineTo(0.42 * w, 0.30 * h)
      ..cubicTo(0.42 * w, 0.06 * h, 0.52 * w, 0.00 * h, 0.74 * w, 0.00 * h)
      ..lineTo(p(0.80, 0.0).dx, p(0.80, 0.0).dy)
      ..lineTo(p(0.80, 0.17).dx, p(0.80, 0.17).dy)
      ..lineTo(p(0.72, 0.17).dx, p(0.72, 0.17).dy)
      // ...then curves back down into the bowl of the stem.
      ..cubicTo(0.62 * w, 0.17 * h, 0.60 * w, 0.22 * h, 0.60 * w, 0.32 * h)
      ..lineTo(p(0.60, 0.40).dx, p(0.60, 0.40).dy)
      ..lineTo(p(0.80, 0.40).dx, p(0.80, 0.40).dy)
      ..lineTo(p(0.78, 0.56).dx, p(0.78, 0.56).dy)
      ..lineTo(p(0.60, 0.56).dx, p(0.60, 0.56).dy)
      ..lineTo(p(0.60, 1.00).dx, p(0.60, 1.00).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_FacebookGlyphPainter old) => false;
}

/// The Google button.
///
/// White with a hairline, which is what Google's own branding guidance asks
/// for and what every other app on the phone looks like — a coloured Google
/// button reads as a fake.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.label = 'Continue with Google',
  });

  final VoidCallback? onPressed;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: busy ? null : onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF3C4043),
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: Color(0xFFDADCE0)),
      ),
    ),
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const _GoogleGlyph(size: 20),
    label: Text(
      label,
      style: AppType.body.copyWith(
        color: const Color(0xFF3C4043),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Google's four-colour G, drawn as arcs.
///
/// Drawn rather than typed or shipped as an asset for the reason recorded on
/// _FacebookGlyph above: this app has already shipped a sign-in button with no
/// mark on it, because the icon codepoint was not in the font. A path cannot
/// go missing.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GoogleGlyphPainter());
}

class _GoogleGlyphPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.22;
    final rect = Rect.fromCircle(
      center: Offset(s / 2, s / 2),
      radius: s / 2 - stroke / 2,
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four quadrants, in Google's order, starting at the right and going
    // clockwise: red across the top, yellow down the left, green along the
    // bottom, blue up the right.
    void quarter(double startDeg, double sweepDeg, Color c) => canvas.drawArc(
      rect,
      startDeg * math.pi / 180,
      sweepDeg * math.pi / 180,
      false,
      arc..color = c,
    );
    quarter(-90, -80, _red);
    quarter(-170, -80, _yellow);
    quarter(110, 80, _green);
    quarter(-14, -76, _blue);

    // The bar of the G.
    canvas.drawRect(
      Rect.fromLTWH(s * 0.52, s * 0.42, s * 0.42, stroke * 0.95),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GoogleGlyphPainter old) => false;
}
