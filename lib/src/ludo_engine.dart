part of '../main.dart';

// Ludo rules engine.
//
// Pure logic — no widgets, no Firestore. That separation is the whole point:
// in a multiplayer game the rules have to be evaluated identically on every
// device and, eventually, on a server that nobody can cheat. Anything that
// knows about pixels or documents cannot be reused there.
//
// The state is small and JSON-round-trippable for exactly that reason: a whole
// game fits in one Firestore document, and a move is a state transition both
// players can verify.
//
// RULES IMPLEMENTED (the Pakistani/South Asian table rules, which differ from
// the Western "Parcheesi" variants in several places):
//
//  * Four tokens each; a six is needed to bring one out of the yard.
//  * A six earns another turn. So does capturing. So does getting a token home.
//  * Three sixes in a row forfeits the turn — otherwise a lucky streak is
//    unbounded.
//  * Landing on an opponent on an unsafe square sends it back to the yard.
//  * Eight safe squares: the four coloured starts and the four stars.
//  * A token must reach home on an EXACT roll; overshooting is not a legal
//    move, which is what makes the endgame tense.

/// The seats. Order matters: play proceeds around the board in this order.
///
/// The first four are the classic board. Purple and orange exist only on the
/// six-player hexagon — a four-player game never seats them, and every switch
/// over this enum has to say what it does with them anyway, which is the
/// compiler making sure the six-seat board was thought about everywhere.
enum LudoColor {
  red('Red'),
  green('Green'),
  yellow('Yellow'),
  blue('Blue'),
  purple('Purple'),
  orange('Orange');

  const LudoColor(this.label);
  final String label;
}

/// Progress value meaning "in the yard, not yet on the board".
const int kLudoInYard = -1;

/// How many private squares a colour runs down before home. Same on both
/// boards; it is what makes the endgame feel identical.
const int kLudoHomeColumnLength = 5;

/// The geometry of a board.
///
/// Everything here is DERIVED from the seat count and ring length rather than
/// listed, and that is the point: the four-player values it produces are
/// exactly the constants this game shipped with for months (ring 52, starts at
/// 0/13/26/39, safe squares {0,8,13,21,26,34,39,47}, last ring step 50, home
/// 56). A test asserts that equality, so the six-player board could be added
/// without any chance of quietly moving the four-player one.
class LudoBoardSpec {
  const LudoBoardSpec({required this.seats, required this.ringLength});

  final int seats;
  final int ringLength;

  /// The classic cross: four seats, thirteen cells apart.
  static const four = LudoBoardSpec(seats: 4, ringLength: 52);

  /// The hexagon: six seats, twelve cells apart.
  static const six = LudoBoardSpec(seats: 6, ringLength: 72);

  static LudoBoardSpec forSeats(int n) => n > 4 ? six : four;

  /// Cells between one colour's start and the next.
  int get spacing => ringLength ~/ seats;

  /// The last ring square before a token turns into its own column. Two short
  /// of a full circuit, so a token never lands back on its own start.
  int get lastRingStep => ringLength - 2;

  /// The centre.
  int get home => lastRingStep + kLudoHomeColumnLength + 1;

  /// The colours this board seats, in turn order.
  List<LudoColor> get colours => LudoColor.values.take(seats).toList();

  /// Where a colour joins the shared ring.
  int startCellOf(LudoColor c) => (c.index * spacing) % ringLength;

  /// Squares nobody can be captured on: every colour's start, plus a star five
  /// cells short of the NEXT colour's start — the square you most want to reach
  /// before running into somebody else's home stretch.
  Set<int> get safeCells => {
    for (var i = 0; i < seats; i++) ...[
      i * spacing,
      i * spacing + spacing - 5,
    ],
  };

  /// Arrow-mode shortcuts, tail -> head. One per arm, each a jump of seven,
  /// two cells past each colour's start. On the four-player board this
  /// reproduces {2: 9, 15: 22, 28: 35, 41: 48} exactly.
  Map<int, int> get arrows => {
    for (var i = 0; i < seats; i++)
      i * spacing + 2: (i * spacing + 9) % ringLength,
  };
}

/// Reading a colour's start on the CLASSIC board.
///
/// Convenience for the four-player painter and the tests written against it.
/// The engine never uses this — it asks its own spec — because a six-player
/// game that read four-player geometry would compute silently wrong squares
/// rather than failing.
extension LudoColorClassicBoard on LudoColor {
  int get startCell => LudoBoardSpec.four.startCellOf(this);
}

/// The classic board's values, kept as names because most of the game and all
/// of its older tests speak in them.
const int kLudoRingLength = 52;
const int kLudoLastRingStep = 50;
const int kLudoHome = 56;
final Set<int> kLudoSafeCells = LudoBoardSpec.four.safeCells;
final Map<int, int> kLudoArrows = LudoBoardSpec.four.arrows;

/// One token's position, expressed as progress along its OWN path.
///
/// Using progress relative to each colour's start — rather than an absolute
/// board cell — is what keeps the rules symmetrical: every colour's journey is
/// identically 0→57, and only [ringCell] translates back to shared geometry.
extension type const LudoTokenPos(int progress) {
  bool get inYard => progress == kLudoInYard;
  bool get onRing => progress >= 0 && progress <= kLudoLastRingStep;
  bool get inHomeColumn => progress > kLudoLastRingStep && progress < kLudoHome;
  bool get isHome => progress == kLudoHome;

  /// The shared-ring cell this token occupies, or null when it is in the yard,
  /// its home column, or finished — none of which can be captured or block.
  ///
  /// Takes the board, because the same progress is a different square on the
  /// hexagon. It defaults to the classic board only for the four-player painter
  /// and its tests; the engine always passes its own spec.
  int? ringCell(LudoColor c, [LudoBoardSpec spec = LudoBoardSpec.four]) =>
      progress >= 0 && progress <= spec.lastRingStep
      ? (spec.startCellOf(c) + progress) % spec.ringLength
      : null;

  bool onRingOf(LudoBoardSpec spec) =>
      progress >= 0 && progress <= spec.lastRingStep;
  bool isHomeOf(LudoBoardSpec spec) => progress == spec.home;
}

/// Who partners whom in a team game.
///
/// Partners sit OPPOSITE each other, which is the only pairing that works: the
/// turn order runs red, green, yellow, blue round the board, so opposite
/// partners alternate with their opponents instead of taking two turns back to
/// back. Adjacent pairings would hand each team a double move.
const Map<LudoColor, LudoColor> kLudoPartners = {
  LudoColor.red: LudoColor.yellow,
  LudoColor.yellow: LudoColor.red,
  LudoColor.green: LudoColor.blue,
  LudoColor.blue: LudoColor.green,
};

/// A legal move: move [tokenIndex] of [color] to [to].
class LudoMove {
  const LudoMove({
    required this.color,
    required this.tokenIndex,
    required this.from,
    required this.to,
    required this.captures,
    this.viaArrow = false,
  });

  final LudoColor color;
  final int tokenIndex;
  final LudoTokenPos from;
  final LudoTokenPos to;

  /// Opponent tokens sent back to the yard, as (colour, token index).
  final List<({LudoColor color, int tokenIndex})> captures;

  /// True when the token landed on an arrow tail and was carried to its head.
  /// [to] is already the head, so the board animates to where it ends up.
  final bool viaArrow;

  bool get isEntry => from.inYard;
  bool get reachesHome => to.isHome;

  @override
  String toString() =>
      '${color.name}#$tokenIndex ${from.progress}->${to.progress}'
      '${captures.isEmpty ? '' : ' x${captures.length}'}'
      '${viaArrow ? ' >>' : ''}';
}

/// How a table is playing. All three use the same board and the same movement
/// rules; they differ in how long a game lasts and what it takes to finish.
enum LudoMode {
  /// The full game: four tokens each, all four must come home.
  classic('Classic', 4, false, 'Four tokens each. Bring all four home.'),

  /// Two tokens each. Roughly half the length, same rules otherwise — the
  /// honest way to make a game short, rather than a timer that cuts it off
  /// mid-play and declares a winner on points.
  quick('Quick', 2, false, 'Two tokens each — a much shorter game.'),

  /// Four tokens, and you must send an opponent home before ANY of your tokens
  /// may enter your home column. A long-standing variant: it stops a player
  /// racing round untouched and forces at least one confrontation.
  master(
    'Master',
    4,
    true,
    'Four tokens, and you must capture an opponent before you can go home.',
  ),

  /// Four tokens, plus four one-way shortcuts around the ring. Landing on an
  /// arrow's tail carries the token to its head and earns another roll.
  arrow(
    'Arrow',
    4,
    false,
    'Shortcuts on the board. Land on an arrow and ride it, then roll again.',
    arrows: true,
  );

  const LudoMode(
    this.label,
    this.tokens,
    this.captureToEnterHome,
    this.blurb, {
    this.arrows = false,
  });

  final String label;
  final int tokens;
  final bool captureToEnterHome;
  final String blurb;

  /// Whether [kLudoArrows] is live for this variant.
  final bool arrows;
}

/// Picks a move the way the server's bot does.
///
/// A DELIBERATE MIRROR of chooseBotMove in functions/ludo_logic.js, scoring
/// included. It is used for auto-play — the toggle that plays your turns while
/// you watch — and keeping it identical to the server means a player who turns
/// auto-play on gets the same decisions the computer would have made for them
/// on timeout. Two different rankings would mean the board played differently
/// depending on whether you were connected, which is exactly the kind of
/// inconsistency nobody can report usefully.
///
/// Not a search. Ludo is mostly dice; a deep search would win too often to be
/// fun, and the obvious move is what a person expects to see played.
/// Order: take a capture, bring a token home, leave the yard, reach safety,
/// otherwise push the leading token on.
LudoMove? chooseLudoMove(
  LudoColor color,
  List<LudoMove> moves, [
  LudoBoardSpec spec = LudoBoardSpec.four,
]) {
  if (moves.isEmpty) return null;
  LudoMove? best;
  var bestScore = double.negativeInfinity;
  for (final m in moves) {
    var score = m.captures.length * 100.0;
    if (m.to.isHomeOf(spec)) score += 80;
    if (m.from.inYard) score += 50;
    final dest = m.to.ringCell(color, spec);
    if (dest != null && spec.safeCells.contains(dest)) score += 20;
    score += m.to.progress / 2;
    if (score > bestScore) {
      bestScore = score;
      best = m;
    }
  }
  return best;
}

/// A complete game state. Immutable; every transition returns a new one.
class LudoGame {
  const LudoGame({
    required this.players,
    required this.positions,
    required this.turn,
    required this.consecutiveSixes,
    required this.winners,
    required this.lastDice,
    this.mode = LudoMode.classic,
    this.hasCaptured = const {},
    this.teams = false,
  });

  /// The board this game is played on, decided by how many are seated.
  ///
  /// Derived rather than stored: the seat count already says which board it is,
  /// and a stored spec could drift out of step with the players list on an old
  /// document.
  LudoBoardSpec get spec => LudoBoardSpec.forSeats(players.length);

  /// Whether this table is playing 2v2.
  ///
  /// A separate flag rather than another [LudoMode] value, because it is a
  /// different axis: a team game is still Classic, Master, Quick or Arrow. Yalla
  /// Ludo models it the same way — a mode grid crossed with 2&4 players or
  /// Team, not a single list of five.
  final bool teams;

  /// The variant being played.
  final LudoMode mode;

  /// Colours that have sent an opponent home at least once. Only consulted in
  /// [LudoMode.master], where it unlocks the home column.
  final Set<LudoColor> hasCaptured;

  /// Seats in play, in turn order. Two, three or four.
  final List<LudoColor> players;

  /// Progress of each colour's tokens — four, or two in Quick.
  final Map<LudoColor, List<int>> positions;

  /// Index into [players].
  final int turn;

  /// Sixes rolled in a row by the current player; three forfeits the turn.
  final int consecutiveSixes;

  /// Colours that have got every token home, in finishing order.
  final List<LudoColor> winners;

  /// The dice value awaiting a move, or null when a roll is due.
  final int? lastDice;

  LudoColor get currentPlayer => players[turn];

  /// The partner of [c] in this game, or null in a solo game.
  LudoColor? partnerOf(LudoColor c) =>
      teams ? kLudoPartners[c] : null;

  /// True when [a] and [b] are on the same side. A colour is its own ally, so
  /// the existing "cannot land on your own token" checks keep working.
  bool areAllies(LudoColor a, LudoColor b) =>
      a == b || (teams && kLudoPartners[a] == b);

  /// The colours that have won, as a set — both partners in a team game.
  Set<LudoColor> get winningSide {
    if (winners.isEmpty) return const {};
    if (!teams) return {winners.first};
    final w = winners.first;
    return {w, ?kLudoPartners[w]};
  }

  /// Whether the result is settled and the table should stop.
  ///
  /// A solo table ends the moment someone comes home first — that is how this
  /// app has always played it, and the win banner says so. A TEAM table must
  /// not: one partner finishing is half a result, and ending there would rob
  /// the other side of a game they could still win.
  bool get isDecided => teams ? isOver : winners.isNotEmpty;

  /// In a team game the race ends when one SIDE is completely home; otherwise
  /// when only one player is still going.
  bool get isOver {
    if (!teams) return winners.length >= players.length - 1;
    for (final c in players) {
      final p = kLudoPartners[c];
      if (p != null && winners.contains(c) && winners.contains(p)) return true;
    }
    return false;
  }

  static LudoGame newGame(
    List<LudoColor> players, {
    LudoMode mode = LudoMode.classic,
    bool teams = false,
  }) {
    assert(players.length >= 2 && players.length <= 6);
    // 2v2 needs four seats. A team game with three players would leave one side
    // a player short, so the flag simply does not apply until the table fills.
    final teamed = teams && players.length == 4;
    return LudoGame(
      players: List.unmodifiable(players),
      positions: {
        for (final c in players)
          c: List.filled(mode.tokens, kLudoInYard, growable: false),
      },
      turn: 0,
      consecutiveSixes: 0,
      winners: const [],
      lastDice: null,
      mode: mode,
      hasCaptured: const {},
      teams: teamed,
    );
  }

  /// Tokens of [color] that have reached home.
  int homeCount(LudoColor color) =>
      positions[color]!.where((p) => p == spec.home).length;

  /// Every move [currentPlayer] may legally make with [dice].
  ///
  /// An empty list is a legal outcome, not an error — it means the turn passes,
  /// which happens constantly when a player has everything in the yard and did
  /// not roll a six.
  List<LudoMove> legalMoves(int dice) {
    assert(dice >= 1 && dice <= 6);
    final color = currentPlayer;
    final mine = positions[color]!;
    final moves = <LudoMove>[];

    for (var i = 0; i < mine.length; i++) {
      final from = LudoTokenPos(mine[i]);
      if (from.isHomeOf(spec)) continue;

      final int toProgress;
      if (from.inYard) {
        // Only a six opens the yard, and it places the token on the start
        // square rather than six steps along it.
        if (dice != 6) continue;
        toProgress = 0;
      } else {
        toProgress = from.progress + dice;
        // Home must be reached exactly. Overshooting is simply not a move.
        if (toProgress > spec.home) continue;
        // Master: the home column stays shut until this colour has sent an
        // opponent back to the yard. The token can still travel the ring — it
        // just cannot turn in, which is the whole point of the variant.
        //
        // Mirrored in functions/ludo_logic.js, because the server rolls and
        // plays the bots. If the two disagree, a player is offered a move the
        // server will refuse.
        if (mode.captureToEnterHome &&
            toProgress > spec.lastRingStep &&
            !hasCaptured.contains(color)) {
          continue;
        }
      }

      // Arrow: resolved HERE rather than when the move is applied, so `to` is
      // already the head. Everything downstream — the own-token check, the
      // capture check and the board animation — then works on where the token
      // actually ends up, not where it touched down.
      final jumped = arrowJump(color, toProgress);
      final finalProgress = jumped ?? toProgress;
      final to = LudoTokenPos(finalProgress);

      // A token cannot land on one of its own — that would stack two tokens on
      // a square and make captures ambiguous.
      final destRing = to.ringCell(color, spec);
      if (destRing != null) {
        final ownCollision = mine.asMap().entries.any(
          (e) =>
              e.key != i &&
              LudoTokenPos(e.value).ringCell(color, spec) == destRing,
        );
        if (ownCollision) continue;
      }

      moves.add(
        LudoMove(
          color: color,
          tokenIndex: i,
          from: from,
          to: to,
          captures: _capturesAt(color, destRing),
          viaArrow: jumped != null,
        ),
      );
    }
    return moves;
  }

  /// The progress an arrow carries a token on to, or null if none applies.
  ///
  /// Refuses any jump that would carry a token past its own turn-off into the
  /// home column ([kLudoLastRingStep]). Home has to be reached by an exact
  /// roll, and a shortcut that skipped that would let a token stroll in.
  int? arrowJump(LudoColor color, int progress) {
    if (!mode.arrows) return null;
    if (progress < 0 || progress > spec.lastRingStep) return null;
    final ring = LudoTokenPos(progress).ringCell(color, spec);
    if (ring == null) return null;
    final head = spec.arrows[ring];
    if (head == null) return null;
    final jumped =
        progress + ((head - ring + spec.ringLength) % spec.ringLength);
    if (jumped > spec.lastRingStep) return null;
    return jumped;
  }

  /// Opponents standing on [ringCell] that this move would send home.
  /// Nothing is captured on a safe square, in the yard, or off the ring.
  List<({LudoColor color, int tokenIndex})> _capturesAt(
    LudoColor mover,
    int? ringCell,
  ) {
    if (ringCell == null || spec.safeCells.contains(ringCell)) return const [];
    final out = <({LudoColor color, int tokenIndex})>[];
    for (final other in players) {
      // A colour never captures itself, and in a team game never its partner.
      // Without this a player would send their own side home, which is the
      // single most confusing thing a team mode can do.
      if (areAllies(mover, other)) continue;
      final theirs = positions[other]!;
      for (var i = 0; i < theirs.length; i++) {
        if (LudoTokenPos(theirs[i]).ringCell(other, spec) == ringCell) {
          out.add((color: other, tokenIndex: i));
        }
      }
    }
    return out;
  }

  /// Applies [move] and hands the turn on according to the rules.
  LudoGame applyMove(LudoMove move) {
    assert(move.color == currentPlayer);
    final next = {
      for (final c in players) c: List<int>.from(positions[c]!),
    };
    next[move.color]![move.tokenIndex] = move.to.progress;
    for (final cap in move.captures) {
      next[cap.color]![cap.tokenIndex] = kLudoInYard;
    }

    final newWinners = List<LudoColor>.from(winners);
    final captured = move.captures.isEmpty
        ? hasCaptured
        : {...hasCaptured, move.color};
    if (next[move.color]!.every((p) => p == spec.home) &&
        !newWinners.contains(move.color)) {
      newWinners.add(move.color);
    }

    // A six, a capture or getting a token home all earn another roll. Three
    // sixes in a row is the exception — it ends the turn regardless.
    final rolledSix = lastDice == 6;
    final earnedAnother =
        (rolledSix && consecutiveSixes < 3) ||
        move.captures.isNotEmpty ||
        move.to.progress == spec.home ||
        move.viaArrow;

    return LudoGame(
      players: players,
      positions: next,
      turn: earnedAnother ? turn : _nextSeat(turn, newWinners),
      consecutiveSixes: earnedAnother && rolledSix ? consecutiveSixes : 0,
      winners: newWinners,
      lastDice: null,
      mode: mode,
      hasCaptured: captured,
      teams: teams,
    );
  }

  /// Records a roll. Returns the new state plus the moves it allows, so the UI
  /// can show "no moves" without having to ask twice.
  ({LudoGame game, List<LudoMove> moves}) roll(int dice) {
    assert(dice >= 1 && dice <= 6);
    final sixes = dice == 6 ? consecutiveSixes + 1 : 0;

    // Three sixes running: the turn is burnt, nothing moves. Without this a
    // player could, in principle, never hand the dice on.
    if (sixes >= 3) {
      return (
        game: LudoGame(
          players: players,
          positions: positions,
          turn: _nextSeat(turn, winners),
          consecutiveSixes: 0,
          winners: winners,
          lastDice: null,
          mode: mode,
          hasCaptured: hasCaptured,
          teams: teams,
        ),
        moves: const [],
      );
    }

    final rolled = LudoGame(
      players: players,
      positions: positions,
      turn: turn,
      consecutiveSixes: sixes,
      winners: winners,
      lastDice: dice,
      mode: mode,
      hasCaptured: hasCaptured,
      teams: teams,
    );
    final moves = rolled.legalMoves(dice);
    if (moves.isNotEmpty) return (game: rolled, moves: moves);

    // Nothing to play. A six with no move still keeps the turn (the player
    // rolls again); anything else passes it on.
    return (
      game: LudoGame(
        players: players,
        positions: positions,
        turn: dice == 6 ? turn : _nextSeat(turn, winners),
        consecutiveSixes: dice == 6 ? sixes : 0,
        winners: winners,
        lastDice: null,
        mode: mode,
        hasCaptured: hasCaptured,
        teams: teams,
      ),
      moves: const [],
    );
  }

  /// The next seat that has not already finished.
  int _nextSeat(int from, List<LudoColor> done) {
    var t = from;
    for (var i = 0; i < players.length; i++) {
      t = (t + 1) % players.length;
      if (!done.contains(players[t])) return t;
    }
    return from;
  }

  // -- serialisation: one game fits in one Firestore document ---------------

  Map<String, dynamic> toJson() => {
    'players': [for (final c in players) c.name],
    'positions': {
      for (final e in positions.entries) e.key.name: e.value,
    },
    'turn': turn,
    'sixes': consecutiveSixes,
    'winners': [for (final c in winners) c.name],
    'dice': lastDice,
    'mode': mode.name,
    'captured': [for (final c in hasCaptured) c.name],
    'teams': teams,
  };

  static LudoGame fromJson(Map<String, dynamic> j) {
    LudoColor parse(String s) =>
        LudoColor.values.firstWhere((c) => c.name == s);
    final players = [for (final s in (j['players'] as List)) parse('$s')];
    final rawPos = (j['positions'] as Map).cast<String, dynamic>();
    return LudoGame(
      players: List.unmodifiable(players),
      positions: {
        for (final c in players)
          c: [
            for (final v in (rawPos[c.name] as List? ?? const []))
              (v as num).toInt(),
          ],
      },
      turn: (j['turn'] as num?)?.toInt() ?? 0,
      consecutiveSixes: (j['sixes'] as num?)?.toInt() ?? 0,
      winners: [for (final s in (j['winners'] as List? ?? const [])) parse('$s')],
      lastDice: (j['dice'] as num?)?.toInt(),
      // Older documents predate modes; they are classic games.
      mode: LudoMode.values.firstWhere(
        (m) => m.name == j['mode'],
        orElse: () => LudoMode.classic,
      ),
      hasCaptured: {
        for (final s in (j['captured'] as List? ?? const [])) parse('$s'),
      },
      // Older documents predate teams; they are solo games.
      teams: j['teams'] == true,
    );
  }
}
