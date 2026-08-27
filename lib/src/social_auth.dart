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
        : const Icon(Icons.facebook, size: 22),
    label: Text(
      label,
      style: AppType.body.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
