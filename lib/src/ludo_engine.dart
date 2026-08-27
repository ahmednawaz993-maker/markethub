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

/// The four seats. Order matters: play proceeds around the board in this order.
enum LudoColor {
  red('Red'),
  green('Green'),
  yellow('Yellow'),
  blue('Blue');

  const LudoColor(this.label);
  final String label;

  /// Where this colour joins the shared 52-square ring.
  int get startCell => switch (this) {
    LudoColor.red => 0,
    LudoColor.green => 13,
    LudoColor.yellow => 26,
    LudoColor.blue => 39,
  };
}

/// Squares nobody can be captured on: the four starts and the four stars.
const Set<int> kLudoSafeCells = {0, 8, 13, 21, 26, 34, 39, 47};

/// Length of the shared ring.
const int kLudoRingLength = 52;

/// Progress value meaning "in the yard, not yet on the board".
const int kLudoInYard = -1;

/// Progress 0..50 is the ring, 51..55 the five private home squares, and 56 is
/// home itself (the centre). 51 ring cells rather than 52: a token turns into
/// its own column one square short of completing the circuit, which is why it
/// never lands back on its own start.
const int kLudoLastRingStep = 50;
const int kLudoHomeColumnLength = 5;
const int kLudoHome = 56;

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
  int? ringCell(LudoColor c) =>
      onRing ? (c.startCell + progress) % kLudoRingLength : null;
}

/// A legal move: move [tokenIndex] of [color] to [to].
class LudoMove {
  const LudoMove({
    required this.color,
    required this.tokenIndex,
    required this.from,
    required this.to,
    required this.captures,
  });

  final LudoColor color;
  final int tokenIndex;
  final LudoTokenPos from;
  final LudoTokenPos to;

  /// Opponent tokens sent back to the yard, as (colour, token index).
  final List<({LudoColor color, int tokenIndex})> captures;

  bool get isEntry => from.inYard;
  bool get reachesHome => to.isHome;

  @override
  String toString() =>
      '${color.name}#$tokenIndex ${from.progress}->${to.progress}'
      '${captures.isEmpty ? '' : ' x${captures.length}'}';
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
  });

  /// Seats in play, in turn order. Two, three or four.
  final List<LudoColor> players;

  /// Progress of each colour's four tokens.
  final Map<LudoColor, List<int>> positions;

  /// Index into [players].
  final int turn;

  /// Sixes rolled in a row by the current player; three forfeits the turn.
  final int consecutiveSixes;

  /// Colours that have got all four tokens home, in finishing order.
  final List<LudoColor> winners;

  /// The dice value awaiting a move, or null when a roll is due.
  final int? lastDice;

  LudoColor get currentPlayer => players[turn];

  bool get isOver => winners.length >= players.length - 1;

  static LudoGame newGame(List<LudoColor> players) {
    assert(players.length >= 2 && players.length <= 4);
    return LudoGame(
      players: List.unmodifiable(players),
      positions: {
        for (final c in players) c: List.filled(4, kLudoInYard, growable: false),
      },
      turn: 0,
      consecutiveSixes: 0,
      winners: const [],
      lastDice: null,
    );
  }

  /// Tokens of [color] that have reached home.
  int homeCount(LudoColor color) =>
      positions[color]!.where((p) => p == kLudoHome).length;

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
      if (from.isHome) continue;

      final int toProgress;
      if (from.inYard) {
        // Only a six opens the yard, and it places the token on the start
        // square rather than six steps along it.
        if (dice != 6) continue;
        toProgress = 0;
      } else {
        toProgress = from.progress + dice;
        // Home must be reached exactly. Overshooting is simply not a move.
        if (toProgress > kLudoHome) continue;
      }

      final to = LudoTokenPos(toProgress);

      // A token cannot land on one of its own — that would stack two tokens on
      // a square and make captures ambiguous.
      final destRing = to.ringCell(color);
      if (destRing != null) {
        final ownCollision = mine.asMap().entries.any(
          (e) =>
              e.key != i &&
              LudoTokenPos(e.value).ringCell(color) == destRing,
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
        ),
      );
    }
    return moves;
  }

  /// Opponents standing on [ringCell] that this move would send home.
  /// Nothing is captured on a safe square, in the yard, or off the ring.
  List<({LudoColor color, int tokenIndex})> _capturesAt(
    LudoColor mover,
    int? ringCell,
  ) {
    if (ringCell == null || kLudoSafeCells.contains(ringCell)) return const [];
    final out = <({LudoColor color, int tokenIndex})>[];
    for (final other in players) {
      if (other == mover) continue;
      final theirs = positions[other]!;
      for (var i = 0; i < theirs.length; i++) {
        if (LudoTokenPos(theirs[i]).ringCell(other) == ringCell) {
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
    if (next[move.color]!.every((p) => p == kLudoHome) &&
        !newWinners.contains(move.color)) {
      newWinners.add(move.color);
    }

    // A six, a capture or getting a token home all earn another roll. Three
    // sixes in a row is the exception — it ends the turn regardless.
    final rolledSix = lastDice == 6;
    final earnedAnother =
        (rolledSix && consecutiveSixes < 3) ||
        move.captures.isNotEmpty ||
        move.reachesHome;

    return LudoGame(
      players: players,
      positions: next,
      turn: earnedAnother
          ? turn
          : _nextSeat(turn, newWinners),
      consecutiveSixes: earnedAnother && rolledSix ? consecutiveSixes : 0,
      winners: newWinners,
      lastDice: null,
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
    );
  }
}
