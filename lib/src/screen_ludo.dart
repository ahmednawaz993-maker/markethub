part of '../main.dart';

// Multiplayer Ludo: rooms, turn sync and in-game chat.
//
// The whole game lives in ONE Firestore document. That is a deliberate choice:
// a Ludo state is a few hundred bytes, every player needs to see every change,
// and a single document gives ordered, atomic updates for free. Splitting moves
// into a subcollection would buy nothing and cost consistency.
//
// AUTHORITY. The rules run on the client, but firestore.rules only accepts a
// write from the player whose seat is currently to move — so a modified client
// cannot play out of turn or move for someone else. What it COULD still do is
// lie about its own dice roll. Closing that needs a server-side roll (a Cloud
// Function), which is noted in the changelog rather than pretended away.

const String _kLudoRooms = 'ludoRooms';

/// A room's lifecycle.
enum LudoRoomStatus { waiting, playing, finished }

/// One multiplayer room: who is sitting where, and the game itself.
class LudoRoom {
  const LudoRoom({
    required this.id,
    required this.hostId,
    required this.seats,
    required this.names,
    required this.status,
    required this.game,
    required this.updatedAt,
  });

  final String id;
  final String hostId;

  /// colour name -> uid. A colour absent from the map is an empty seat.
  final Map<String, String> seats;
  final Map<String, String> names;
  final LudoRoomStatus status;
  final LudoGame game;
  final Timestamp? updatedAt;

  List<LudoColor> get seatedColors => [
    for (final c in LudoColor.values)
      if (seats.containsKey(c.name)) c,
  ];

  LudoColor? colorOf(String uid) {
    for (final e in seats.entries) {
      if (e.value == uid) {
        return LudoColor.values.firstWhere((c) => c.name == e.key);
      }
    }
    return null;
  }

  bool get isFull => seats.length >= 4;

  static LudoRoom fromDoc(DocumentSnapshot doc) =>
      fromMap(doc.id, (doc.data() as Map<String, dynamic>?) ?? const {});

  /// Split from [fromDoc] so seat/colour logic can be tested without a live
  /// Firestore snapshot — it is the part that decides who may move.
  static LudoRoom fromMap(String id, Map<String, dynamic> d) {
    final seats = (d['seats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final names = (d['names'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawGame = (d['state'] as Map?)?.cast<String, dynamic>();
    return LudoRoom(
      id: id,
      hostId: d['hostId']?.toString() ?? '',
      seats: {for (final e in seats.entries) e.key: '${e.value}'},
      names: {for (final e in names.entries) e.key: '${e.value}'},
      status: LudoRoomStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => LudoRoomStatus.waiting,
      ),
      game: rawGame == null
          ? LudoGame.newGame(const [LudoColor.red, LudoColor.green])
          : LudoGame.fromJson(rawGame),
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }
}

CollectionReference<Map<String, dynamic>> _ludoCol() =>
    FirebaseFirestore.instance.collection(_kLudoRooms);

/// Creates a room with the host seated as Red.
Future<String> createLudoRoom({required String displayName}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final game = LudoGame.newGame(const [LudoColor.red, LudoColor.green]);
  final doc = await _ludoCol().add({
    'hostId': uid,
    'seats': {LudoColor.red.name: uid},
    'names': {LudoColor.red.name: displayName},
    'status': LudoRoomStatus.waiting.name,
    'state': game.toJson(),
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
  });
  return doc.id;
}

/// Takes the first free seat. Returns the colour taken, or null if full.
///
/// Runs in a transaction because two people tapping "Join" at the same instant
/// is the normal case in a lobby, not an edge case.
Future<LudoColor?> joinLudoRoom(String roomId, String displayName) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final ref = _ludoCol().doc(roomId);
    final snap = await tx.get(ref);
    if (!snap.exists) return null;
    final room = LudoRoom.fromDoc(snap);
    final existing = room.colorOf(uid);
    if (existing != null) return existing;
    if (room.isFull || room.status != LudoRoomStatus.waiting) return null;

    final free = LudoColor.values.firstWhere(
      (c) => !room.seats.containsKey(c.name),
      orElse: () => LudoColor.red,
    );
    final seats = {...room.seats, free.name: uid};
    final names = {...room.names, free.name: displayName};
    // The seated colours ARE the players, in board order, so a two-player game
    // sits opposite and a three-player game does not leave a phantom seat.
    final players = [
      for (final c in LudoColor.values)
        if (seats.containsKey(c.name)) c,
    ];
    tx.update(ref, {
      'seats': seats,
      'names': names,
      'state': LudoGame.newGame(players).toJson(),
      'updatedAt': Timestamp.now(),
    });
    return free;
  });
}

/// Seats a computer player in the first free colour.
///
/// The uid is a `bot:` sentinel that no real account can ever hold, which is
/// what lets the server recognise the seat and play it — and stops any human
/// device claiming that seat's turn, since firestore.rules matches on uid.
Future<LudoColor?> addLudoBot(String roomId) async {
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final ref = _ludoCol().doc(roomId);
    final snap = await tx.get(ref);
    if (!snap.exists) return null;
    final room = LudoRoom.fromDoc(snap);
    if (room.isFull || room.status != LudoRoomStatus.waiting) return null;

    final free = LudoColor.values.firstWhere(
      (c) => !room.seats.containsKey(c.name),
      orElse: () => LudoColor.red,
    );
    final n = room.seats.values.where((v) => v.startsWith('bot:')).length + 1;
    final seats = {...room.seats, free.name: 'bot:$n'};
    final names = {...room.names, free.name: 'Computer $n'};
    final players = [
      for (final c in LudoColor.values)
        if (seats.containsKey(c.name)) c,
    ];
    tx.update(ref, {
      'seats': seats,
      'names': names,
      'state': LudoGame.newGame(players).toJson(),
      'updatedAt': Timestamp.now(),
    });
    return free;
  });
}

/// True for a seat played by the server rather than a person.
bool isLudoBotSeat(LudoRoom room, LudoColor c) =>
    (room.seats[c.name] ?? '').startsWith('bot:');

/// Starts the game. Host only; needs at least two seats.
Future<void> startLudoRoom(String roomId) async {
  await _ludoCol().doc(roomId).update({
    'status': LudoRoomStatus.playing.name,
    'updatedAt': Timestamp.now(),
  });
}

/// Writes a new game state after a roll or a move.
Future<void> pushLudoState(String roomId, LudoGame game) async {
  await _ludoCol().doc(roomId).update({
    'state': game.toJson(),
    'status': game.winners.isNotEmpty
        ? LudoRoomStatus.finished.name
        : LudoRoomStatus.playing.name,
    'updatedAt': Timestamp.now(),
  });
}

Future<void> sendLudoMessage(String roomId, String text) async {
  final user = FirebaseAuth.instance.currentUser;
  final t = text.trim();
  if (t.isEmpty || user == null) return;
  await _ludoCol().doc(roomId).collection('messages').add({
    'userId': user.uid,
    'text': t,
    'createdAt': Timestamp.now(),
  });
}

// ---------------------------------------------------------------------------
// Lobby
// ---------------------------------------------------------------------------

class LudoLobbyScreen extends StatelessWidget {
  const LudoLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Ludo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('New game'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ludoCol()
            .where('status', isEqualTo: LudoRoomStatus.waiting.name)
            .orderBy('createdAt', descending: true)
            .limit(30)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load games',
              subtitle: '${snap.error}',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rooms = snap.data!.docs.map(LudoRoom.fromDoc).toList();
          if (rooms.isEmpty) {
            return const EmptyState(
              icon: Icons.casino_outlined,
              title: 'No games waiting',
              subtitle: 'Start one and invite a friend to join.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.navClearance,
            ),
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final r = rooms[i];
              final mine = r.colorOf(uid) != null;
              return AppCard(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                onTap: () => _join(context, r),
                child: Row(
                  children: [
                    Wrap(
                      spacing: 3,
                      children: [
                        for (final c in LudoColor.values)
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: r.seats.containsKey(c.name)
                                  ? ludoColorOf(c)
                                  : AppColors.borderSoft,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.names.values.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${r.seats.length}/4 players · '
                            '${timeAgo(r.updatedAt)}',
                            style: AppType.caption,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      mine ? 'Rejoin' : (r.isFull ? 'Full' : 'Join'),
                      style: TextStyle(
                        color: r.isFull && !mine ? AppColors.textMuted : kPakGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<String> _name() async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .get();
      final n = (doc.data()?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    } catch (_) {}
    return user?.email?.split('@').first ?? 'Player';
  }

  Future<void> _create(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final id = await createLudoRoom(displayName: await _name());
      navigator.push(
        MaterialPageRoute(builder: (_) => LudoGameScreen(roomId: id)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not start a game: $e')),
      );
    }
  }

  Future<void> _join(BuildContext context, LudoRoom room) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (room.colorOf(uid) == null) {
      final taken = await joinLudoRoom(room.id, await _name());
      if (taken == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('That game is full.')),
        );
        return;
      }
    }
    navigator.push(
      MaterialPageRoute(builder: (_) => LudoGameScreen(roomId: room.id)),
    );
  }
}

// ---------------------------------------------------------------------------
// The game
// ---------------------------------------------------------------------------

class LudoGameScreen extends StatefulWidget {
  const LudoGameScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends State<LudoGameScreen> {
  final _chat = TextEditingController();

  /// Moves offered by the roll this device just made. Cleared on every state
  /// change from the server so a stale roll can never be played twice.
  List<LudoMove> _pending = const [];
  int? _shownDice;
  bool _busy = false;

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Asks the server for a dice value.
  ///
  /// The device does NOT generate the number. `ludoRoll` produces it with a
  /// cryptographic RNG and writes the new state itself, and firestore.rules
  /// refuses any client write that sets a dice — so a modified app cannot claim
  /// a six. This method only reads back what the server decided and works out
  /// which tokens that allows the player to touch.
  Future<void> _roll(LudoRoom room) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('ludoRoll')
          .call<Map<String, dynamic>>({'roomId': widget.roomId});
      final dice = (res.data['dice'] as num?)?.toInt();
      if (!mounted || dice == null) return;
      // Recompute the legal moves locally against the state we already hold.
      // The server also computed them; if the two ever disagree the board
      // simply offers nothing and the next snapshot corrects it.
      setState(() {
        _shownDice = dice;
        _pending = room.game.roll(dice).moves;
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not roll.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not roll: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(LudoRoom room, LudoMove move) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await pushLudoState(widget.roomId, room.game.applyMove(move));
      if (mounted) {
        setState(() {
          _pending = const [];
          _shownDice = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not move: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _ludoCol().doc(widget.roomId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ludo')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ludo')),
            body: const EmptyState(
              icon: Icons.casino_outlined,
              title: 'Game ended',
              subtitle: 'This game is no longer available.',
            ),
          );
        }
        final room = LudoRoom.fromDoc(snap.data!);
        final me = room.colorOf(_uid);
        final myTurn =
            room.status == LudoRoomStatus.playing &&
            me != null &&
            room.game.currentPlayer == me &&
            room.game.winners.isEmpty;

        // The pending moves belong to the state this device rolled against. If
        // the server has moved on, they are stale.
        final moves = myTurn ? _pending : const <LudoMove>[];

        return Scaffold(
          appBar: AppBar(
            title: Text(
              room.status == LudoRoomStatus.waiting
                  ? 'Waiting for players'
                  : 'Ludo',
            ),
            actions: [
              IconButton(
                tooltip: 'Chat',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => _openChat(room),
              ),
            ],
          ),
          body: Column(
            children: [
              _players(room, me),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: LudoBoard(
                    game: room.game,
                    moves: moves,
                    onMove: (m) => _play(room, m),
                  ),
                ),
              ),
              _controls(room, me, myTurn),
            ],
          ),
        );
      },
    );
  }

  Widget _players(LudoRoom room, LudoColor? me) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    color: AppColors.surfaceVariant,
    child: Row(
      children: [
        for (final c in room.seatedColors)
          Expanded(
            child: Opacity(
              opacity: room.game.currentPlayer == c ? 1 : 0.45,
              child: Column(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: ludoColorOf(c),
                      shape: BoxShape.circle,
                      border: room.game.currentPlayer == c
                          ? Border.all(color: AppColors.textPrimary, width: 2)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c == me
                        ? 'You'
                        : (room.names[c.name] ?? c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption,
                  ),
                  Text('${room.game.homeCount(c)}/4', style: AppType.caption),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _controls(LudoRoom room, LudoColor? me, bool myTurn) {
    if (room.game.winners.isNotEmpty) {
      final w = room.game.winners.first;
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          w == me ? 'You won 🎉' : '${room.names[w.name] ?? w.label} won',
          textAlign: TextAlign.center,
          style: AppType.sectionTitle,
        ),
      );
    }
    if (room.status == LudoRoomStatus.waiting) {
      final isHost = room.hostId == _uid;
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text(
              '${room.seats.length} of 4 seated. Share this game with a friend '
              'to fill the board.',
              textAlign: TextAlign.center,
              style: AppType.secondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (isHost) ...[
              Wrap(
                spacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: room.isFull
                        ? null
                        : () => addLudoBot(widget.roomId),
                    icon: const Icon(Icons.smart_toy_outlined, size: 18),
                    label: const Text('Add computer'),
                  ),
                  ElevatedButton.icon(
                    onPressed: room.seats.length >= 2
                        ? () => startLudoRoom(widget.roomId)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      room.seats.length >= 2
                          ? 'Start game'
                          : 'Add a player or a computer',
                    ),
                  ),
                ],
              ),
            ] else
              Text('Waiting for the host to start.', style: AppType.caption),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          // Tapping the die rolls, which is what a player reaches for first.
          LudoDice(
            value: _shownDice,
            rolling: _busy,
            enabled: myTurn && _pending.isEmpty,
            onTap: () => _roll(room),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: myTurn
                ? (_pending.isEmpty
                      ? ElevatedButton.icon(
                          onPressed: _busy ? null : () => _roll(room),
                          icon: const Icon(Icons.casino),
                          label: const Text('Roll'),
                        )
                      : Text(
                          'Tap a highlighted token to move.',
                          style: AppType.secondary,
                        ))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        me == null
                            ? 'Watching — every seat is taken.'
                            : 'Waiting for '
                                  '${room.names[room.game.currentPlayer.name] ?? room.game.currentPlayer.label}…',
                        style: AppType.secondary,
                      ),
                      // Nobody can freeze the board by walking away any more,
                      // and saying so stops the other players just leaving too.
                      Text(
                        isLudoBotSeat(room, room.game.currentPlayer)
                            ? 'The computer is thinking.'
                            : 'If they do not play, their turn is taken '
                                  'automatically.',
                        style: AppType.caption,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _openChat(LudoRoom room) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text('Game chat', style: AppType.sectionTitle),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _ludoCol()
                        .doc(widget.roomId)
                        .collection('messages')
                        .orderBy('createdAt', descending: true)
                        .limit(80)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const EmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: 'Say something',
                          subtitle: 'Messages are visible to everyone playing.',
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final who = d['userId']?.toString() ?? '';
                          final mine = who == _uid;
                          final seat = room.seats.entries
                              .where((e) => e.value == who)
                              .map((e) => e.key)
                              .cast<String?>()
                              .firstWhere((_) => true, orElse: () => null);
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              constraints: const BoxConstraints(maxWidth: 280),
                              decoration: BoxDecoration(
                                color: mine
                                    ? kPakGreen.withValues(alpha: 0.12)
                                    : AppColors.surfaceVariant,
                                borderRadius: AppRadius.rMd,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mine
                                        ? 'You'
                                        : (seat == null
                                              ? 'Player'
                                              : (room.names[seat] ?? 'Player')),
                                    style: AppType.caption,
                                  ),
                                  Text(d['text']?.toString() ?? ''),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chat,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Message',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: kPakGreen),
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _send() {
    final t = _chat.text;
    _chat.clear();
    sendLudoMessage(widget.roomId, t);
  }
}
