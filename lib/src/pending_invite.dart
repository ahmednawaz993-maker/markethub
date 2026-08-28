part of '../main.dart';

// Remembering an invite across sign-in.
//
// THE GAP THIS CLOSES. A Ludo invite link opened by somebody who is not signed
// in used to say "sign in, then open the link again" — which is asking a person
// who was invited to a game to go and find the message a second time. Most will
// not, and the invite is the whole way a table fills.
//
// So the room is remembered before the login screen, and the moment sign-in
// succeeds the app takes them to that board itself. The link leads to the game;
// the sign-in is a step on the way, not a dead end.
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

/// Remembers the room to open once this person has signed in.
Future<void> rememberPendingLudoInvite(String roomId) async {
  if (roomId.isEmpty) return;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPendingInviteKey, roomId);
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

/// Takes the pending invite, if there is a fresh one. Always CONSUMES it —
/// including when it has expired — so a stale value cannot sit there and fire
/// on some later launch.
Future<String?> takePendingLudoInvite() async {
  try {
    final p = await SharedPreferences.getInstance();
    final roomId = p.getString(_kPendingInviteKey);
    if (roomId == null || roomId.isEmpty) return null;
    final at = p.getInt(_kPendingInviteAtKey);
    await p.remove(_kPendingInviteKey);
    await p.remove(_kPendingInviteAtKey);
    return pendingInviteIsFresh(at, DateTime.now()) ? roomId : null;
  } catch (_) {
    return null;
  }
}

/// Opens the remembered board, if one is waiting.
///
/// Called once the user is signed in and the home screen is up, so there is
/// something to come back to when they leave the game.
Future<void> resumePendingLudoInvite(BuildContext context) async {
  final roomId = await takePendingLudoInvite();
  if (roomId == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => LudoInviteScreen(roomId: roomId)),
  );
}
