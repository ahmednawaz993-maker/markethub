// Six-player games, played out.
//
// The hexagon is a longer ring (72 against 52) with the same five-square run
// home and the same exact-roll finish. That combination could in principle
// stall an endgame, and no unit test of a single move would show it — so these
// play thousands of complete games and check they end, and that no seat is
// favoured by the geometry.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('a six-player game plays to a finish', () {
    test('2000 games all end, and none runs away', () {
      final rng = Random(20260828);
      var unfinished = 0;
      var totalRolls = 0;
      final firstPlace = <LudoColor, int>{};

      for (var g = 0; g < 2000; g++) {
        var game = LudoGame.newGame(LudoBoardSpec.six.colours);
        var rolls = 0;
        while (!game.isOver && rolls < 40000) {
          final r = game.roll(rng.nextInt(6) + 1);
          rolls++;
          game = r.game;
          if (r.moves.isNotEmpty) {
            final pick = chooseLudoMove(
              game.currentPlayer,
              r.moves,
              LudoBoardSpec.six,
            );
            game = game.applyMove(pick!);
          }
        }
        if (!game.isOver) {
          unfinished++;
          continue;
        }
        totalRolls += rolls;
        final w = game.winners.first;
        firstPlace[w] = (firstPlace[w] ?? 0) + 1;
      }

      expect(unfinished, 0, reason: '$unfinished six-player games never ended');
      final avg = totalRolls ~/ 2000;
      // Longer than the four-player game, but not absurdly so.
      expect(avg, greaterThan(200));
      expect(avg, lessThan(3000), reason: 'average $avg rolls is unplayable');

      // Six seats, so a fair board gives each roughly a sixth of first places.
      // Turn order genuinely helps, so the bound is generous — what it catches
      // is a seat the GEOMETRY favours, which would be far outside this.
      for (final c in LudoBoardSpec.six.colours) {
        final share = (firstPlace[c] ?? 0) / 2000;
        expect(
          share,
          inInclusiveRange(0.06, 0.30),
          reason: '${c.name} won ${(share * 100).toStringAsFixed(1)}% '
              'of first places',
        );
      }
    });
  });

  group('the hexagon obeys the same rules as the cross', () {
    test('only a six opens the yard', () {
      final g = LudoGame.newGame(LudoBoardSpec.six.colours);
      for (var d = 1; d <= 5; d++) {
        expect(g.legalMoves(d), isEmpty, reason: 'a $d opened the yard');
      }
      expect(g.legalMoves(6), isNotEmpty);
    });

    test('home must be reached exactly', () {
      const spec = LudoBoardSpec.six;
      final g = LudoGame(
        players: spec.colours,
        positions: {
          for (final c in spec.colours)
            c: [
              if (c == LudoColor.red) spec.home - 3 else kLudoInYard,
              kLudoInYard,
              kLudoInYard,
              kLudoInYard,
            ],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: null,
      );
      // Three lands exactly on home; four would overshoot and is not a move.
      expect(g.legalMoves(3).any((m) => m.to.progress == spec.home), isTrue);
      expect(g.legalMoves(4).any((m) => m.tokenIndex == 0), isFalse);
    });

    test('a capture on the hexagon uses hexagon geometry', () {
      const spec = LudoBoardSpec.six;
      // Red enters at 0, green at 12. Red progress 5 is ring 5; green needs
      // progress 65 to stand on ring (12 + 65) % 72 = 5.
      final g = LudoGame(
        players: spec.colours,
        positions: {
          for (final c in spec.colours)
            c: [
              if (c == LudoColor.red)
                1
              else if (c == LudoColor.green)
                65
              else
                kLudoInYard,
              kLudoInYard,
              kLudoInYard,
              kLudoInYard,
            ],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 4,
      );
      final m = g.legalMoves(4).firstWhere((m) => m.tokenIndex == 0);
      expect(m.to.progress, 5);
      expect(m.captures.single.color, LudoColor.green);
    });

    test('nobody is captured on a safe square', () {
      const spec = LudoBoardSpec.six;
      // Ring 12 is green's start, which is safe. Red reaches it at progress 12.
      final g = LudoGame(
        players: spec.colours,
        positions: {
          for (final c in spec.colours)
            c: [
              if (c == LudoColor.red)
                8
              else if (c == LudoColor.green)
                0
              else
                kLudoInYard,
              kLudoInYard,
              kLudoInYard,
              kLudoInYard,
            ],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 4,
      );
      final m = g.legalMoves(4).firstWhere((m) => m.tokenIndex == 0);
      expect(m.to.progress, 12);
      expect(m.captures, isEmpty, reason: 'a start square must protect');
    });
  });
}
