import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Three modes, one board. What differs is how long a game lasts and what it
// takes to finish — so these tests are about token counts and the Master home
// lock, not about movement, which is identical everywhere.
//
// The Master rule is mirrored in functions/ludo_logic.js because the server
// rolls and plays bots. If the two disagree, a player is offered a move the
// server will not accept, so ludo_logic.test.js asserts the same cases.

void main() {
  _arrowTests();
  const two = [LudoColor.red, LudoColor.green];

  group('token counts', () {
    test('Classic and Master use four, Quick uses two', () {
      expect(LudoMode.classic.tokens, 4);
      expect(LudoMode.master.tokens, 4);
      expect(LudoMode.quick.tokens, 2);
    });

    test('a new game deals the right number of tokens', () {
      for (final m in LudoMode.values) {
        final g = LudoGame.newGame(two, mode: m);
        for (final c in two) {
          expect(g.positions[c], hasLength(m.tokens), reason: m.label);
          expect(g.positions[c]!.every((p) => p == kLudoInYard), isTrue);
        }
      }
    });

    // The shorter game must genuinely end sooner, not just look different.
    test('Quick needs two tokens home to win, not four', () {
      final g = LudoGame(
        players: two,
        positions: {
          LudoColor.red: [kLudoHome, 53],
          LudoColor.green: [0, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 3,
        mode: LudoMode.quick,
      );
      final move = g.legalMoves(3).firstWhere((m) => m.to.isHome);
      expect(g.applyMove(move).winners, [LudoColor.red]);
    });
  });

  group('Master: the home column is locked until you capture', () {
    LudoGame master({required bool captured}) => LudoGame(
      players: two,
      // Red on 48: a roll of 5 would reach 53, inside the home column.
      positions: {
        LudoColor.red: [48, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [10, kLudoInYard, kLudoInYard, kLudoInYard],
      },
      turn: 0,
      consecutiveSixes: 0,
      winners: const [],
      lastDice: 5,
      mode: LudoMode.master,
      hasCaptured: captured ? {LudoColor.red} : const {},
    );

    test('without a capture the token cannot turn in', () {
      final moves = master(captured: false).legalMoves(5);
      expect(
        moves.where((m) => m.to.progress > kLudoLastRingStep),
        isEmpty,
        reason: 'the home column must stay shut',
      );
    });

    test('after a capture it opens', () {
      final moves = master(captured: true).legalMoves(5);
      expect(moves.where((m) => m.to.progress > kLudoLastRingStep), hasLength(1));
    });

    // The point of the variant: the token is not frozen, it just cannot finish.
    test('a locked token can still move around the ring', () {
      final g = LudoGame(
        players: two,
        positions: {
          LudoColor.red: [30, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.green: [10, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 4,
        mode: LudoMode.master,
      );
      expect(g.legalMoves(4), isNotEmpty);
    });

    test('capturing records the unlock on the state', () {
      final g = LudoGame(
        players: two,
        positions: {
          LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.green: [46, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 3,
        mode: LudoMode.master,
      );
      final cap = g.legalMoves(3).firstWhere((m) => m.captures.isNotEmpty);
      expect(g.applyMove(cap).hasCaptured, contains(LudoColor.red));
    });

    test('Classic and Quick never lock the home column', () {
      for (final m in [LudoMode.classic, LudoMode.quick]) {
        final g = LudoGame(
          players: two,
          positions: {
            LudoColor.red: List.filled(m.tokens, kLudoInYard)..[0] = 48,
            LudoColor.green: List.filled(m.tokens, kLudoInYard)..[0] = 10,
          },
          turn: 0,
          consecutiveSixes: 0,
          winners: const [],
          lastDice: 5,
          mode: m,
        );
        expect(
          g.legalMoves(5).where((x) => x.to.progress > kLudoLastRingStep),
          isNotEmpty,
          reason: m.label,
        );
      }
    });
  });

  group('the mode survives the network', () {
    test('mode and capture flags round-trip through JSON', () {
      for (final m in LudoMode.values) {
        var g = LudoGame.newGame(two, mode: m);
        g = LudoGame(
          players: g.players,
          positions: g.positions,
          turn: g.turn,
          consecutiveSixes: g.consecutiveSixes,
          winners: g.winners,
          lastDice: g.lastDice,
          mode: m,
          hasCaptured: {LudoColor.green},
        );
        final back = LudoGame.fromJson(g.toJson());
        expect(back.mode, m);
        expect(back.hasCaptured, {LudoColor.green});
        expect(back.positions[LudoColor.red], hasLength(m.tokens));
      }
    });

    // Rooms created before modes existed have no `mode` field; they are the
    // classic game and must not become something else on read.
    test('a document with no mode reads as Classic', () {
      final legacy = LudoGame.newGame(two).toJson()..remove('mode');
      expect(LudoGame.fromJson(legacy).mode, LudoMode.classic);
    });
  });
}

// ---------------------------------------------------------------------------
// Arrow: four one-way shortcuts round the ring. Landing on a tail carries the
// token to the head and earns another roll.
//
// The arrow TABLE is tested as hard as the behaviour, because bad numbers here
// would not crash anything — they would just make the game subtly wrong. An
// arrow onto a safe square would create protection that should not exist; a
// head that is also a tail would chain into a ride nobody designed; a backwards
// jump would look like a bug to every player who saw it.
// ---------------------------------------------------------------------------

void _arrowTests() {
  group('the arrow table', () {
    test('is four evenly spaced, forward-only jumps', () {
      expect(kLudoArrows.length, 4);
      for (final e in kLudoArrows.entries) {
        final forward = (e.value - e.key + kLudoRingLength) % kLudoRingLength;
        expect(forward, 7, reason: 'arrow ${e.key}->${e.value} is not +7');
      }
    });

    test('never starts or ends on a safe square', () {
      for (final e in kLudoArrows.entries) {
        expect(kLudoSafeCells.contains(e.key), isFalse, reason: 'tail ${e.key}');
        expect(
          kLudoSafeCells.contains(e.value),
          isFalse,
          reason: 'head ${e.value}',
        );
      }
    });

    test('no head is another tail, so arrows cannot chain', () {
      for (final head in kLudoArrows.values) {
        expect(kLudoArrows.containsKey(head), isFalse, reason: 'chain at $head');
      }
    });

    test('every cell is within the ring', () {
      for (final e in kLudoArrows.entries) {
        expect(e.key, inInclusiveRange(0, kLudoRingLength - 1));
        expect(e.value, inInclusiveRange(0, kLudoRingLength - 1));
      }
    });
  });

  group('riding an arrow', () {
    LudoGame arrowGame() =>
        LudoGame.newGame(const [LudoColor.red, LudoColor.green],
            mode: LudoMode.arrow);

    test('only applies in Arrow mode', () {
      // Red's start cell is 0, so progress 2 sits on ring cell 2 — a tail.
      final classic = LudoGame.newGame(const [
        LudoColor.red,
        LudoColor.green,
      ]);
      expect(classic.arrowJump(LudoColor.red, 2), isNull);
      expect(arrowGame().arrowJump(LudoColor.red, 2), 9);
    });

    test('carries the token to the head', () {
      final g = arrowGame();
      expect(g.arrowJump(LudoColor.red, 2), 9);
      expect(g.arrowJump(LudoColor.red, 15), 22);
      expect(g.arrowJump(LudoColor.red, 28), 35);
    });

    test('does nothing on a cell that is not a tail', () {
      final g = arrowGame();
      expect(g.arrowJump(LudoColor.red, 3), isNull);
      expect(g.arrowJump(LudoColor.red, 0), isNull);
    });

    test('never carries a token into the home column', () {
      // Red at 41 is a tail whose head is 48 — allowed, it stays on the ring.
      expect(arrowGame().arrowJump(LudoColor.red, 41), 48);
      // Anything the jump would push past the turn-off is refused outright,
      // because home has to be reached by an exact roll.
      for (var p = 0; p <= kLudoLastRingStep; p++) {
        final j = arrowGame().arrowJump(LudoColor.red, p);
        if (j != null) {
          expect(j, lessThanOrEqualTo(kLudoLastRingStep));
          expect(j, greaterThan(p), reason: 'arrow went backwards from $p');
        }
      }
    });

    test('works for every colour, not just red', () {
      // Each colour enters the ring at a different cell, so the progress that
      // lands on a tail differs — the jump must still be +7 for all of them.
      for (final c in LudoColor.values) {
        var found = 0;
        for (var p = 0; p <= kLudoLastRingStep; p++) {
          final j = arrowGame().arrowJump(c, p);
          if (j != null) {
            expect(j - p, 7, reason: '${c.name} from $p');
            found++;
          }
        }
        expect(found, greaterThan(0), reason: '${c.name} has no arrows at all');
      }
    });

    test('a move that rides an arrow reports it, and earns another roll', () {
      // Red token 0 at progress 1; a 1 lands it on 2, which is a tail.
      var g = arrowGame();
      g = LudoGame(
        players: g.players,
        positions: {
          LudoColor.red: [1, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 1,
        mode: LudoMode.arrow,
      );
      final move = g.legalMoves(1).firstWhere((m) => m.tokenIndex == 0);
      expect(move.viaArrow, isTrue);
      expect(move.to.progress, 9, reason: 'should end on the arrow head');

      final after = g.applyMove(move);
      expect(after.positions[LudoColor.red]![0], 9);
      // A 3 is not a six and captured nothing, so only the arrow can be
      // granting the extra roll.
      expect(after.currentPlayer, LudoColor.red);
    });

    test('the same move in Classic stops on the tail and passes the turn', () {
      var g = LudoGame(
        players: const [LudoColor.red, LudoColor.green],
        positions: {
          LudoColor.red: [1, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 1,
      );
      final move = g.legalMoves(1).firstWhere((m) => m.tokenIndex == 0);
      expect(move.viaArrow, isFalse);
      expect(move.to.progress, 2);
      expect(g.applyMove(move).currentPlayer, LudoColor.green);
    });
  });
}
