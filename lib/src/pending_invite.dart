part of '../main.dart';

// Remembering where someone was going, across sign-in.
//
// THE GAP THIS CLOSES. A shared link opened by somebody who is not signed in
// used to say "sign in, then open the link again" — which asks a person to go
// back and find the message a second time. Most will not.
//
// It matters for BOTH kinds of link, and arguably more for ads than for games:
// an ad link is what a seller shares and what Google indexes, so it is the
// front door for people who have never used PakBazar at all. Telling a first
// visitor to fetch the link again is the worst possible greeting.
//
// So the destination is remembered before the login screen, and the moment
// sign-in succeeds the app opens it. A ROUTE is stored rather than an id, so
// one mechanism serves /ad/... and /ludo/... and anything added later — the
// route is handed straight back to generateAppRoute, which already knows how to
// resolve every link the app understands.
//
// It is stored on DISK rather than in memory because signing in can reload the
// page: a Facebook or Google sign-in on the web leaves and returns, and an
// in-memory value would not survive that.

const String _kPendingInviteKey = 'pending_ludo_invite';
const String _kPendingInviteAtKey = 'pending_ludo_invite_at';

/// How long a remembered invite is honoured.
///
/// Long enough to create an account, verify an email and come back; short
/// enough that a link followed last week does not hijack today's launch. A
/// stale invite would drop somebody into a game that finished days ago.
const Duration kPendingInviteTtl = Duration(hours: 2);

/// Remembers a Ludo room. Kept as a thin wrapper over [rememberPendingRoute]
/// so call sites read as what they mean.
Future<void> rememberPendingLudoInvite(String roomId) =>
    rememberPendingRoute('/ludo/$roomId');

/// Remembers a listing.
Future<void> rememberPendingAd(String listingId) =>
    rememberPendingRoute('/ad/$listingId');

/// Remembers the route to open once this person has signed in.
Future<void> rememberPendingRoute(String route) async {
  if (route.isEmpty) return;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPendingInviteKey, route);
    await p.setInt(
      _kPendingInviteAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (_) {
    // Private browsing, or storage disabled. The invite simply is not
    // remembered; nothing else breaks.
  }
}

/// Whether a stored invite is still worth acting on.
///
/// Pure so the expiry rule can be tested without a device: an invite with no
/// timestamp is treated as expired rather than trusted, because a value written
/// by an older build carries no way to tell how old it is.
bool pendingInviteIsFresh(int? savedAtMs, DateTime now) {
  if (savedAtMs == null) return false;
  final age = now.millisecondsSinceEpoch - savedAtMs;
  if (age < 0) return false; // clock skew, not freshness
  return age <= kPendingInviteTtl.inMilliseconds;
}

/// Normalises a stored value into a route.
///
/// Builds before this one stored a BARE ROOM ID rather than a route. Those
/// values are still on devices that have not updated, and dropping them would
/// silently break the invite flow for exactly the people mid-upgrade.
String pendingRouteOf(String stored) =>
    stored.startsWith('/') ? stored : '/ludo/$stored';

/// Takes the pending route, if there is a fresh one. Always CONSUMES it —
/// including when it has expired — so a stale value cannot sit there and fire
/// on some later launch.
Future<String?> takePendingRoute() async {
  try {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_kPendingInviteKey);
    if (stored == null || stored.isEmpty) return null;
    final at = p.getInt(_kPendingInviteAtKey);
    await p.remove(_kPendingInviteKey);
    await p.remove(_kPendingInviteAtKey);
    return pendingInviteIsFresh(at, DateTime.now())
        ? pendingRouteOf(stored)
        : null;
  } catch (_) {
    return null;
  }
}

/// Opens whatever was remembered, if anything is waiting.
///
/// Called once the user is signed in and the home screen is up, so there is
/// something to come back to when they leave. The route is resolved by
/// generateAppRoute — the same code that handles a cold link — so an ad and a
/// game invite need no separate handling here, and a route this build does not
/// recognise resolves to null and is simply dropped.
Future<void> resumePendingRoute(BuildContext context) async {
  final route = await takePendingRoute();
  if (route == null || !context.mounted) return;
  final page = generateAppRoute(RouteSettings(name: route));
  if (page == null) return;
  await Navigator.of(context).push(page);
}
