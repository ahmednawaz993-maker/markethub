// Board geometry, for four seats and six.
//
// The six-player board was added by turning hard-coded geometry into a spec
// that DERIVES it. That is only safe if the four-player values it produces are
// the ones this game has shipped with for months — so the first group below
// asserts them literally, against the numbers as they were written before the
// refactor. If any of these move, every game in progress moves with them.
//
// The second group asserts the invariants on BOTH boards, so the hexagon
// inherits the properties the cross was designed around instead of being
// assumed to have them.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('the four-player board is exactly what it always was', () {
    const f = LudoBoardSpec.four;

    test('ring, spacing, turn-off and home', () {
      expect(f.ringLength, 52);
      expect(f.spacing, 13);
      expect(f.lastRingStep, 50);
      expect(f.home, 56);
      expect(f.seats, 4);
    });

    test('the same start squares', () {
      expect(f.startCellOf(LudoColor.red), 0);
      expect(f.startCellOf(LudoColor.green), 13);
      expect(f.startCellOf(LudoColor.yellow), 26);
      expect(f.startCellOf(LudoColor.blue), 39);
    });

    test('the same safe squares', () {
      expect(f.safeCells, {0, 8, 13, 21, 26, 34, 39, 47});
    });

    test('the same arrow shortcuts', () {
      expect(f.arrows, {2: 9, 15: 22, 28: 35, 41: 48});
    });

    test('the old constants still agree with the spec', () {
      // Most of the game and all of its older tests speak in these names.
      expect(kLudoRingLength, f.ringLength);
      expect(kLudoLastRingStep, f.lastRingStep);
      expect(kLudoHome, f.home);
      expect(kLudoSafeCells, f.safeCells);
      expect(kLudoArrows, f.arrows);
    });

    test('it seats exactly the four classic colours', () {
      expect(f.colours, const [
        LudoColor.red,
        LudoColor.green,
        LudoColor.yellow,
        LudoColor.blue,
      ]);
    });
  });

  group('the six-player board', () {
    const x = LudoBoardSpec.six;

    test('is a longer ring, evenly divided', () {
      expect(x.seats, 6);
      expect(x.ringLength, 72);
      expect(x.spacing, 12);
      expect(x.ringLength % x.seats, 0, reason: 'seats must divide the ring');
    });

    test('turn-off and home follow the same rule as the cross', () {
      // Two short of a full circuit, then five private squares, then home.
      expect(x.lastRingStep, x.ringLength - 2);
      expect(x.home, x.lastRingStep + kLudoHomeColumnLength + 1);
    });

    test('seats six colours, evenly spaced', () {
      expect(x.colours.length, 6);
      expect(
        x.colours.map(x.startCellOf).toList(),
        [0, 12, 24, 36, 48, 60],
      );
    });

    test('purple and orange exist only here', () {
      expect(LudoBoardSpec.four.colours, isNot(contains(LudoColor.purple)));
      expect(x.colours, contains(LudoColor.purple));
      expect(x.colours, contains(LudoColor.orange));
    });
  });

  group('both boards hold the same invariants', () {
    for (final spec in const [LudoBoardSpec.four, LudoBoardSpec.six]) {
      final n = spec.seats;

      test('$n seats: every colour gets a start and a star', () {
        expect(spec.safeCells.length, n * 2);
        for (final c in spec.colours) {
          expect(
            spec.safeCells,
            contains(spec.startCellOf(c)),
            reason: 'a start square must be safe',
          );
        }
      });

      test('$n seats: no arrow starts or ends on a safe square', () {
        // A shortcut must never double as protection, and a capture on a head
        // has to remain possible.
        for (final e in spec.arrows.entries) {
          expect(spec.safeCells, isNot(contains(e.key)), reason: 'tail');
          expect(spec.safeCells, isNot(contains(e.value)), reason: 'head');
        }
      });

      test('$n seats: no arrow chains into another', () {
        for (final head in spec.arrows.values) {
          expect(spec.arrows.containsKey(head), isFalse, reason: '$head');
        }
      });

      test('$n seats: every arrow is a forward jump of seven', () {
        for (final e in spec.arrows.entries) {
          final forward = (e.value - e.key + spec.ringLength) % spec.ringLength;
          expect(forward, 7, reason: '${e.key} -> ${e.value}');
        }
      });

      test('$n seats: one arrow per arm', () {
        expect(spec.arrows.length, n);
      });

      test('$n seats: every ring cell is reachable and none is doubled', () {
        // Each colour walks the same ring from a different entry, so the set of
        // squares one colour visits must be the whole ring minus the last one.
        final visited = <int>{};
        for (var p = 0; p <= spec.lastRingStep; p++) {
          final cell = LudoTokenPos(p).ringCell(LudoColor.red, spec);
          expect(cell, isNotNull);
          expect(visited.add(cell!), isTrue, reason: 'cell $cell twice');
        }
        expect(visited.length, spec.ringLength - 1);
      });

      test('$n seats: a token never lands back on its own start', () {
        // The reason the ring is walked two short of a full circuit.
        for (final c in spec.colours) {
          final start = spec.startCellOf(c);
          for (var p = 1; p <= spec.lastRingStep; p++) {
            expect(
              LudoTokenPos(p).ringCell(c, spec),
              isNot(start),
              reason: '${c.name} returned to its start at progress $p',
            );
          }
        }
      });
    }
  });

  group('forSeats picks the right board', () {
    test('four or fewer players use the cross', () {
      for (final n in [2, 3, 4]) {
        expect(LudoBoardSpec.forSeats(n).seats, 4);
      }
    });

    test('five or six use the hexagon', () {
      for (final n in [5, 6]) {
        expect(LudoBoardSpec.forSeats(n).seats, 6);
      }
    });
  });
}
