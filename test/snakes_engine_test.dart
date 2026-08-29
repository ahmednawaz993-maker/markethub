// Saanp Seerhi rules.
//
// The board is the interesting part to test, not the dice: a snake or a ladder
// that is placed wrongly turns the game into something that cannot be finished
// or cannot be lost, and neither shows up as a crash.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('the board itself', () {
    test('every snake goes down and every ladder goes up', () {
      for (final s in kSnakesAndLadders) {
        expect(s.from, isNot(s.to), reason: 'a square cannot lead to itself');
        expect(s.isSnake ^ s.isLadder, isTrue);
      }
    });

    test('nothing starts or ends off the board', () {
      for (final s in kSnakesAndLadders) {
        expect(s.from, inInclusiveRange(2, 99));
        expect(s.to, inInclusiveRange(1, kSnakesHome));
      }
    });

    test('no square is the mouth of two different things', () {
      // Two entries for one square means whichever comes first in the list
      // wins, silently, and the board no longer matches what is drawn on it.
      final froms = kSnakesAndLadders.map((s) => s.from).toList();
      expect(froms.toSet(), hasLength(froms.length));
    });

    test('a snake never lands you on another snake head', () {
      // Legal in principle, but a chain reaction reads as the game cheating,
      // and on a printed board it looks like a mistake.
      for (final s in kSnakesAndLadders) {
        expect(
          snakeOrLadderAt(s.to),
          isNull,
          reason: 'landing at ${s.to} immediately moves you again',
        );
      }
    });

    test('a ladder to 100 exists, and no snake sits on 100', () {
      // Reaching the last square by ladder is the moment everybody remembers.
      expect(kSnakesAndLadders.any((s) => s.to == kSnakesHome), isTrue);
      expect(snakeOrLadderAt(kSnakesHome), isNull);
    });

    test('the last quarter is more dangerous than the first', () {
      // A lead near the end should be worth something and never be safe.
      int snakesIn(int lo, int hi) => kSnakesAndLadders
          .where((s) => s.isSnake && s.from >= lo && s.from <= hi)
          .length;
      expect(snakesIn(76, 100), greaterThan(snakesIn(1, 25)));
    });
  });

  group('the grid', () {
    test('square 1 is bottom-left and 100 is top-left', () {
      expect(snakesCellOf(1), (row: 9, col: 0));
      expect(snakesCellOf(100), (row: 0, col: 0));
    });

    test('the first row runs left to right, the second right to left', () {
      expect(snakesCellOf(10), (row: 9, col: 9));
      // 11 sits directly above 10, which is what makes the path continuous.
      expect(snakesCellOf(11), (row: 8, col: 9));
      expect(snakesCellOf(20), (row: 8, col: 0));
      expect(snakesCellOf(21), (row: 7, col: 0));
    });

    test('every square has its own cell', () {
      final seen = <String>{};
      for (var i = 1; i <= kSnakesHome; i++) {
        final c = snakesCellOf(i);
        expect(seen.add('${c.row}:${c.col}'), isTrue, reason: 'square $i');
      }
      expect(seen, hasLength(kSnakesHome));
    });

    test('consecutive squares are always adjacent on the board', () {
      // If they are not, the piece teleports across the board on a plain move.
      for (var i = 1; i < kSnakesHome; i++) {
        final a = snakesCellOf(i), b = snakesCellOf(i + 1);
        final step = (a.row - b.row).abs() + (a.col - b.col).abs();
        expect(step, 1, reason: '$i to ${i + 1}');
      }
    });
  });

  group('playing', () {
    test('a player starts off the board and is on it after one roll', () {
      final g = SnakesGame.newGame(2).roll(3);
      expect(g.positions[0], 3);
    });

    test('landing on a ladder climbs it', () {
      final g = SnakesGame.newGame(2).roll(2); // 2 -> 23
      expect(g.positions[0], 23);
      expect(g.lastMove!.jump!.isLadder, isTrue);
      expect(g.lastMove!.landed, 2, reason: 'the board must know where it hit');
    });

    test('landing on a snake slides down it', () {
      var g = SnakesGame.newGame(2);
      g = SnakesGame(
        positions: const [26, 0],
        turn: 0,
        consecutiveSixes: 0,
        winner: null,
        lastMove: null,
      ).roll(3); // 29 -> 9
      expect(g.positions[0], 9);
      expect(g.lastMove!.jump!.isSnake, isTrue);
    });

    test('passing over a snake does nothing', () {
      final g = SnakesGame(
        positions: const [28, 0],
        turn: 0,
        consecutiveSixes: 0,
        winner: null,
        lastMove: null,
      ).roll(3); // over 29, lands on 31
      expect(g.positions[0], 31);
      expect(g.lastMove!.jump, isNull);
    });

    test('a six earns another turn', () {
      final g = SnakesGame.newGame(2).roll(6);
      expect(g.turn, 0);
      expect(g.consecutiveSixes, 1);
    });

    test('three sixes running forfeits the turn and moves nothing', () {
      var g = SnakesGame.newGame(2).roll(6).roll(6);
      final before = g.positions[0];
      g = g.roll(6);
      expect(g.positions[0], before);
      expect(g.turn, 1);
      expect(g.lastMove!.blocked, isTrue);
    });

    test('100 must be reached exactly', () {
      final g = SnakesGame(
        positions: const [98, 0],
        turn: 0,
        consecutiveSixes: 0,
        winner: null,
        lastMove: null,
      ).roll(4);
      expect(g.positions[0], 98, reason: 'an overshoot does not move');
      expect(g.lastMove!.blocked, isTrue);
      expect(g.turn, 1);
    });

    test('reaching exactly 100 wins', () {
      final g = SnakesGame(
        positions: const [98, 0],
        turn: 0,
        consecutiveSixes: 0,
        winner: null,
        lastMove: null,
      ).roll(2);
      expect(g.winner, 0);
      expect(g.isOver, isTrue);
      expect(g.lastMove!.won, isTrue);
    });

    test('winning on a six does not earn another turn', () {
      final g = SnakesGame(
        positions: const [94, 0],
        turn: 0,
        consecutiveSixes: 0,
        winner: null,
        lastMove: null,
      ).roll(6);
      expect(g.winner, 0);
    });

    test('a finished game ignores further rolls', () {
      final won = SnakesGame(
        positions: const [98, 0],
        turn: 0,
        consecutiveSixes: 0,
        winner: null,
        lastMove: null,
      ).roll(2);
      expect(won.roll(3), same(won));
    });

    test('the turn goes round the table', () {
      var g = SnakesGame.newGame(4);
      for (final expected in [1, 2, 3, 0]) {
        g = g.roll(3);
        expect(g.turn, expected);
      }
    });
  });

  test('games finish, and are not decided in a handful of turns', () {
    // The failure a rules bug produces here is not a crash: it is a game that
    // cannot end, or one that ends so fast nobody enjoys it.
    final rng = Random(20260830);
    var total = 0, shortest = 99999, longest = 0;
    for (var n = 0; n < 2000; n++) {
      var g = SnakesGame.newGame(2);
      var rolls = 0;
      while (!g.isOver && rolls < 5000) {
        g = g.roll(rng.nextInt(6) + 1);
        rolls++;
      }
      expect(g.isOver, isTrue, reason: 'a game ran away');
      total += rolls;
      shortest = rolls < shortest ? rolls : shortest;
      longest = rolls > longest ? rolls : longest;
    }
    final average = total / 2000;
    expect(average, greaterThan(15), reason: 'over before it started');
    expect(average, lessThan(150), reason: 'nobody will sit through this');
    // ignore: avoid_print
    print('  2000 games: average $average rolls, range $shortest..$longest');
  });
}
