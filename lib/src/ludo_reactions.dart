part of '../main.dart';

// Emoji reactions and gifts during a game.
//
// These are the cheapest social feature a board game has and the one players
// use constantly — a taunt after a capture is half of why Ludo is fun with
// other people. The design follows from that:
//
//  * EPHEMERAL, not chat. A reaction lives in its own subcollection, shows for
//    a few seconds and deletes itself. Putting them in the message log would
//    bury the actual conversation under a wall of 😂.
//  * SEATED PLAYERS ONLY, enforced in firestore.rules, not just here. A
//    spectator who can read a room must not be able to spray emoji into it.
//  * RATE LIMITED on the client. Not a security boundary — a modified client
//    ignores it — but it is what stops an ordinary player holding a button
//    down and drowning the table.

/// What a player can throw at the table. Kept deliberately small: a grid of
/// sixty emoji is a menu to be navigated, and the whole point is that this is
/// faster than typing.
const List<String> kLudoEmojis = ['😂', '😮', '😎', '😭', '🔥', '👏', '🤔', '💀'];

/// Gifts are aimed at a player rather than the room, so they carry a target.
/// The mix is deliberate — three kind, one rude — because that is how these get
/// used at a Ludo table.
enum LudoGift {
  rose('🌹', 'Rose'),
  trophy('🏆', 'Trophy'),
  sweets('🍬', 'Mithai'),
  bomb('💣', 'Bomb');

  const LudoGift(this.emoji, this.label);
  final String emoji;
  final String label;
}

/// How long a reaction stays on screen, and the window the client reads back.
const Duration kLudoReactionLife = Duration(seconds: 5);

/// The gap enforced between one player's reactions.
const Duration kLudoReactionCooldown = Duration(milliseconds: 1200);

/// One emoji or gift, as stored.
class LudoReaction {
  const LudoReaction({
    required this.id,
    required this.userId,
    required this.emoji,
    required this.fromName,
    required this.toName,
    required this.at,
  });

  final String id;
  final String userId;
  final String emoji;
  final String fromName;

  /// Empty for an emoji thrown at the whole table; a player's name for a gift.
  final String toName;
  final DateTime at;

  bool get isGift => toName.isNotEmpty;

  static LudoReaction fromMap(String id, Map<String, dynamic> d) => LudoReaction(
    id: id,
    userId: d['userId']?.toString() ?? '',
    emoji: d['emoji']?.toString() ?? '',
    fromName: d['fromName']?.toString() ?? '',
    toName: d['toName']?.toString() ?? '',
    at: (d['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );

  /// True while this should still be on screen.
  bool isLive(DateTime now) => now.difference(at) < kLudoReactionLife;
}

CollectionReference<Map<String, dynamic>> ludoReactionsCol(String roomId) =>
    FirebaseFirestore.instance
        .collection(_kLudoRooms)
        .doc(roomId)
        .collection('reactions');

/// Sends a reaction, and cleans it up after it has been seen.
///
/// The sender deletes its own document once the display window has passed.
/// Without that these accumulate for the life of the room, and a long game with
/// chatty players would leave hundreds of dead documents behind — the rules let
/// an author delete their own, so no scheduled job is needed.
Future<void> sendLudoReaction({
  required String roomId,
  required String emoji,
  required String fromName,
  String toName = '',
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || emoji.isEmpty) return;
  final doc = await ludoReactionsCol(roomId).add({
    'userId': uid,
    'emoji': emoji,
    'fromName': fromName,
    'toName': toName,
    'at': Timestamp.now(),
  });
  unawaited(
    Future<void>.delayed(kLudoReactionLife * 2, () => doc.delete()).catchError(
      // The room may already be gone, or the player may have closed the app.
      // Neither is worth surfacing.
      (_) {},
    ),
  );
}

/// The tap-to-send strip: emoji for the table, a gift for one player.
class LudoReactionBar extends StatefulWidget {
  const LudoReactionBar({
    super.key,
    required this.roomId,
    required this.room,
    required this.myName,
  });

  final String roomId;
  final LudoRoom room;
  final String myName;

  @override
  State<LudoReactionBar> createState() => _LudoReactionBarState();
}

class _LudoReactionBarState extends State<LudoReactionBar> {
  DateTime? _last;

  bool get _ready {
    final last = _last;
    return last == null ||
        DateTime.now().difference(last) >= kLudoReactionCooldown;
  }

  Future<void> _send(String emoji, {String toName = ''}) async {
    if (!_ready) return;
    setState(() => _last = DateTime.now());
    GameSoundPlayer.instance.play(GameSound.move);
    await sendLudoReaction(
      roomId: widget.roomId,
      emoji: emoji,
      fromName: widget.myName,
      toName: toName,
    );
  }

  /// Gifts need a recipient, so this asks who — but only lists the people
  /// actually at the table, and never the sender or a computer.
  Future<void> _sendGift() async {
    final targets = [
      for (final c in widget.room.seatedColors)
        if (widget.room.seats[c.name] !=
                FirebaseAuth.instance.currentUser?.uid &&
            !(widget.room.seats[c.name] ?? '').startsWith('bot:'))
          (colour: c, name: widget.room.names[c.name] ?? c.label),
    ];
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gifts are for other players — invite someone to play.'),
        ),
      );
      return;
    }
    final choice = await showModalBottomSheet<(LudoGift, String)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Send a gift', style: AppType.sectionTitle),
            ),
            for (final t in targets)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: ludoColorOf(t.colour),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label,
                      ),
                    ),
                    for (final g in LudoGift.values)
                      IconButton(
                        tooltip: g.label,
                        onPressed: () => Navigator.pop(ctx, (g, t.name)),
                        icon: Text(
                          g.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _send(choice.$1.emoji, toName: choice.$2);
  }

  @override
  Widget build(BuildContext context) {
    final seated =
        widget.room.colorOf(FirebaseAuth.instance.currentUser?.uid ?? '') !=
        null;
    if (!seated) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          _Chip(
            onTap: _sendGift,
            child: const Icon(Icons.card_giftcard, size: 20),
          ),
          const SizedBox(width: AppSpacing.xs),
          for (final e in kLudoEmojis) ...[
            _Chip(
              onTap: () => _send(e),
              child: Text(e, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 26,
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: child,
    ),
  );
}

/// Shows the reactions currently in flight, newest at the bottom.
///
/// Reads a short window rather than the whole collection, so a player joining
/// mid-game is not hit by a backlog of everything ever sent.
class LudoReactionOverlay extends StatelessWidget {
  const LudoReactionOverlay({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final since = Timestamp.fromDate(
      DateTime.now().subtract(kLudoReactionLife),
    );
    return StreamBuilder<QuerySnapshot>(
      stream: ludoReactionsCol(roomId)
          .where('at', isGreaterThan: since)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final now = DateTime.now();
        final live =
            snap.data!.docs
                .map(
                  (d) => LudoReaction.fromMap(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .where((r) => r.isLive(now))
                .toList()
              ..sort((a, b) => a.at.compareTo(b.at));
        if (live.isEmpty) return const SizedBox.shrink();
        return IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final r in live.length > 4
                  ? live.sublist(live.length - 4)
                  : live)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _Bubble(reaction: r),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({required this.reaction});
  final LudoReaction reaction;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reaction;
    return FadeTransition(
      opacity: _c,
      child: SlideTransition(
        // Rises into place, so a new reaction reads as arriving rather than
        // appearing.
        position: Tween<Offset>(
          begin: const Offset(0.25, 0.4),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.borderSoft),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: AppSpacing.xs),
              ConstrainedBox(
                // A long display name must not push the bubble off screen.
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  r.isGift ? '${r.fromName} → ${r.toName}' : r.fromName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
