part of '../main.dart';

// Saanp Seerhi — Snakes and Ladders.
//
// The other board game everybody in Pakistan already knows, and the reason to
// add it rather than something cleverer: nobody needs the rules explained, so
// a player can be playing eight seconds after tapping the tile.
//
// Pure logic, no widgets and no Firestore, for the same reason as the Ludo
// engine — the rules have to be evaluated identically wherever they run, and
// anything that knows about pixels cannot be reused.
//
// RULES, as the game is actually played here (they differ from the Milton
// Bradley version in ways that matter):
//
//  * No six is needed to start. You are on the board from your first roll.
//    Needing a six to begin is a Ludo rule that got borrowed by some printed
//    boards; it turns the opening into several minutes of nothing happening.
//  * A six earns another turn. Three sixes running forfeits it, exactly as in
//    Ludo — without that cap a lucky streak has no end.
//  * 100 must be reached EXACTLY. An overshoot does not move at all, which is
//    what makes the last few squares tense instead of a formality.
//  * Landing on a ladder's foot climbs it; landing on a snake's head slides
//    down. Passing over either does nothing.

/// A snake or a ladder: you land on [from] and end up at [to].
///
/// One type for both, because they are the same rule in two directions and
/// splitting them into two lists only creates a way for them to disagree.
class SnakeOrLadder {
  const SnakeOrLadder(this.from, this.to);

  final int from;
  final int to;

  bool get isLadder => to > from;
  bool get isSnake => to < from;
}

/// The board everybody has played on.
///
/// Chosen so the two halves are not symmetrical — a board where every ladder
/// has a matching snake plays like a coin toss with extra steps. There are
/// deliberately more snakes in the last quarter, so a lead near the end is
/// worth something but never safe.
const List<SnakeOrLadder> kSnakesAndLadders = [
  // Ladders.
  SnakeOrLadder(2, 23),
  SnakeOrLadder(8, 34),
  SnakeOrLadder(20, 77),
  SnakeOrLadder(32, 68),
  SnakeOrLadder(41, 79),
  SnakeOrLadder(74, 88),
  SnakeOrLadder(82, 100),
  SnakeOrLadder(85, 95),
  // Snakes.
  SnakeOrLadder(29, 9),
  SnakeOrLadder(38, 15),
  SnakeOrLadder(47, 5),
  SnakeOrLadder(53, 33),
  SnakeOrLadder(62, 19),
  SnakeOrLadder(86, 54),
  SnakeOrLadder(92, 51),
  SnakeOrLadder(97, 61),
];

/// The last square. Reaching it exactly wins.
const int kSnakesHome = 100;

/// How many squares a full board has, ten by ten.
const int kSnakesSide = 10;

/// Where a landing takes you, or null if the square is plain.
SnakeOrLadder? snakeOrLadderAt(int square) {
  for (final s in kSnakesAndLadders) {
    if (s.from == square) return s;
  }
  return null;
}

/// The grid position of a square, counting from the BOTTOM-LEFT and snaking.
///
/// Square 1 is bottom-left, 10 is bottom-right, 11 sits directly above 10, and
/// so on — the boustrophedon every printed board uses. Returned as (row, col)
/// from the TOP so it can be drawn without every caller flipping it.
({int row, int col}) snakesCellOf(int square) {
  final i = square - 1;
  final rowFromBottom = i ~/ kSnakesSide;
  final within = i % kSnakesSide;
  // Odd rows run right-to-left, which is what makes the path continuous.
  final col = rowFromBottom.isEven ? within : kSnakesSide - 1 - within;
  return (row: kSnakesSide - 1 - rowFromBottom, col: col);
}

/// What one roll did, so the board can animate it and the screen can narrate.
class SnakesMove {
  const SnakesMove({
    required this.player,
    required this.dice,
    required this.from,
    required this.landed,
    required this.to,
    required this.jump,
    required this.blocked,
    required this.won,
  });

  final int player;
  final int dice;

  /// Where the piece started.
  final int from;

  /// Where the die alone took it, before any snake or ladder.
  final int landed;

  /// Where it ended up.
  final int to;

  /// The snake or ladder taken, if any.
  final SnakeOrLadder? jump;

  /// True when the roll would have overshot 100 and so nothing moved.
  final bool blocked;

  final bool won;
}

/// A game of Saanp Seerhi.
///
/// Immutable, like the Ludo engine: every transition returns a new game, so a
/// board can hold the previous one and animate between the two.
class SnakesGame {
  const SnakesGame({
    required this.positions,
    required this.turn,
    required this.consecutiveSixes,
    required this.winner,
    required this.lastMove,
  });

  factory SnakesGame.newGame(int players) => SnakesGame(
    positions: List.filled(players, 0, growable: false),
    turn: 0,
    consecutiveSixes: 0,
    winner: null,
    lastMove: null,
  );

  /// Each player's square. 0 means "not yet on the board".
  final List<int> positions;

  final int turn;
  final int consecutiveSixes;

  /// The player who reached 100, or null while the game is on.
  final int? winner;

  /// The last roll, for the board to animate and the screen to describe.
  final SnakesMove? lastMove;

  int get playerCount => positions.length;
  bool get isOver => winner != null;

  /// Applies a roll and returns the game that follows it.
  SnakesGame roll(int dice) {
    assert(dice >= 1 && dice <= 6);
    if (isOver) return this;

    final sixes = dice == 6 ? consecutiveSixes + 1 : 0;
    final me = turn;
    final from = positions[me];

    // Three sixes running: the turn is burnt and nothing moves. Without this a
    // player could in principle never hand the dice on.
    if (sixes >= 3) {
      return SnakesGame(
        positions: positions,
        turn: (me + 1) % playerCount,
        consecutiveSixes: 0,
        winner: null,
        lastMove: SnakesMove(
          player: me,
          dice: dice,
          from: from,
          landed: from,
          to: from,
          jump: null,
          blocked: true,
          won: false,
        ),
      );
    }

    final landed = from + dice;
    // Home must be exact. Overshooting is not a move — the piece stays put and
    // the turn passes, which is what makes the endgame worth playing.
    if (landed > kSnakesHome) {
      return SnakesGame(
        positions: positions,
        turn: (me + 1) % playerCount,
        consecutiveSixes: 0,
        winner: null,
        lastMove: SnakesMove(
          player: me,
          dice: dice,
          from: from,
          landed: from,
          to: from,
          jump: null,
          blocked: true,
          won: false,
        ),
      );
    }

    final jump = snakeOrLadderAt(landed);
    final to = jump?.to ?? landed;
    final next = [...positions]..[me] = to;
    final won = to == kSnakesHome;

    return SnakesGame(
      positions: List.unmodifiable(next),
      // A six earns another turn — but not after winning, and not if the six
      // was the third in a row, which is handled above.
      turn: (dice == 6 && !won) ? me : (me + 1) % playerCount,
      consecutiveSixes: won ? 0 : sixes,
      winner: won ? me : null,
      lastMove: SnakesMove(
        player: me,
        dice: dice,
        from: from,
        landed: landed,
        to: to,
        jump: jump,
        blocked: false,
        won: won,
      ),
    );
  }
}
