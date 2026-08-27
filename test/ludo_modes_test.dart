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
