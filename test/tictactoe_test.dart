// Tic-tac-toe, and one claim worth proving.
//
// "Hard" is advertised as unbeatable. That is a strong thing to say in an app,
// and it is either true or it is a lie a player will catch — so it is checked
// exhaustively rather than spot-checked: every game the opponent can be made
// to play, against every possible line of play, must end in a win or a draw.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

TicBoard _board(String s) {
  // "x o|. x .|o . x" — dots are empty. Written out so a test reads like the
  // position it is about.
  final cells = s.replaceAll('|', '').replaceAll(' ', '').split('');
  expect(cells, hasLength(9));
  return [
    for (final c in cells)
      c == 'x'
          ? TicMark.x
          : c == 'o'
          ? TicMark.o
          : null,
  ];
}

void main() {
  group('reading a board', () {
    test('a row, a column and a diagonal all win', () {
      expect(ticWinner(_board('xxx|...|ooo')), TicMark.x);
      expect(ticWinner(_board('x.o|x.o|x..')), TicMark.x);
      expect(ticWinner(_board('o.x|.o.|x.o')), TicMark.o);
    });

    test('the winning line is reported, for the screen to draw through it', () {
      expect(ticWinningLine(_board('ooo|x.x|...')), [0, 1, 2]);
      expect(ticWinningLine(_board('x.o|.x.|o.x')), [0, 4, 8]);
    });

    test('an unfinished board has no winner', () {
      expect(ticWinner(_board('xo.|.x.|..o')), isNull);
      expect(ticIsOver(_board('xo.|.x.|..o')), isFalse);
    });

    test('a full board with no line is a draw, and is over', () {
      final drawn = _board('xox|xoo|oxx');
      expect(ticWinner(drawn), isNull);
      expect(ticIsFull(drawn), isTrue);
      expect(ticIsOver(drawn), isTrue);
    });
  });

  group('the hard opponent', () {
    test('takes a win when it has one', () {
      // o has the top row with 2 free, and playing it ends the game.
      final board = _board('oo.|xx.|x..');
      final move = ticBestMove(board, TicMark.o)!;
      final after = [...board]..[move] = TicMark.o;
      expect(
        ticWinner(after),
        TicMark.o,
        reason: 'it had a win available and played $move instead',
      );
    });

    test('blocks a loss when one can be blocked', () {
      // Asserted as a PROPERTY rather than as a specific square, because the
      // first attempt at this test picked a position that was already a fork —
      // every reply lost, so "the right block" did not exist and the bot was
      // marked wrong for playing one of several equally lost moves.
      final board = _board('xx.|o..|xo.');
      final move = ticBestMove(board, TicMark.o)!;
      final after = [...board]..[move] = TicMark.o;
      // x must not be able to finish on the very next move.
      for (var i = 0; i < 9; i++) {
        if (after[i] != null) continue;
        final reply = [...after]..[i] = TicMark.x;
        expect(
          ticWinner(reply),
          isNot(TicMark.x),
          reason: 'played $move and left x winning at $i',
        );
      }
    });

    test('prefers winning NOW over winning later', () {
      // Both lead to a win, but only one ends it this move. Without depth in
      // the score the search is indifferent and the bot dawdles, which reads
      // as a bug rather than as strategy.
      final move = ticBestMove(_board('oo.|xx.|...'), TicMark.o);
      expect(move, 2);
    });

    test('returns nothing on a finished board', () {
      expect(ticBestMove(_board('xxx|ooo|...'), TicMark.o), isNull);
      expect(ticBestMove(_board('xox|xoo|oxx'), TicMark.o), isNull);
    });

    test('does not always open in the same square', () {
      // A perfect bot that plays the identical game every time is solved by
      // the player in three rounds, which is its own kind of beatable.
      final rng = Random(7);
      final opens = <int>{};
      for (var i = 0; i < 40; i++) {
        opens.add(ticBestMove(ticNewBoard(), TicMark.x, rng: rng)!);
      }
      expect(opens.length, greaterThan(1));
    });
  });

  test('the hard opponent can NEVER be beaten', () {
    // Exhaustive: every reachable line of play, with the human trying every
    // legal move at every turn. This is the claim the app makes on screen.
    var games = 0, botWins = 0, draws = 0;

    void play(TicBoard board, TicMark turn, TicMark bot) {
      if (ticIsOver(board)) {
        games++;
        final w = ticWinner(board);
        expect(w, isNot(ticOther(bot)), reason: 'the human won: $board');
        if (w == bot) {
          botWins++;
        } else {
          draws++;
        }
        return;
      }
      if (turn == bot) {
        // The bot's own choice, deterministically the first best move so the
        // search space stays finite.
        final move = ticBestMove(board, bot, rng: Random(1));
        final next = [...board]..[move!] = bot;
        play(next, ticOther(turn), bot);
        return;
      }
      // The human tries everything.
      for (var i = 0; i < 9; i++) {
        if (board[i] != null) continue;
        final next = [...board]..[i] = turn;
        play(next, ticOther(turn), bot);
      }
    }

    // Both as the opening player and as the responder.
    play(ticNewBoard(), TicMark.x, TicMark.x);
    play(ticNewBoard(), TicMark.x, TicMark.o);

    expect(games, greaterThan(100), reason: 'the search did not explore');
    // ignore: avoid_print
    print('  $games complete games: bot won $botWins, drew $draws, lost 0');
  });

  group('the easy opponent', () {
    test('still takes a free win', () {
      final board = _board('oo.|xx.|x..');
      final move = ticEasyMove(board, TicMark.o)!;
      final after = [...board]..[move] = TicMark.o;
      expect(ticWinner(after), TicMark.o);
    });

    test('still blocks the obvious loss', () {
      // One threat, and taking it is not also a win — so blocking is the only
      // sensible move even for a bot that does not think ahead.
      final board = _board('xx.|o..|xo.');
      final move = ticEasyMove(board, TicMark.o)!;
      expect(move, 2);
    });

    test('is beatable, which is the whole point', () {
      // If "Easy" cannot be beaten it is not easy, it is mislabelled.
      final rng = Random(3);
      var humanWins = 0;
      for (var g = 0; g < 300; g++) {
        var board = ticNewBoard();
        var turn = TicMark.x; // the human opens
        while (!ticIsOver(board)) {
          final move = turn == TicMark.x
              ? ticBestMove(board, TicMark.x, rng: rng)
              : ticEasyMove(board, TicMark.o, rng: rng);
          board = [...board]..[move!] = turn;
          turn = ticOther(turn);
        }
        if (ticWinner(board) == TicMark.x) humanWins++;
      }
      expect(humanWins, greaterThan(0));
    });

    test('plays only into empty squares', () {
      final rng = Random(11);
      for (var i = 0; i < 200; i++) {
        final board = _board('xo.|.x.|o..');
        final move = ticEasyMove(board, TicMark.o, rng: rng)!;
        expect(board[move], isNull);
      }
    });
  });
}
