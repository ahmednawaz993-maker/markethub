import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// The engine is proven in ludo_engine_test. What this file proves is the
// translation from "progress 37 for blue" to "row 11, column 6" — the part
// that, if wrong, puts a token on the wrong square while every rule still
// passes. Geometry errors are invisible to logic tests, so they are checked
// here as coordinates and then LOOKED at as a golden.

void main() {
  group('the ring', () {
    test('is 52 distinct cells, all on the board', () {
      expect(kLudoRing.length, kLudoRingLength);
      final seen = <String>{};
      for (final c in kLudoRing) {
        expect(c.row, inInclusiveRange(0, 14));
        expect(c.col, inInclusiveRange(0, 14));
        expect(seen.add('${c.row},${c.col}'), isTrue, reason: 'duplicate $c');
      }
    });

    // Consecutive cells must touch, or a token appears to teleport. A Ludo
    // track does turn DIAGONALLY at the four inner corners of the cross — the
    // last square of an arm meets the first square of the next arm only at a
    // corner — so exactly four such turns are expected and no more.
    test('every step touches the next, with exactly four corner turns', () {
      var diagonals = 0;
      for (var i = 0; i < kLudoRing.length; i++) {
        final a = kLudoRing[i];
        final b = kLudoRing[(i + 1) % kLudoRing.length];
        final dr = (a.row - b.row).abs();
        final dc = (a.col - b.col).abs();
        if (dr + dc == 1) continue; // straight
        if (dr == 1 && dc == 1) {
          diagonals++;
          continue; // corner turn
        }
        fail('cell $i $a -> $b does not touch');
      }
      expect(diagonals, 4, reason: 'the cross has four inner corners');
    });

    test('each colour joins at its own coloured square', () {
      expect(kLudoRing[LudoColor.red.startCell], (row: 6, col: 1));
      expect(kLudoRing[LudoColor.green.startCell], (row: 1, col: 8));
      expect(kLudoRing[LudoColor.yellow.startCell], (row: 8, col: 13));
      expect(kLudoRing[LudoColor.blue.startCell], (row: 13, col: 6));
    });

    // The four stars should sit symmetrically, one per arm.
    test('the safe squares are the four starts plus four stars', () {
      final starts = {for (final c in LudoBoardSpec.four.colours) c.startCell};
      final stars = kLudoSafeCells.difference(starts);
      expect(stars, {8, 21, 34, 47});
      for (final s in stars) {
        expect(kLudoRing[s].row, inInclusiveRange(0, 14));
      }
    });
  });

  group('home columns and yards', () {
    test('each colour has five private cells, none of them on the ring', () {
      final ring = {for (final c in kLudoRing) '${c.row},${c.col}'};
      for (final colour in LudoBoardSpec.four.colours) {
        final col = ludoHomeColumn(colour);
        expect(col.length, kLudoHomeColumnLength, reason: colour.name);
        for (final cell in col) {
          expect(
            ring.contains('${cell.row},${cell.col}'),
            isFalse,
            reason: '${colour.name} home cell $cell is on the ring',
          );
        }
      }
    });

    test('home columns run inward toward the centre', () {
      // Each colour's column ends adjacent to the centre block.
      expect(ludoHomeColumn(LudoColor.red).last, (row: 7, col: 5));
      expect(ludoHomeColumn(LudoColor.green).last, (row: 5, col: 7));
      expect(ludoHomeColumn(LudoColor.yellow).last, (row: 7, col: 9));
      expect(ludoHomeColumn(LudoColor.blue).last, (row: 9, col: 7));
    });

    // The invariant that was wrong first time round and that no rules test can
    // see: a token leaving the yard must appear NEXT to it, not across the
    // board. Each colour's start square has to touch its own corner.
    test('each colour starts beside its own yard', () {
      for (final c in LudoBoardSpec.four.colours) {
        final start = kLudoRing[c.startCell];
        final o = ludoYardOrigin(c);
        final touchesRows =
            start.row >= o.row - 1 && start.row <= o.row + 6;
        final touchesCols =
            start.col >= o.col - 1 && start.col <= o.col + 6;
        expect(
          touchesRows && touchesCols,
          isTrue,
          reason: '${c.name} starts at $start but its yard is at $o',
        );
      }
    });

    test('the four yards are distinct 6x6 corners', () {
      final origins = {
        for (final c in LudoBoardSpec.four.colours)
          '${ludoYardOrigin(c).row},${ludoYardOrigin(c).col}',
      };
      expect(origins.length, 4);
      for (final c in LudoBoardSpec.four.colours) {
        final o = ludoYardOrigin(c);
        expect(o.row, anyOf(0, 9));
        expect(o.col, anyOf(0, 9));
      }
    });
  });

  group('ludoCellFor', () {
    test('yard tokens sit in their own corner, four to a yard', () {
      for (final c in LudoBoardSpec.four.colours) {
        final seen = <String>{};
        for (var i = 0; i < 4; i++) {
          final cell = ludoCellFor(c, kLudoInYard, i)!;
          final o = ludoYardOrigin(c);
          expect(cell.row, inInclusiveRange(o.row, o.row + 5));
          expect(cell.col, inInclusiveRange(o.col, o.col + 5));
          expect(seen.add('${cell.row},${cell.col}'), isTrue);
        }
      }
    });

    test('progress 0 is the colour\'s start square', () {
      for (final c in LudoBoardSpec.four.colours) {
        expect(ludoCellFor(c, 0, 0), kLudoRing[c.startCell]);
      }
    });

    test('the last ring step is one short of a full loop', () {
      // Progress 50 must NOT be back on the start square — a token turns into
      // its home column before completing the circuit.
      for (final c in LudoBoardSpec.four.colours) {
        final cell = ludoCellFor(c, kLudoLastRingStep, 0);
        expect(cell, isNot(kLudoRing[c.startCell]));
      }
    });

    test('home-column progress walks the private column in order', () {
      for (final c in LudoBoardSpec.four.colours) {
        final col = ludoHomeColumn(c);
        for (var i = 0; i < kLudoHomeColumnLength; i++) {
          expect(ludoCellFor(c, kLudoLastRingStep + 1 + i, 0), col[i]);
        }
      }
    });

    test('a finished token has no board cell', () {
      expect(ludoCellFor(LudoColor.red, kLudoHome, 0), isNull);
    });
  });

  group('board renders', () {
    testWidgets('a mid-game board paints without error', (tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final game = LudoGame(
        players: LudoBoardSpec.four.colours,
        positions: {
          LudoColor.red: [0, 12, 52, kLudoHome],
          LudoColor.green: [kLudoInYard, 7, 30, 45],
          LudoColor.yellow: [3, kLudoInYard, kLudoInYard, 55],
          LudoColor.blue: [20, 41, kLudoInYard, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 6,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: LudoBoard(game: game, moves: game.legalMoves(6)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await expectLater(
        find.byType(LudoBoard),
        matchesGoldenFile('goldens/ludo_board.png'),
      );
    });
  });
}
