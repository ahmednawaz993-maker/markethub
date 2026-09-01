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

/// Signs in with Google.
///
/// google.com has been enabled on the Firebase project all along and the app
/// never offered it — the single most-used sign-in button in Pakistan was
/// configured and invisible.
///
/// Deliberately the same shape as Facebook above, and deliberately WITHOUT the
/// google_sign_in package: that route needs the native SDK, a SHA-1 registered
/// for both the debug and the release keystore, and a google-services entry —
/// four things that can be wrong on a release build and are all fine on the
/// developer's machine. signInWithProvider goes through Firebase's own OAuth
/// handler on the domain that already works for Facebook, so there is no new
/// native configuration to get wrong.
///
/// A guest is UPGRADED rather than replaced, so somebody who has been browsing
/// with a cart or favourites keeps them.
Future<UserCredential> signInWithGoogle() async {
  final provider = GoogleAuthProvider()
    ..addScope('email')
    ..addScope('profile');

  final auth = FirebaseAuth.instance;
  final guest = auth.currentUser;

  if (guest != null && guest.isAnonymous) {
    try {
      return kIsWeb
          ? await guest.linkWithPopup(provider)
          : await guest.linkWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'credential-already-in-use' &&
          e.code != 'provider-already-linked' &&
          e.code != 'email-already-in-use') {
        rethrow;
      }
      // That Google account already has a PakBazar account of its own, and the
      // guest session is the throwaway one.
    }
  }
  return kIsWeb
      ? await auth.signInWithPopup(provider)
      : await auth.signInWithProvider(provider);
}

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
String friendlyFacebookError(Object e) {
  if (e is! FirebaseAuthException) {
    return 'Could not sign in with Facebook. Please try again.';
  }
  return switch (e.code) {
    'account-exists-with-different-credential' =>
      'You already have an account on this email address. Log in with your '
          'email and password instead — you can connect Facebook afterwards '
          'from your profile.',
    'popup-closed-by-user' ||
    'cancelled-popup-request' ||
    'web-context-canceled' ||
    'user-cancelled' =>
      '',
    'popup-blocked' =>
      'Your browser blocked the Facebook window. Allow pop-ups for this site '
          'and try again.',
    'network-request-failed' =>
      'No internet connection. Please try again.',
    'too-many-requests' =>
      'Too many attempts. Please try again in a few minutes.',
    'operation-not-allowed' =>
      'Facebook sign-in is not enabled for this app right now.',
    'user-disabled' => 'This account has been disabled.',
    _ => e.message ?? 'Could not sign in with Facebook. Please try again.',
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
      ..cubicTo(
        0.42 * w,
        0.06 * h,
        0.52 * w,
        0.00 * h,
        0.74 * w,
        0.00 * h,
      )
      ..lineTo(p(0.80, 0.0).dx, p(0.80, 0.0).dy)
      ..lineTo(p(0.80, 0.17).dx, p(0.80, 0.17).dy)
      ..lineTo(p(0.72, 0.17).dx, p(0.72, 0.17).dy)
      // ...then curves back down into the bowl of the stem.
      ..cubicTo(
        0.62 * w,
        0.17 * h,
        0.60 * w,
        0.22 * h,
        0.60 * w,
        0.32 * h,
      )
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
