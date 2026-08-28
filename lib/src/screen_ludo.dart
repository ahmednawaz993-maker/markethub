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
    this.teamsWanted = false,
    this.stake = 0,
    this.pot = 0,
    this.abandonedBy = const [],
    this.seatCap = 4,
  });

  /// How many seats this table has: four on the cross, six on the hexagon.
  ///
  /// Stored on the room rather than read from the game state, because the state
  /// only knows how many are ALREADY seated — a six-player table with two
  /// people in it would otherwise look like a four-player one and stop letting
  /// anybody else in.
  final int seatCap;

  /// Coins it costs to sit at this table. Zero for a free game.
  final int stake;

  /// Coins collected when play began. Written by the server, never the client.
  final int pot;

  /// Players who walked out mid-game. They keep no reward and take no share of
  /// the pot — see leaveLudoGame.
  final List<String> abandonedBy;

  /// Whether this table was opened as 2v2.
  ///
  /// Held on the room, not in the game state, because a game only BECOMES a
  /// team game once four seats are filled — and the intent has to survive every
  /// rebuild between opening the table and that fourth player arriving.
  final bool teamsWanted;

  final String id;
  final String hostId;

  /// colour name -> uid. A colour absent from the map is an empty seat.
  final Map<String, String> seats;
  final Map<String, String> names;
  final LudoRoomStatus status;
  final LudoGame game;
  final Timestamp? updatedAt;

  List<LudoColor> get seatedColors => [
    for (final c in spec.colours)
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

  /// The board this table plays on.
  LudoBoardSpec get spec => LudoBoardSpec.forSeats(seatCap);

  bool get isFull => seats.length >= seatCap;

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
      teamsWanted: d['teamsWanted'] == true,
      stake: (d['stake'] as num?)?.toInt() ?? 0,
      pot: (d['pot'] as num?)?.toInt() ?? 0,
      abandonedBy: [
        for (final v in (d['abandonedBy'] as List? ?? const [])) '$v',
      ],
      // Older rooms predate six-player tables and are all four-seaters.
      seatCap: (d['seatCap'] as num?)?.toInt() ?? 4,
    );
  }
}

CollectionReference<Map<String, dynamic>> _ludoCol() =>
    FirebaseFirestore.instance.collection(_kLudoRooms);

/// Creates a room with the host seated as Red.
Future<String> createLudoRoom({
  required String displayName,
  LudoMode mode = LudoMode.classic,
  bool teams = false,
  int stake = 0,
  int seats = 4,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final spec = LudoBoardSpec.forSeats(seats);
  // Seeded with two seats; newGame only turns teams on once four are filled,
  // so the flag has to survive every rebuild below until then. It is carried on
  // the document as `teamsWanted` because the game state cannot hold it yet.
  final game = LudoGame.newGame(
    const [LudoColor.red, LudoColor.green],
    mode: mode,
    teams: teams,
  );
  final doc = await _ludoCol().add({
    'hostId': uid,
    'seats': {LudoColor.red.name: uid},
    'names': {LudoColor.red.name: displayName},
    'status': LudoRoomStatus.waiting.name,
    'state': game.toJson(),
    'teamsWanted': teams,
    // Fixed at creation. firestore.rules refuses any later change, because
    // raising it mid-game would empty everyone else's balance at start.
    'stake': stake,
    // Fixed at creation like the stake: firestore.rules refuses any later
    // change, so a table cannot grow or shrink under the people sitting at it.
    'seatCap': spec.seats,
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

    final free = room.spec.colours.firstWhere(
      (c) => !room.seats.containsKey(c.name),
      orElse: () => LudoColor.red,
    );
    final seats = {...room.seats, free.name: uid};
    final names = {...room.names, free.name: displayName};
    // The seated colours ARE the players, in board order, so a two-player game
    // sits opposite and a three-player game does not leave a phantom seat.
    final players = [
      for (final c in room.spec.colours)
        if (seats.containsKey(c.name)) c,
    ];
    tx.update(ref, {
      'seats': seats,
      'names': names,
      // Keep the room's mode: rebuilding as classic would silently change the
      // rules under a table that chose Quick or Master.
      'state': LudoGame.newGame(
        players,
        mode: room.game.mode,
        teams: room.teamsWanted,
      ).toJson(),
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

    final free = room.spec.colours.firstWhere(
      (c) => !room.seats.containsKey(c.name),
      orElse: () => LudoColor.red,
    );
    final n = room.seats.values.where((v) => v.startsWith('bot:')).length + 1;
    final seats = {...room.seats, free.name: 'bot:$n'};
    final names = {...room.names, free.name: 'Computer $n'};
    final players = [
      for (final c in room.spec.colours)
        if (seats.containsKey(c.name)) c,
    ];
    tx.update(ref, {
      'seats': seats,
      'names': names,
      // Keep the room's mode AND its team setting. Without this, adding a
      // computer silently reset a Quick or Master table to Classic rules — the
      // same trap joinLudoRoom already guards against, missed here once
      // already, and teams would go the same way.
      'state': LudoGame.newGame(
        players,
        mode: room.game.mode,
        teams: room.teamsWanted,
      ).toJson(),
      'updatedAt': Timestamp.now(),
    });
    return free;
  });
}

/// Seats a quick match aims for. Four is what every other Ludo app deals you.
const int kLudoQuickMatchSeats = 4;

/// How long a table holds open for real people before computers fill it.
///
/// The number that matters most in this file. Before this existed you created a
/// room and waited for a stranger who never came — the live data was full of
/// rooms sitting at one seat, forever. Nobody waits twelve seconds and nobody
/// waits for ever; this is the difference between "a Ludo game" and "a lobby".
const int kLudoAutoStartSeconds = 12;

/// Drops the player straight into a game: joins an open table, or opens one.
///
/// Deliberately filters mode on the client rather than in the query. An
/// equality filter combined with the orderBy would need a composite index, and
/// the lobby already reads this collection the same way — the room count here
/// is tens, not thousands.
Future<String> quickMatchLudo({
  required String displayName,
  LudoMode mode = LudoMode.classic,
  bool teams = false,
  int stake = 0,
  int seats = 4,
}) async {
  try {
    final snap = await _ludoCol()
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
    for (final doc in snap.docs) {
      final room = LudoRoom.fromDoc(doc);
      if (room.status != LudoRoomStatus.waiting) continue;
      if (room.isFull || room.game.mode != mode) continue;
      // A team table is a different game; joining one by accident would drop a
      // player into 2v2 they never chose.
      if (room.teamsWanted != teams) continue;
      // Never seat somebody at a stake they did not pick.
      if (room.stake != stake) continue;
      // A six-player hexagon is a different game from a four-player cross.
      if (room.seatCap != LudoBoardSpec.forSeats(seats).seats) continue;
      // Never match into a table of nothing but computers — that is a solo
      // game wearing a multiplayer hat.
      if (!room.seats.values.any((v) => !v.startsWith('bot:'))) continue;
      final taken = await joinLudoRoom(doc.id, displayName);
      if (taken != null) return doc.id;
    }
  } catch (_) {
    // A failed search must still end in a game.
  }
  return createLudoRoom(
    displayName: displayName,
    mode: mode,
    teams: teams,
    stake: stake,
    seats: seats,
  );
}

/// Seconds until computers fill the table, or null when it is not waiting.
int? ludoAutoStartIn(LudoRoom room) {
  if (room.status != LudoRoomStatus.waiting) return null;
  final at = room.updatedAt?.toDate();
  if (at == null) return null;
  final left = kLudoAutoStartSeconds - DateTime.now().difference(at).inSeconds;
  return left.clamp(0, kLudoAutoStartSeconds);
}

/// Fills the empty seats with computers and starts the game.
///
/// Run by whichever seated client notices first, not by the host: the host is
/// often the one who wandered off, and a table that only their device can start
/// is exactly the table that never starts. The transaction makes the race
/// harmless — the second client to arrive sees status != waiting and stops.
/// Fills the empty seats with computers and starts the game.
///
/// Seats are added ONE AT A TIME and the start is a separate write, because
/// that is the only shape firestore.rules accepts. A single write that seated
/// three computers and flipped status at once matches none of the update
/// clauses — it was silently denied for every player except the host, which is
/// precisely the player who has usually walked away. Cheap to get wrong and
/// invisible when you do: the transaction just fails and the table sits there.
Future<void> autoStartLudoRoom(String roomId) async {
  final first = await _ludoCol().doc(roomId).get();
  if (!first.exists) return;
  final room = LudoRoom.fromDoc(first);
  if (room.status != LudoRoomStatus.waiting) return;
  // Someone must actually be here.
  if (!room.seats.values.any((v) => !v.startsWith('bot:'))) return;

  // Fill to the table's own size, not a fixed four.
  for (var i = room.seats.length; i < room.seatCap; i++) {
    // addLudoBot adds exactly one seat and touches nothing else, which is what
    // the isJoining() rule permits.
    if (await addLudoBot(roomId) == null) break;
  }
  await startLudoRoom(roomId);
}

/// The first build whose client asks the SERVER to roll the dice.
///
/// Builds before this rolled on the device and wrote the number into the game
/// state themselves. firestore.rules now rejects any client-written dice — that
/// is what makes the roll uncheatable — so on an older build the roll is
/// silently denied, the dice appears dead, and the stuck-game sweeper quietly
/// plays the turn instead. Rather than leave those players staring at a board
/// that moves by itself, Ludo tells them to update.
///
/// appBuildNumber is 0 until the platform reports it, and 0 must NOT be treated
/// as "too old" — that would lock everyone out on a slow cold start.
const int kLudoMinBuild = 64;

bool ludoNeedsUpdate() => appBuildNumber > 0 && appBuildNumber < kLudoMinBuild;

/// How long a player has before the server plays their turn for them. Must
/// match LUDO_TURN_SECONDS in functions/index.js — if the client counts down
/// faster than the server acts, players see a timer hit zero and nothing
/// happen, which is worse than no timer at all.
const int kLudoTurnSeconds = 45;

/// Seconds left before the current turn is taken automatically, or null when
/// there is nothing to count.
int? ludoSecondsLeft(LudoRoom room) {
  final at = room.updatedAt;
  if (at == null || room.status != LudoRoomStatus.playing) return null;
  if (room.game.isDecided) return null;
  final gone = DateTime.now().difference(at.toDate()).inSeconds;
  final left = kLudoTurnSeconds - gone;
  return left.clamp(0, kLudoTurnSeconds);
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

/// Whether this player walked out of this game.
bool ludoHasAbandoned(LudoRoom room, String uid) =>
    room.abandonedBy.contains(uid);

/// Leaves a game in progress.
///
/// The seat is handed to a computer rather than emptied, because three other
/// people are mid-game and collapsing the board under them would punish the
/// wrong players. The leaver is recorded in `abandonedBy`, and the server then
/// treats the game as if they were never there: no win reward, no share of the
/// pot, and no row on the leaderboard. A game you walked out of is not a game
/// you played.
///
/// Any stake already collected stays in the pot. It was taken when play began
/// and the remaining players are still competing for it — refunding a leaver
/// would make quitting free, and quitting a losing position profitable.
Future<void> leaveLudoGame(String roomId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return;
  await FirebaseFirestore.instance.runTransaction((tx) async {
    final ref = _ludoCol().doc(roomId);
    final snap = await tx.get(ref);
    if (!snap.exists) return;
    final room = LudoRoom.fromDoc(snap);
    final colour = room.colorOf(uid);
    if (colour == null) return;

    final bots =
        room.seats.values.where((v) => v.startsWith('bot:')).length + 1;
    tx.update(ref, {
      'seats': {...room.seats, colour.name: 'bot:$bots'},
      'names': {...room.names, colour.name: 'Computer $bots'},
      'abandonedBy': FieldValue.arrayUnion([uid]),
      'updatedAt': Timestamp.now(),
    });
  });
}

/// Writes a new game state after a roll or a move.
Future<void> pushLudoState(String roomId, LudoGame game) async {
  await _ludoCol().doc(roomId).update({
    'state': game.toJson(),
    // isDecided, not winners.isNotEmpty: in a 2v2 the first partner coming
    // home is half a result, and closing the room there would end the game
    // while the other side could still win it.
    'status': game.isDecided
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

class LudoLobbyScreen extends StatefulWidget {
  const LudoLobbyScreen({super.key});

  @override
  State<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

// Stateful only so the matchmaking button can show that it is working. A tap
// that appears to do nothing while a query runs is why people tap twice.
class _LudoLobbyScreenState extends State<LudoLobbyScreen> {
  bool _matching = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (ludoNeedsUpdate()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ludo')),
        body: const EmptyState(
          icon: Icons.system_update,
          title: 'Update to play Ludo',
          subtitle:
              'This version of the app cannot roll the dice. Update PakBazar '
              'from the Play Store and the game will work.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ludo'),
        actions: [
          // Coins appear HERE and nowhere else in the app — never on the wallet
          // screen, never beside a price.
          StreamBuilder<GameProfile>(
            stream: gameProfileStream(),
            builder: (context, snap) {
              final profile = snap.data ?? const GameProfile();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Badge(
                  isLabelVisible: profile.canClaimDaily || profile.chests > 0,
                  child: CoinPill(
                    coins: profile.coins,
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CoinRewardsSheet(profile: profile),
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: "Collection",
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const LudoCollectionSheet(),
            ),
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: 'This week',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LudoLeaderboardScreen()),
            ),
            icon: const Icon(Icons.leaderboard_outlined),
          ),
          TextButton.icon(
            onPressed: _matching ? null : () => _create(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New game'),
          ),
        ],
      ),
      // "Play now" is the primary action, and it is one tap. Choosing a mode,
      // waiting for a stranger and pressing Start were three decisions asked of
      // someone who wanted to play Ludo.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // A great deal of Ludo is played by people sitting together, and none
          // of the online machinery helps them. This needs no connection at all.
          FloatingActionButton.extended(
            heroTag: 'ludo-local',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LudoLocalSetupScreen()),
            ),
            backgroundColor: AppColors.surfaceVariant,
            foregroundColor: AppColors.textPrimary,
            elevation: 1,
            icon: const Icon(Icons.people_outline, size: 18),
            label: const Text('Pass and play'),
          ),
          const SizedBox(height: AppSpacing.sm),
          FloatingActionButton.extended(
            heroTag: 'ludo-online',
            onPressed: _matching ? null : () => _playNow(context),
            icon: _matching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_matching ? 'Finding a game…' : 'Play now'),
          ),
        ],
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
              subtitle:
                  'Tap Play now — you will be dealt in straight away, against '
                  'whoever joins or against the computer.',
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
                        for (final c in LudoBoardSpec.four.colours)
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
                        color: r.isFull && !mine
                            ? AppColors.textMuted
                            : kPakGreen,
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

  /// One tap to a game: join an open table, or open one and let it fill.
  Future<void> _playNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _matching = true);
    try {
      final id = await quickMatchLudo(displayName: await _name());
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(builder: (_) => LudoGameScreen(roomId: id)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not find a game: $e')),
      );
    } finally {
      if (mounted) setState(() => _matching = false);
    }
  }

  Future<void> _create(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Two axes, asked as two questions: WHICH game, then how many sides. That
    // is the same shape Yalla Ludo uses, and it beats a flat list of eight
    // combinations.
    final mode = await showModalBottomSheet<LudoMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Choose a game', style: AppType.sectionTitle),
            ),
            for (final m in LudoMode.values)
              ListTile(
                leading: Icon(switch (m) {
                  LudoMode.classic => Icons.grid_view,
                  LudoMode.quick => Icons.bolt,
                  LudoMode.master => Icons.military_tech,
                  LudoMode.arrow => Icons.double_arrow,
                }, color: kPakGreen),
                title: Text(m.label),
                subtitle: Text(m.blurb, style: AppType.caption),
                onTap: () => Navigator.pop(ctx, m),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (mode == null) return;
    if (!context.mounted) return;
    final teams = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('How many sides?', style: AppType.sectionTitle),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: kPakGreen),
              title: const Text('Everyone for themselves'),
              subtitle: Text(
                'Two to four players, one winner.',
                style: AppType.caption,
              ),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined, color: kPakGreen),
              title: const Text('Team — 2 v 2'),
              subtitle: Text(
                'Partners sit opposite, never capture each other, and win '
                'together when all eight tokens are home. Needs four players.',
                style: AppType.caption,
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (teams == null) return;
    if (!context.mounted) return;
    // Four or six. Asked after the sides question because 2v2 only exists on
    // the four-player board, so choosing Team already answers this.
    final seats = teams
        ? 4
        : await showModalBottomSheet<int>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text('Table size', style: AppType.sectionTitle),
                  ),
                  ListTile(
                    leading: const Icon(Icons.grid_view, color: kPakGreen),
                    title: const Text('Four players'),
                    subtitle: Text(
                      'The classic board.',
                      style: AppType.caption,
                    ),
                    onTap: () => Navigator.pop(ctx, 4),
                  ),
                  ListTile(
                    leading: const Icon(Icons.hexagon_outlined,
                        color: kPakGreen),
                    title: const Text('Six players'),
                    subtitle: Text(
                      'A hexagonal board — longer track, six home columns.',
                      style: AppType.caption,
                    ),
                    onTap: () => Navigator.pop(ctx, 6),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          );
    if (seats == null) return;
    if (!context.mounted) return;
    final stake = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Entry stake', style: AppType.sectionTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Everyone pays in when the game starts and the winner takes '
                    'the pot. Coins only — they are not money and cannot be '
                    'withdrawn.',
                    style: AppType.caption,
                  ),
                ],
              ),
            ),
            for (final tier in kLudoStakeTiers)
              ListTile(
                leading: Icon(
                  tier == 0 ? Icons.sports_esports : Icons.savings_outlined,
                  color: kPakGreen,
                ),
                title: Text(tier == 0 ? 'Free table' : formatCoins(tier)),
                subtitle: Text(
                  tier == 0
                      ? 'No entry cost, no pot.'
                      : 'Pot of up to ${formatCoins(tier * seats)} with a '
                            'full table.',
                  style: AppType.caption,
                ),
                onTap: () => Navigator.pop(ctx, tier),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (stake == null) return;
    try {
      final id = await createLudoRoom(
        displayName: await _name(),
        mode: mode,
        teams: teams,
        stake: stake,
        seats: seats,
      );
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

  /// Cached so a reaction does not trigger a profile read per tap.
  String _displayName = 'Player';

  /// Created lazily and kept for the life of the screen: rebuilding it would
  /// tear down every peer connection on each repaint of the board.
  VoiceSession? _voice;

  VoiceSession? _voiceFor(LudoRoom room) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Only players get a microphone. A spectator listening in on a table is a
    // different feature with different consent.
    if (uid == null || room.colorOf(uid) == null) return null;
    return _voice ??= VoiceSession(
      roomId: widget.roomId,
      myUid: uid,
      myName: _displayName,
    );
  }

  /// Only true while a network call is in flight. Everything else about the
  /// game — including the pending dice — comes from the synced state, so
  /// nothing can be lost by a rebuild.
  bool _busy = false;

  /// The state signature this device has already auto-played, so the forced
  /// move fires once and not on every rebuild of the same snapshot.
  String? _autoPlayed;

  /// Whether this device is playing the whole turn for the player.
  ///
  /// Per game and OFF by default, deliberately not remembered between games.
  /// Coming back to Ludo tomorrow and finding the board playing itself, because
  /// of a switch flipped last week, is alarming rather than convenient.
  bool _autoPlay = false;

  /// Signature of the turn auto-play has already acted on. Separate from
  /// [_autoPlayed] so the two mechanisms cannot block each other.
  String? _autoTurn;

  /// Releases the dice if a roll request is never answered.
  Timer? _rollWatchdog;

  /// Drives the turn countdown. The server takes an unplayed turn after
  /// [kLudoTurnSeconds]; showing that ticking down is the difference between
  /// "the game is helping" and "the board is moving on its own".
  Timer? _tick;
  // Guards the auto-start so a 1Hz rebuild cannot fire a transaction per tick.
  bool _autoStarting = false;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Confirms before walking out. Irreversible, and it can cost a stake — so
  /// the dialog says exactly what happens rather than asking "are you sure?".
  Future<void> _confirmLeave(LudoRoom room) async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this game?'),
        content: Text(
          room.stake > 0
              ? 'A computer takes over your tokens so the others can finish. '
                    'This game will not count towards your record, and your '
                    '${formatCoins(room.stake)} coin stake stays in the pot.'
              : 'A computer takes over your tokens so the others can finish, '
                    'and this game will not count towards your record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await leaveLudoGame(widget.roomId);
    if (mounted) navigator.pop();
  }

  Future<void> _loadDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    var name = user?.email?.split('@').first ?? 'Player';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .get();
      final n = (doc.data()?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) name = n;
    } catch (_) {}
    if (mounted) setState(() => _displayName = name);
  }

  @override
  void dispose() {
    _rollWatchdog?.cancel();
    _tick?.cancel();
    // Closes the microphone and every peer connection, and clears presence.
    _voice?.dispose();
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
  /// Asks the server to roll, by writing a one-field request document.
  ///
  /// NOT a callable. The callable works on Android and iOS but its reply cannot
  /// be decoded by dart2js — any number in the response throws
  /// "Int64 accessor not supported by dart2js" on the web build, even when the
  /// client discards the result. A document write has no reply to decode and
  /// behaves identically on every platform.
  ///
  /// Nothing about the outcome is stored here either. The server parks the dice
  /// on the shared game state and every player reads it from there, which is
  /// also what stops a lost local copy deadlocking the turn.
  Future<void> _roll() async {
    if (_busy) return;
    GameSoundPlayer.instance.play(GameSound.dice);
    setState(() => _busy = true);
    try {
      await _ludoCol().doc(widget.roomId).collection('rollRequests').add({
        'userId': _uid,
        'at': Timestamp.now(),
      });
      // The dice keeps tumbling until the snapshot brings the result; see the
      // reset in build(). A watchdog covers the case where the answer never
      // comes — a request the server declined leaves no trace, and a die that
      // spins forever is a worse failure than one that simply stops.
      _rollWatchdog?.cancel();
      _rollWatchdog = Timer(const Duration(seconds: 10), () {
        if (mounted && _busy) setState(() => _busy = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not roll: $e')));
      }
    }
  }

  Future<void> _play(LudoRoom room, LudoMove move) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await pushLudoState(widget.roomId, room.game.applyMove(move));
      // applyMove clears the dice, so the next snapshot ends the turn or offers
      // the next roll. Nothing to reset here.
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

        // The dice lives on the shared state, so it survives a rebuild and
        // every player sees the same number — the way it works on a real board,
        // and the way Ludo Star shows the roll to the whole table.
        final dice = room.game.lastDice;
        final moves = (myTurn && dice != null)
            ? room.game.legalMoves(dice)
            : const <LudoMove>[];

        // The roll is answered through the document, so the tumble ends when
        // the dice appears or the turn moves on. A request that is refused
        // silently (not your turn any more) still releases the dice, rather
        // than spinning forever.
        if (_busy && (dice != null || !myTurn)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _busy) setState(() => _busy = false);
          });
        }

        // Auto-play: the whole turn, not just a forced move. Rolls, waits long
        // enough for the table to see the number, then plays the move the
        // server's own bot would have chosen.
        if (_autoPlay &&
            myTurn &&
            !_busy &&
            room.status == LudoRoomStatus.playing) {
          final sig =
              'auto:${room.game.turn}:$dice:'
              '${room.game.toJson()['positions']}';
          if (_autoTurn != sig) {
            _autoTurn = sig;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              // A beat before acting, so the other players can follow what
              // happened. Instant play reads as the board glitching.
              await Future<void>.delayed(const Duration(milliseconds: 750));
              // Re-check everything: the snapshot may have moved on, and the
              // player may have switched auto-play off during the pause.
              if (!mounted || !_autoPlay || _busy) return;
              if (dice == null) {
                await _roll();
                return;
              }
              final pick = chooseLudoMove(room.game.currentPlayer, moves);
              if (pick != null) await _play(room, pick);
            });
          }
        }

        // Ludo Star plays the move for you when there is only one — with a
        // single option there is no decision to make, and asking for a tap just
        // slows the table down. The signature guard makes it fire once per
        // roll rather than on every rebuild of the same snapshot.
        if (myTurn && dice != null && moves.length == 1 && !_busy) {
          final sig =
              '${room.game.turn}:$dice:${room.game.toJson()['positions']}';
          if (_autoPlayed != sig) {
            _autoPlayed = sig;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Re-check: the snapshot may have moved on while the frame drew.
              if (mounted && !_busy) _play(room, moves.first);
            });
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              room.status == LudoRoomStatus.waiting
                  ? 'Waiting for players'
                  : 'Ludo · ${room.game.mode.label}',
            ),
            actions: [
              IconButton(
                tooltip: 'Invite players',
                icon: const Icon(Icons.person_add_alt),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => LudoInviteSheet(room: room),
                ),
              ),
              const GameSoundButton(),
              IconButton(
                tooltip: 'Chat',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => _openChat(room),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'auto') {
                    setState(() {
                      _autoPlay = !_autoPlay;
                      // Clear the guard so turning it on acts on the CURRENT
                      // turn rather than waiting for the next one.
                      _autoTurn = null;
                    });
                  } else if (v == 'board') {
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => const LudoCollectionSheet(),
                    );
                  } else if (v == 'leave') {
                    _confirmLeave(room);
                  }
                },
                itemBuilder: (context) => [
                  if (room.colorOf(_uid) != null &&
                      room.status == LudoRoomStatus.playing)
                    PopupMenuItem(
                      value: 'auto',
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          _autoPlay
                              ? Icons.smart_toy
                              : Icons.smart_toy_outlined,
                          color: _autoPlay ? kPakGreen : null,
                        ),
                        title: Text(_autoPlay ? 'Auto-play: on' : 'Auto-play'),
                        subtitle: Text(
                          _autoPlay
                              ? 'Tap to take back control'
                              : 'Play my turns for me',
                          style: AppType.caption,
                        ),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'board',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.palette_outlined),
                      title: Text("Collection"),
                    ),
                  ),
                  if (room.colorOf(_uid) != null &&
                      room.status == LudoRoomStatus.playing)
                    const PopupMenuItem(
                      value: 'leave',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.logout),
                        title: Text('Leave game'),
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _players(room, me),
              Expanded(
                // Reactions float OVER the board rather than taking layout
                // space, so an emoji storm never shifts the squares a player is
                // aiming at mid-tap.
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        // Six seats draw the hexagon. Same game, same moves —
                        // only the geometry differs.
                        child: room.seatCap == 6
                            ? LudoHexBoard(
                                game: room.game,
                                moves: moves,
                                onMove: (m) => _play(room, m),
                              )
                            : LudoBoard(
                                game: room.game,
                                moves: moves,
                                onMove: (m) => _play(room, m),
                              ),
                      ),
                    ),
                    Positioned(
                      right: AppSpacing.md,
                      bottom: AppSpacing.sm,
                      child: LudoReactionOverlay(roomId: widget.roomId),
                    ),
                  ],
                ),
              ),
              if (room.status != LudoRoomStatus.finished)
                Builder(
                  builder: (context) {
                    final v = _voiceFor(room);
                    return v == null
                        ? const SizedBox.shrink()
                        : VoiceChatBar(session: v);
                  },
                ),
              if (room.status == LudoRoomStatus.playing)
                LudoReactionBar(
                  roomId: widget.roomId,
                  room: room,
                  myName: _displayName,
                ),
              _controls(room, me, myTurn, dice, moves),
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
                    c == me ? 'You' : (room.names[c.name] ?? c.label),
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

  Widget _controls(
    LudoRoom room,
    LudoColor? me,
    bool myTurn,
    int? dice,
    List<LudoMove> moves,
  ) {
    if (room.game.isDecided) {
      final w = room.game.winners.first;
      // In a team game the result belongs to the SIDE, so a player whose
      // partner came home first has still won — telling them someone else won
      // would be simply wrong.
      final side = room.game.winningSide;
      final iWon = me != null && side.contains(me);
      final sideNames = [
        for (final c in side)
          if (room.names[c.name] != null) room.names[c.name]!,
      ].join(' & ');
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          room.game.teams
              ? (iWon ? 'Your team won 🎉' : '$sideNames won')
              : (w == me
                    ? 'You won 🎉'
                    : '${room.names[w.name] ?? w.label} won'),
          textAlign: TextAlign.center,
          style: AppType.sectionTitle,
        ),
      );
    }
    if (room.status == LudoRoomStatus.waiting) {
      final seated = room.colorOf(_uid) != null;
      final countdown = ludoAutoStartIn(room);
      // The table starts itself. Any seated client may do it, because the host
      // is often the one who left, and a game only their device can start is
      // the game that sits at one seat for ever.
      if (seated && countdown == 0 && !_autoStarting) {
        _autoStarting = true;
        autoStartLudoRoom(widget.roomId).whenComplete(() {
          if (mounted) _autoStarting = false;
        });
      }
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text(
              '${room.seats.length} of ${room.seatCap} seated. Share this '
              'game with a friend to fill the board.',
              textAlign: TextAlign.center,
              style: AppType.secondary,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (room.stake > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  room.pot > 0
                      ? 'Pot: ${formatCoins(room.pot)} coins'
                      : '${formatCoins(room.stake)} coins each — '
                            'winner takes the pot',
                  textAlign: TextAlign.center,
                  style: AppType.label.copyWith(color: kPakGreen),
                ),
              ),
            if (countdown != null)
              Text(
                countdown > 0 ? 'Computers join in ${countdown}s' : 'Starting…',
                textAlign: TextAlign.center,
                style: AppType.caption,
              ),
            const SizedBox(height: AppSpacing.sm),
            if (seated) ...[
              Wrap(
                spacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: room.isFull
                        ? null
                        : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => LudoInviteSheet(room: room),
                          ),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Invite'),
                  ),
                  OutlinedButton.icon(
                    onPressed: room.isFull
                        ? null
                        : () => addLudoBot(widget.roomId),
                    icon: const Icon(Icons.smart_toy_outlined, size: 18),
                    label: const Text('Add computer'),
                  ),
                  ElevatedButton.icon(
                    // Always available: with fewer than two seats this fills
                    // the rest with computers rather than staying disabled,
                    // which is what left players stuck at a dead button.
                    onPressed: () => room.seats.length >= 2
                        ? startLudoRoom(widget.roomId)
                        : autoStartLudoRoom(widget.roomId),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start now'),
                  ),
                ],
              ),
            ] else
              Text('Joining…', style: AppType.caption),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Auto-play has to be VISIBLE while it runs. A board that moves on its
        // own with nothing on screen to explain it reads as a bug, and the way
        // out has to be one tap from where the player is already looking.
        if (_autoPlay)
          Container(
            width: double.infinity,
            color: kPakGreen.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(Icons.smart_toy, size: 16, color: kPakGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Auto-play is on — your turns are played for you.',
                    style: AppType.caption,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _autoPlay = false;
                    _autoTurn = null;
                  }),
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              // Tapping the die rolls, which is what a player reaches for first.
              LudoDice(
                value: dice,
                rolling: _busy,
                enabled: myTurn && dice == null,
                onTap: _roll,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: myTurn
                    ? (dice == null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _busy ? null : _roll,
                                  icon: const Icon(Icons.casino),
                                  label: const Text('Roll'),
                                ),
                                Builder(
                                  builder: (context) {
                                    final left = ludoSecondsLeft(room);
                                    if (left == null || left > 20) {
                                      return const SizedBox.shrink();
                                    }
                                    // Only shown once it matters, so it reads as a
                                    // warning rather than constant pressure.
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        top: AppSpacing.xs,
                                      ),
                                      child: Text(
                                        'Rolling for you in ${left}s',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: left <= 10
                                              ? AppColors.error
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            )
                          : Text(
                              moves.isEmpty
                                  ? 'No move with that roll — passing…'
                                  : 'Tap a highlighted token to move.',
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
                          Builder(
                            builder: (context) {
                              final left = ludoSecondsLeft(room);
                              if (isLudoBotSeat(
                                room,
                                room.game.currentPlayer,
                              )) {
                                return Text(
                                  'The computer is thinking.',
                                  style: AppType.caption,
                                );
                              }
                              return Text(
                                left == null
                                    ? 'Waiting…'
                                    : 'Their turn is played automatically in '
                                          '${left}s',
                                style: AppType.caption,
                              );
                            },
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
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
