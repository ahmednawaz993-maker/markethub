part of '../main.dart';

// Tic-tac-toe.
//
// Added as the short game. Ludo is twenty minutes and Saanp Seerhi is five;
// this is the one you play twice while waiting for someone to reply to a
// message, and the reason to have it is that it costs nothing to open and
// nothing to abandon.
//
// The opponent is solved rather than heuristic. Tic-tac-toe has 5,478
// reachable positions, which is small enough to search exhaustively on a phone
// in well under a millisecond — so "Hard" is not hard-ish, it is perfect: it
// cannot be beaten, only drawn. That is worth doing properly, because a bot
// that loses to a fork it did not see is more annoying than one that never
// loses at all.

/// A mark on the board.
enum TicMark { x, o }

/// The nine cells, row by row. Null is empty.
typedef TicBoard = List<TicMark?>;

/// The eight ways to win.
const List<List<int>> kTicLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
  [0, 4, 8], [2, 4, 6], // diagonals
];

/// The winning line, or null if nobody has one yet.
List<int>? ticWinningLine(TicBoard b) {
  for (final line in kTicLines) {
    final a = b[line[0]];
    if (a != null && b[line[1]] == a && b[line[2]] == a) return line;
  }
  return null;
}

TicMark? ticWinner(TicBoard b) {
  final line = ticWinningLine(b);
  return line == null ? null : b[line[0]];
}

bool ticIsFull(TicBoard b) => b.every((c) => c != null);
bool ticIsOver(TicBoard b) => ticWinner(b) != null || ticIsFull(b);

TicMark ticOther(TicMark m) => m == TicMark.x ? TicMark.o : TicMark.x;

/// An empty board.
TicBoard ticNewBoard() => List<TicMark?>.filled(9, null, growable: false);

/// How well [me] can do from here, and in how many moves.
///
/// Depth is part of the score on purpose: without it the search is indifferent
/// between winning now and winning in three moves, so a solved opponent will
/// idly pass up an immediate win and look broken rather than clever. Likewise
/// it prefers to lose LATER, which makes a lost game last long enough to feel
/// like a game.
int _score(TicBoard b, TicMark me, TicMark turn, int depth) {
  final w = ticWinner(b);
  if (w == me) return 10 - depth;
  if (w != null) return depth - 10;
  if (ticIsFull(b)) return 0;

  var best = turn == me ? -100 : 100;
  for (var i = 0; i < 9; i++) {
    if (b[i] != null) continue;
    b[i] = turn;
    final s = _score(b, me, ticOther(turn), depth + 1);
    b[i] = null;
    best = turn == me
        ? (s > best ? s : best)
        : (s < best ? s : best);
  }
  return best;
}

/// The best move for [me], or null on a finished board.
///
/// [rng] breaks ties, so the perfect opponent does not play the identical
/// game every time — a bot that always opens in the same corner is solved by
/// the player after three rounds, which is a different way of being beatable.
int? ticBestMove(TicBoard board, TicMark me, {math.Random? rng}) {
  if (ticIsOver(board)) return null;
  final work = [...board];
  var best = -1000;
  final ties = <int>[];
  for (var i = 0; i < 9; i++) {
    if (work[i] != null) continue;
    work[i] = me;
    final s = _score(work, me, ticOther(me), 1);
    work[i] = null;
    if (s > best) {
      best = s;
      ties
        ..clear()
        ..add(i);
    } else if (s == best) {
      ties.add(i);
    }
  }
  if (ties.isEmpty) return null;
  return ties[(rng ?? math.Random()).nextInt(ties.length)];
}

/// A move for the easy opponent: it takes a win, blocks a loss, and otherwise
/// plays at random.
///
/// Deliberately NOT a weakened search. A bot that plays perfectly and then
/// throws a move away at random feels like it is cheating in reverse; one that
/// simply does not think ahead feels like a beginner, which is what it is
/// supposed to be.
int? ticEasyMove(TicBoard board, TicMark me, {math.Random? rng}) {
  if (ticIsOver(board)) return null;
  final r = rng ?? math.Random();
  final work = [...board];

  for (final mark in [me, ticOther(me)]) {
    for (var i = 0; i < 9; i++) {
      if (work[i] != null) continue;
      work[i] = mark;
      final wins = ticWinner(work) == mark;
      work[i] = null;
      if (wins) return i;
    }
  }
  final free = [
    for (var i = 0; i < 9; i++)
      if (board[i] == null) i,
  ];
  return free.isEmpty ? null : free[r.nextInt(free.length)];
}
