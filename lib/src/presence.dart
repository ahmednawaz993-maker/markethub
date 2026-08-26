part of '../main.dart';

// ---------------------------------------------------------------------------
// Presence + message read receipts (WhatsApp-style).
//
// Presence: each signed-in user writes a heartbeat to presence/{uid} every
// ~20s while the app is foregrounded, and flips to offline on pause/detach. A
// support agent additionally keeps a shared presence/support doc fresh so users
// can see whether Customer Care is live (any one online agent keeps it "on").
// A user is shown "Online" while their heartbeat is fresh (< kPresenceStale),
// otherwise "last seen <ago>".
//
// Read receipts: message docs are immutable (firestore.rules), so read state
// lives on the parent chat/ticket doc as per-party "read up to" timestamps —
// keyed by uid for buyer<->seller chats and by role ('user'/'support') for
// support tickets. A message shows a single grey tick when sent, double grey
// when delivered (the recipient's app has listed/opened the thread), and double
// blue when seen (the recipient opened the thread after the message was sent).
// ---------------------------------------------------------------------------

/// A heartbeat older than this means the user is treated as offline even if
/// their last write said online (covers crashes, closed tabs, killed apps).
const Duration kPresenceStale = Duration(seconds: 45);

const Duration _kHeartbeat = Duration(seconds: 20);

CollectionReference<Map<String, dynamic>> get _presenceCol =>
    FirebaseFirestore.instance.collection('presence');

/// Shared presence doc id for Customer Care: any online support agent keeps it
/// fresh so users see "Support is online".
const String kSupportPresenceId = 'support';

/// Drives the current user's own presence heartbeat and app-lifecycle state.
/// Started once the user is authenticated (see AuthGate) and stopped on sign
/// out. Reading other users' presence does not go through this — use the
/// [PresenceStatusLine] / [PresenceDot] widgets.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  Timer? _timer;
  bool _started = false;

  /// The uid we are keeping a heartbeat for. Captured at [start] and reused for
  /// the final "offline" write in [stop]/[_beat] — by the time sign-out disposes
  /// this service, `FirebaseAuth.currentUser` is already null, so without this
  /// the last offline write would be silently skipped and the user would linger
  /// "Online" until their heartbeat went stale.
  String? _uid;

  void start() {
    if (_started) return;
    _started = true;
    _uid = FirebaseAuth.instance.currentUser?.uid;
    WidgetsBinding.instance.addObserver(this);
    _beat(true);
    _timer = Timer.periodic(_kHeartbeat, (_) => _beat(true));
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    await _beat(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    _beat(state == AppLifecycleState.resumed);
  }

  Future<void> _beat(bool online) async {
    final me = FirebaseAuth.instance.currentUser;
    // On sign-out, currentUser is already null when the final offline write
    // runs — fall back to the uid captured at start() so it still lands.
    final uid = me?.uid ?? _uid;
    if (uid == null) return;
    _uid = uid;
    final now = Timestamp.now();
    try {
      await _presenceCol.doc(uid).set({
        'online': online,
        'lastActive': now,
        // merge:true keeps the last-known name if currentUser is gone.
        if (me?.email != null) 'name': me!.email!.split('@').first,
      }, SetOptions(merge: true));
      // Support agents keep the shared Care presence fresh only while online, so
      // one agent going offline never marks Care offline while another is live —
      // staleness handles the last agent leaving.
      if (online && me != null && hasAdminPerm('support')) {
        await _presenceCol.doc(kSupportPresenceId).set({
          'online': true,
          'lastActive': now,
          'name': 'PakBazar Support',
          'agentId': me.uid,
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }
}

/// True if a presence doc means the party is online right now (heartbeat fresh).
bool presenceOnline(Map<String, dynamic>? d) {
  if (d == null || d['online'] != true) return false;
  final ts = d['lastActive'] as Timestamp?;
  if (ts == null) return false;
  return DateTime.now().difference(ts.toDate()) < kPresenceStale;
}

/// (label, isOnline) for a presence doc, e.g. ("Online", true) or
/// ("last seen 5m ago", false).
(String, bool) presenceLabel(Map<String, dynamic>? d) {
  if (presenceOnline(d)) return ('Online', true);
  final ts = d?['lastActive'] as Timestamp?;
  if (ts == null) return ('Offline', false);
  final diff = DateTime.now().difference(ts.toDate());
  if (diff < const Duration(minutes: 1)) return ('last seen recently', false);
  return ('last seen ${timeAgo(ts)}', false);
}

const Color kOnlineGreen = Color(0xFF25D366);
const Color kSeenBlue = Color(0xFF34B7F1);

/// A live "Online / last seen …" line with a status dot. [presenceId] is a uid
/// for buyer<->seller chats or [kSupportPresenceId] for Customer Care. Rebuilds
/// itself periodically so a party silently going stale flips to offline.
class PresenceStatusLine extends StatefulWidget {
  final String presenceId;
  final String? onlinePrefix; // e.g. "Support is" -> "Support is Online"
  final TextStyle? style;
  const PresenceStatusLine(
    this.presenceId, {
    super.key,
    this.onlinePrefix,
    this.style,
  });

  @override
  State<PresenceStatusLine> createState() => _PresenceStatusLineState();
}

class _PresenceStatusLineState extends State<PresenceStatusLine> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-evaluate staleness even when no new snapshot arrives (party went quiet).
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ?? TextStyle(fontSize: 11, color: AppColors.textSecondary);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _presenceCol.doc(widget.presenceId).snapshots(),
      builder: (context, snap) {
        var (label, online) = presenceLabel(snap.data?.data());
        if (online && widget.onlinePrefix != null) {
          label = '${widget.onlinePrefix} Online';
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: online ? kOnlineGreen : Colors.white38,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label, style: style, overflow: TextOverflow.ellipsis),
            ),
          ],
        );
      },
    );
  }
}

/// Streams the number of users currently online (fresh heartbeat) and hands it
/// to [builder]. Rebuilds every 15s so the count decays as heartbeats go stale
/// even when no new snapshot arrives. Excludes the shared Customer Care doc.
class OnlineUsersCount extends StatefulWidget {
  final Widget Function(BuildContext context, int onlineCount) builder;
  const OnlineUsersCount({super.key, required this.builder});

  @override
  State<OnlineUsersCount> createState() => _OnlineUsersCountState();
}

class _OnlineUsersCountState extends State<OnlineUsersCount> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // online==true keeps the result set small; staleness is filtered here.
      stream: _presenceCol.where('online', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        var count = 0;
        for (final d in snap.data?.docs ?? const []) {
          if (d.id == kSupportPresenceId) continue;
          if (presenceOnline(d.data())) count++;
        }
        return widget.builder(context, count);
      },
    );
  }
}

/// A compact "● N online" pill for the admin panel app bar.
class AdminLiveUsersPill extends StatelessWidget {
  const AdminLiveUsersPill({super.key});

  @override
  Widget build(BuildContext context) {
    return OnlineUsersCount(
      builder: (context, onlineCount) => Center(
        child: Container(
          margin: const EdgeInsetsDirectional.only(end: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: AppRadius.rXl,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: kOnlineGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$onlineCount online',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small standalone presence dot (for list rows). Green when online.
class PresenceDot extends StatelessWidget {
  final String presenceId;
  final double size;
  const PresenceDot(this.presenceId, {super.key, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _presenceCol.doc(presenceId).snapshots(),
      builder: (context, snap) {
        final online = presenceOnline(snap.data?.data());
        if (!online) return const SizedBox.shrink();
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: kOnlineGreen,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        );
      },
    );
  }
}

// --- Message ticks ---------------------------------------------------------

enum MsgTick { sent, delivered, seen }

/// Reads a party's "read up to" / "delivered up to" [Timestamp] from a read
/// marker map keyed by [key] (a uid or a role like 'user'/'support').
Timestamp? readMarker(Object? map, String key) {
  if (map is Map) {
    final v = map[key];
    if (v is Timestamp) return v;
  }
  return null;
}

MsgTick tickFor(Timestamp? sentAt, Timestamp? deliveredAt, Timestamp? seenAt) {
  final t = sentAt?.millisecondsSinceEpoch ?? 0;
  if (seenAt != null && seenAt.millisecondsSinceEpoch >= t) return MsgTick.seen;
  if (deliveredAt != null && deliveredAt.millisecondsSinceEpoch >= t) {
    return MsgTick.delivered;
  }
  return MsgTick.sent;
}

/// A WhatsApp-style delivery tick for a message the current user sent.
class MessageStatusTick extends StatelessWidget {
  final Timestamp? sentAt;
  final Timestamp? deliveredAt;
  final Timestamp? seenAt;

  /// Colour for the sent/delivered (grey) state — tuned to the bubble it sits on.
  final Color baseColor;

  const MessageStatusTick({
    super.key,
    required this.sentAt,
    required this.deliveredAt,
    required this.seenAt,
    this.baseColor = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    final t = tickFor(sentAt, deliveredAt, seenAt);
    return Icon(
      t == MsgTick.sent ? Icons.check : Icons.done_all,
      size: 14,
      color: t == MsgTick.seen ? kSeenBlue : baseColor,
    );
  }
}

// --- Marking helpers -------------------------------------------------------

/// Marks a buyer<->seller chat delivered up to now for [uid] (recipient's app
/// has the thread listed but may not have opened it). Caller must guard so this
/// only fires when there is something newer than the existing marker.
Future<void> markChatDelivered(String chatId, String uid) async {
  try {
    await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'deliveredAt': {uid: Timestamp.now()},
    }, SetOptions(merge: true));
  } catch (_) {}
}

/// Marks a buyer<->seller chat delivered AND read up to now for [uid] (recipient
/// has the thread open).
Future<void> markChatRead(String chatId, String uid) async {
  final now = Timestamp.now();
  try {
    await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'deliveredAt': {uid: now},
      'readAt': {uid: now},
    }, SetOptions(merge: true));
  } catch (_) {}
}

/// Marks a support ticket delivered AND read up to now for [role] ('user' or
/// 'support').
Future<void> markTicketRead(String ticketId, String role) async {
  final now = Timestamp.now();
  try {
    await _supportTicketsCol.doc(ticketId).set({
      'deliveredAt': {role: now},
      'readAt': {role: now},
    }, SetOptions(merge: true));
  } catch (_) {}
}
