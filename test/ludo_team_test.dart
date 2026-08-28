// Team 2v2.
//
// Modelled as a FLAG rather than another LudoMode, because it is a different
// axis: a team game is still Classic, Master, Quick or Arrow. Two rules
// actually change — no friendly fire, and a win that belongs to the side — and
// one thing has to survive that has bitten this file twice already: the flag
// must be carried through every state transition and every rebuild, or a team
// game quietly turns back into a free-for-all on the first move.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

LudoGame teamGame({
  Map<LudoColor, List<int>>? positions,
  int turn = 0,
  int? dice,
  List<LudoColor> winners = const [],
}) => LudoGame(
  players: const [
    LudoColor.red,
    LudoColor.green,
    LudoColor.yellow,
    LudoColor.blue,
  ],
  positions:
      positions ??
      {
        for (final c in LudoBoardSpec.four.colours)
          c: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      },
  turn: turn,
  consecutiveSixes: 0,
  winners: winners,
  lastDice: dice,
  teams: true,
);

Map<LudoColor, List<int>> yard() => {
  for (final c in LudoBoardSpec.four.colours)
    c: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
};

void main() {
  group('the pairing', () {
    test('partners sit opposite, never adjacent', () {
      // Turn order runs red, green, yellow, blue. Opposite partners alternate
      // with their opponents; adjacent ones would hand one team two turns in a
      // row, which is a different (and worse) game.
      expect(kLudoPartners[LudoColor.red], LudoColor.yellow);
      expect(kLudoPartners[LudoColor.green], LudoColor.blue);
    });

    test('is symmetric and total', () {
      for (final c in LudoBoardSpec.four.colours) {
        final p = kLudoPartners[c]!;
        expect(p, isNot(c), reason: '${c.name} partners itself');
        expect(kLudoPartners[p], c, reason: '${c.name} pairing is one-way');
      }
    });
  });

  group('allies', () {
    test('a colour is its own ally, so self-collision checks still work', () {
      expect(teamGame().areAllies(LudoColor.red, LudoColor.red), isTrue);
    });

    test('partners are allies, opponents are not', () {
      final g = teamGame();
      expect(g.areAllies(LudoColor.red, LudoColor.yellow), isTrue);
      expect(g.areAllies(LudoColor.red, LudoColor.green), isFalse);
      expect(g.areAllies(LudoColor.red, LudoColor.blue), isFalse);
    });

    test('in a solo game nobody is an ally but yourself', () {
      final solo = LudoGame.newGame(LudoBoardSpec.four.colours);
      expect(solo.areAllies(LudoColor.red, LudoColor.yellow), isFalse);
      expect(solo.partnerOf(LudoColor.red), isNull);
    });
  });

  group('no friendly fire', () {
    test('a partner standing on the destination is not captured', () {
      // Red token 0 at progress 1; a 3 takes it to 4, which is ring cell 4.
      // Yellow enters at 26, so yellow progress 30 is ring (26+30)%52 = 4.
      final g = teamGame(
        positions: {
          ...yard(),
          LudoColor.red: [1, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.yellow: [30, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        dice: 3,
      );
      final m = g.legalMoves(3).firstWhere((m) => m.tokenIndex == 0);
      expect(
        m.captures,
        isEmpty,
        reason: 'a player must never send their own side home',
      );
    });

    test('an opponent on the same square IS captured', () {
      // Green enters at 13, so green progress 43 is ring (13+43)%52 = 4.
      final g = teamGame(
        positions: {
          ...yard(),
          LudoColor.red: [1, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.green: [43, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        dice: 3,
      );
      final m = g.legalMoves(3).firstWhere((m) => m.tokenIndex == 0);
      expect(m.captures.length, 1);
      expect(m.captures.single.color, LudoColor.green);
    });

    test('that same partner IS captured in a solo game', () {
      // Proves the exemption comes from the team flag and not from the board
      // geometry — the positions here are identical to the first test.
      final solo = LudoGame(
        players: LudoBoardSpec.four.colours,
        positions: {
          ...yard(),
          LudoColor.red: [1, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.yellow: [30, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 3,
      );
      final m = solo.legalMoves(3).firstWhere((m) => m.tokenIndex == 0);
      expect(m.captures.single.color, LudoColor.yellow);
    });
  });

  group('winning as a side', () {
    test('one partner home is not a win', () {
      final g = teamGame(winners: const [LudoColor.red]);
      expect(g.isOver, isFalse);
      expect(g.winningSide, {LudoColor.red, LudoColor.yellow});
    });

    test('both partners home ends the game', () {
      expect(
        teamGame(winners: const [LudoColor.red, LudoColor.yellow]).isOver,
        isTrue,
      );
    });

    test('two OPPONENTS finishing does not end it', () {
      // Red and green are on opposite sides, so neither team is complete. A
      // solo game would already be over here, which is the point.
      expect(
        teamGame(winners: const [LudoColor.red, LudoColor.green]).isOver,
        isFalse,
      );
    });

    test('a solo game is unaffected', () {
      final solo = LudoGame.newGame(const [LudoColor.red, LudoColor.green]);
      expect(solo.isOver, isFalse);
      expect(solo.winningSide, isEmpty);
    });
  });

  group('a team game needs four seats', () {
    test('the flag is ignored until the table is full', () {
      final two = LudoGame.newGame(
        const [LudoColor.red, LudoColor.green],
        teams: true,
      );
      expect(two.teams, isFalse, reason: '2v2 with two players is not 2v2');
      expect(LudoGame.newGame(LudoBoardSpec.four.colours, teams: true).teams, isTrue);
    });
  });

  group('the flag survives every transition', () {
    test('it round-trips through JSON', () {
      final g = LudoGame.newGame(LudoBoardSpec.four.colours, teams: true);
      expect(LudoGame.fromJson(g.toJson()).teams, isTrue);
      expect(
        LudoGame.fromJson(LudoGame.newGame(LudoBoardSpec.four.colours).toJson()).teams,
        isFalse,
      );
    });

    test('an old document with no teams key reads as a solo game', () {
      final json = LudoGame.newGame(LudoBoardSpec.four.colours).toJson()..remove('teams');
      expect(LudoGame.fromJson(json).teams, isFalse);
    });

    test('applying a move and rolling both keep it', () {
      // The failure this guards against is silent: drop the flag on applyMove
      // and the first capture of the game sends a partner home.
      var g = teamGame(
        positions: {
          ...yard(),
          LudoColor.red: [1, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        dice: 3,
      );
      g = g.applyMove(g.legalMoves(3).first);
      expect(g.teams, isTrue, reason: 'dropped on applyMove');
      expect(g.roll(4).game.teams, isTrue, reason: 'dropped on roll');
      // Three sixes takes a different branch out of roll().
      var six = teamGame(dice: 6);
      six = LudoGame(
        players: six.players,
        positions: six.positions,
        turn: 0,
        consecutiveSixes: 2,
        winners: const [],
        lastDice: null,
        teams: true,
      );
      expect(six.roll(6).game.teams, isTrue, reason: 'dropped on three sixes');
    });
  });
}
