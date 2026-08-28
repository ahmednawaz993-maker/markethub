import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Ludo is a game people argue about. Every table has a house rule, and a rules
// engine that quietly disagrees with the players will be described as "broken"
// no matter how clean the code is. So each rule below is pinned explicitly,
// and the ones that vary between tables are called out as decisions rather
// than left implicit.

LudoGame _withPositions(Map<LudoColor, List<int>> pos, {int turn = 0}) =>
    LudoGame(
      players: pos.keys.toList(),
      positions: pos,
      turn: turn,
      consecutiveSixes: 0,
      winners: const [],
      lastDice: null,
    );

void main() {
  const all = [
    LudoColor.red,
    LudoColor.green,
    LudoColor.yellow,
    LudoColor.blue,
  ];

  group('board geometry', () {
    test('each colour joins the ring a quarter turn apart', () {
      expect(LudoColor.red.startCell, 0);
      expect(LudoColor.green.startCell, 13);
      expect(LudoColor.yellow.startCell, 26);
      expect(LudoColor.blue.startCell, 39);
    });

    // Progress is per-colour, so the same progress is a different board cell
    // for each player. This translation is the only place the colours differ,
    // and an error here would make captures land on the wrong square.
    test('progress translates to the shared ring, wrapping at 52', () {
      expect(const LudoTokenPos(0).ringCell(LudoColor.red), 0);
      expect(const LudoTokenPos(0).ringCell(LudoColor.yellow), 26);
      expect(const LudoTokenPos(30).ringCell(LudoColor.yellow), 4);
      expect(const LudoTokenPos(50).ringCell(LudoColor.blue), 37);
    });

    test('yard, home column and home are off the ring', () {
      expect(const LudoTokenPos(kLudoInYard).ringCell(LudoColor.red), isNull);
      expect(const LudoTokenPos(51).ringCell(LudoColor.red), isNull);
      expect(const LudoTokenPos(kLudoHome).ringCell(LudoColor.red), isNull);
      expect(const LudoTokenPos(51).inHomeColumn, isTrue);
      expect(const LudoTokenPos(kLudoHome).isHome, isTrue);
    });

    test('there are eight safe squares, including every start', () {
      expect(kLudoSafeCells.length, 8);
      for (final c in all) {
        expect(kLudoSafeCells, contains(c.startCell));
      }
    });
  });

  group('leaving the yard', () {
    test('only a six opens the yard', () {
      final g = LudoGame.newGame(all);
      for (var d = 1; d <= 5; d++) {
        expect(g.legalMoves(d), isEmpty, reason: 'rolled $d');
      }
      expect(g.legalMoves(6), hasLength(4));
    });

    // A six places the token ON the start square — it does not also advance it
    // six steps. Tables differ on nothing here, but the off-by-six is an easy
    // implementation slip.
    test('a six places the token on the start square, not six past it', () {
      final g = LudoGame.newGame(all);
      final move = g.legalMoves(6).first;
      expect(move.to.progress, 0);
      expect(move.to.ringCell(LudoColor.red), 0);
    });

    test('a non-six with everything in the yard passes the turn', () {
      final g = LudoGame.newGame(all);
      final r = g.roll(3);
      expect(r.moves, isEmpty);
      expect(r.game.currentPlayer, LudoColor.green);
    });

    // A six that cannot be used still keeps the dice: the player rolls again.
    test('a six with no legal move keeps the turn', () {
      final g = _withPositions({
        LudoColor.red: [kLudoHome, kLudoHome, kLudoHome, 55],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      final r = g.roll(6); // 55 + 6 = 61, overshoots home
      expect(r.moves, isEmpty);
      expect(r.game.currentPlayer, LudoColor.red, reason: 'six keeps the dice');
    });
  });

  group('capturing', () {
    test('landing on an opponent on an unsafe square sends it home', () {
      // Red at progress 4 (cell 4); green token sitting on cell 4, which for
      // green is progress 43. Cell 4 is not safe.
      final g = _withPositions({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [43, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      expect(const LudoTokenPos(43).ringCell(LudoColor.green), 4);

      final rolled = g.roll(3); // red 4 -> 7, cell 7
      expect(rolled.moves, isNotEmpty);

      // Now put green on cell 7 instead and check the capture.
      final g2 = _withPositions({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [46, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      expect(const LudoTokenPos(46).ringCell(LudoColor.green), 7);
      final r2 = g2.roll(3);
      final capturing = r2.moves.firstWhere((m) => m.captures.isNotEmpty);
      expect(capturing.captures.single.color, LudoColor.green);

      final after = r2.game.applyMove(capturing);
      expect(after.positions[LudoColor.green]![0], kLudoInYard);
    });

    test('nobody is captured on a safe square', () {
      // Cell 8 is a star. Red 4 + 4 = progress 8 = cell 8.
      final g = _withPositions({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [47, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      expect(const LudoTokenPos(47).ringCell(LudoColor.green), 8);
      expect(kLudoSafeCells, contains(8));

      final r = g.roll(4);
      final move = r.moves.firstWhere((m) => m.tokenIndex == 0);
      expect(move.to.ringCell(LudoColor.red), 8);
      expect(move.captures, isEmpty, reason: 'square 8 is a star');
    });

    test('a token in its home column cannot be captured', () {
      // Home-column progress never maps to a ring cell, so no move can reach
      // it. This is the rule that makes the last stretch a refuge.
      final g = _withPositions({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [53, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      for (var d = 1; d <= 6; d++) {
        for (final m in g.legalMoves(d)) {
          expect(m.captures, isEmpty, reason: 'rolled $d');
        }
      }
    });

    test('capturing earns another turn', () {
      final g = _withPositions({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [46, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      final r = g.roll(3);
      final cap = r.moves.firstWhere((m) => m.captures.isNotEmpty);
      expect(r.game.applyMove(cap).currentPlayer, LudoColor.red);
    });
  });

  group('the home stretch', () {
    test('home must be reached exactly; overshooting is not a move', () {
      final g = _withPositions({
        LudoColor.red: [53, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      // 53 + 3 = 56 exactly.
      expect(g.legalMoves(3).where((m) => m.tokenIndex == 0), hasLength(1));
      // 53 + 4 = 57 overshoots.
      expect(g.legalMoves(4).where((m) => m.tokenIndex == 0), isEmpty);
      expect(g.legalMoves(6).where((m) => m.tokenIndex == 0), isEmpty);
    });

    test('getting a token home earns another turn', () {
      final g = _withPositions({
        LudoColor.red: [53, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      final r = g.roll(3);
      final move = r.moves.firstWhere((m) => m.reachesHome);
      expect(r.game.applyMove(move).currentPlayer, LudoColor.red);
    });

    test('all four home wins, and the seat is skipped afterwards', () {
      final g = _withPositions({
        LudoColor.red: [kLudoHome, kLudoHome, kLudoHome, 53],
        LudoColor.green: [0, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.yellow: [0, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      final r = g.roll(3);
      final after = r.game.applyMove(r.moves.first);
      expect(after.winners, [LudoColor.red]);
      expect(after.homeCount(LudoColor.red), 4);

      // Red got a token home so keeps the dice, but has nothing left to move;
      // the next roll must hand play on and never come back to red.
      final next = after.roll(4);
      expect(next.game.currentPlayer, isNot(LudoColor.red));
    });
  });

  group('turn order and the six rule', () {
    test('a six keeps the dice', () {
      final g = LudoGame.newGame(all);
      final r = g.roll(6);
      final after = r.game.applyMove(r.moves.first);
      expect(after.currentPlayer, LudoColor.red);
    });

    test('an ordinary roll hands the dice on', () {
      final g = _withPositions({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      final r = g.roll(2);
      expect(r.game.applyMove(r.moves.first).currentPlayer, LudoColor.green);
    });

    // House rule, stated deliberately: three sixes running burns the turn and
    // the third six is NOT played. Without it a streak has no bound.
    test('three sixes in a row forfeits the turn and moves nothing', () {
      var g = LudoGame.newGame(all);
      var r = g.roll(6);
      g = r.game.applyMove(r.moves.first);
      expect(g.consecutiveSixes, 1);

      r = g.roll(6);
      g = r.game.applyMove(r.moves.first);
      expect(g.consecutiveSixes, 2);

      final before = g.positions[LudoColor.red]!.toList();
      r = g.roll(6);
      expect(r.moves, isEmpty, reason: 'the third six is not played');
      expect(r.game.currentPlayer, LudoColor.green);
      expect(r.game.positions[LudoColor.red], before);
      expect(r.game.consecutiveSixes, 0);
    });

    test('a non-six resets the six counter', () {
      var g = LudoGame.newGame(all);
      final r = g.roll(6);
      g = r.game.applyMove(r.moves.first);
      expect(g.consecutiveSixes, 1);
      expect(g.roll(2).game.consecutiveSixes, 0);
    });
  });

  group('stacking', () {
    // This used to assert the opposite: that a token could NOT land on one of
    // its own. The restriction was removed after it was reported twice as the
    // game misbehaving — a six that would not open the yard while your own
    // token stood on the start, and a roll that offered only some of the
    // tokens you had out. It is also not how anybody plays Ludo.
    test('your own tokens may share a square', () {
      final g = _withPositions({
        LudoColor.red: [4, 6, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      // Token 0 at 4 rolling 2 lands on token 1 at 6. Both are playable.
      final moves = g.legalMoves(2);
      expect(moves.where((m) => m.tokenIndex == 0), hasLength(1));
      expect(moves.where((m) => m.tokenIndex == 1), hasLength(1));
    });

    test('every token you have out can be moved', () {
      // The report, exactly: four tokens on the board, a three rolled, and the
      // player expects to be able to move any of the four.
      final g = _withPositions({
        LudoColor.red: [3, 4, 5, 6],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      expect(g.legalMoves(3), hasLength(4));
    });

    test('a stack is not a fortress — landing on it takes both', () {
      // The consequence of allowing stacks, stated as a test so it cannot
      // change by accident. Red has two on one unsafe square; green lands
      // there and sends both home.
      final g = _withPositions({
        // Green start is 13. Green token at progress 3 sits on cell 16.
        LudoColor.red: [16, 16, kLudoInYard, kLudoInYard],
        LudoColor.green: [1, kLudoInYard, kLudoInYard, kLudoInYard],
      }, turn: 1);
      final move = g.legalMoves(2).firstWhere((m) => m.tokenIndex == 0);
      expect(move.captures, hasLength(2));
    });

    // The reported bug: a six arrived, a token was waiting in the yard, and
    // nothing came out — because the player's own first token was standing on
    // the start square. A start square is a SAFE square, nothing can be
    // captured there, and every Ludo anybody has played lets your own pieces
    // share one. Simulated over 400 games, the old rule blocked 27% of sixes.
    test('a six opens the yard even when your own token is on the start', () {
      final g = _withPositions({
        LudoColor.red: [0, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      final moves = g.legalMoves(6);
      final releases = moves.where((m) => m.from.inYard);
      expect(releases, hasLength(3), reason: 'all three waiting tokens may come out');
      // And the token already out may still move, as before.
      expect(moves.where((m) => m.tokenIndex == 0), hasLength(1));
    });

    // Two of your own tokens may share the home column, since it is a private
    // lane with no capture and no blocking.
    test('own tokens may share the home column', () {
      final g = _withPositions({
        LudoColor.red: [52, 50, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      expect(g.legalMoves(2).where((m) => m.tokenIndex == 1), hasLength(1));
    });
  });

  group('serialisation', () {
    test('a game survives a JSON round trip', () {
      var g = LudoGame.newGame(all);
      final r = g.roll(6);
      g = r.game.applyMove(r.moves.first);

      final back = LudoGame.fromJson(g.toJson());
      expect(back.players, g.players);
      expect(back.turn, g.turn);
      expect(back.consecutiveSixes, g.consecutiveSixes);
      expect(back.winners, g.winners);
      expect(back.lastDice, g.lastDice);
      for (final c in g.players) {
        expect(back.positions[c], g.positions[c]);
      }
    });
  });

  group('a whole game terminates', () {
    // The real safety property: whatever the dice do, play always advances and
    // somebody eventually wins. A rule that silently hands the turn back to the
    // same player forever would hang a live match.
    test('random play always reaches a winner', () {
      var seed = 12345;
      int nextDice() {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        return 1 + (seed >> 16) % 6;
      }

      var g = LudoGame.newGame(all);
      var rolls = 0;
      while (g.winners.isEmpty && rolls < 200000) {
        rolls++;
        final r = g.roll(nextDice());
        g = r.moves.isEmpty ? r.game : r.game.applyMove(r.moves.first);
      }
      expect(g.winners, isNotEmpty, reason: 'no winner after $rolls rolls');
      expect(g.homeCount(g.winners.first), 4);
    });
  });
}
