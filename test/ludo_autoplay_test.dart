// Auto-play.
//
// chooseLudoMove is a deliberate MIRROR of chooseBotMove in
// functions/ludo_logic.js. Auto-play uses it on the device; the server uses its
// copy when a turn times out. If the two rank differently, the same position
// plays one way when you are connected and another when you are not — a
// difference nobody can describe well enough to report.
//
// So these tests assert the RANKING, not just that something is returned: a
// chooser that always picked the first legal move would pass a weaker test and
// make auto-play useless.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

LudoMove move({
  int from = 5,
  int to = 10,
  int captures = 0,
  LudoColor color = LudoColor.red,
  int tokenIndex = 0,
}) => LudoMove(
  color: color,
  tokenIndex: tokenIndex,
  from: LudoTokenPos(from),
  to: LudoTokenPos(to),
  captures: [
    for (var i = 0; i < captures; i++)
      (color: LudoColor.green, tokenIndex: i),
  ],
);

void main() {
  group('nothing to play', () {
    test('an empty list picks nothing rather than throwing', () {
      expect(chooseLudoMove(LudoColor.red, const []), isNull);
    });

    test('a single move is simply taken', () {
      final only = move();
      expect(chooseLudoMove(LudoColor.red, [only]), same(only));
    });
  });

  group('the ranking matches the server', () {
    test('a capture beats an ordinary move and leaving the yard', () {
      final capture = move(to: 12, captures: 1);
      final leavingYard = move(from: kLudoInYard, to: 0, tokenIndex: 2);
      final step = move(from: 3, to: 6, tokenIndex: 3);
      expect(
        chooseLudoMove(LudoColor.red, [leavingYard, step, capture]),
        same(capture),
      );
    });

    test('bringing a token home outscores a single early capture', () {
      // Verified against node rather than assumed: the server's chooser makes
      // the same call. Home scores 80 plus half its progress (28) = 108; a
      // capture at progress 12 scores 100 plus 6 = 106. So the progress term
      // decides it, and a capture LATER on the track wins instead — which the
      // next test pins, so the balance cannot drift unnoticed.
      final goingHome = move(to: kLudoHome, tokenIndex: 1);
      final earlyCapture = move(to: 12, captures: 1);
      expect(
        chooseLudoMove(LudoColor.red, [earlyCapture, goingHome]),
        same(goingHome),
      );
    });

    test('a capture far along the track beats going home', () {
      // Progress 45: 100 + 22.5 = 122.5 against home's 108.
      final lateCapture = move(from: 40, to: 45, captures: 1);
      final goingHome = move(to: kLudoHome, tokenIndex: 1);
      expect(
        chooseLudoMove(LudoColor.red, [goingHome, lateCapture]),
        same(lateCapture),
      );
    });

    test('two captures beat one', () {
      final one = move(to: 12, captures: 1);
      final two = move(to: 11, captures: 2, tokenIndex: 1);
      expect(chooseLudoMove(LudoColor.red, [one, two]), same(two));
    });

    test('reaching home beats leaving the yard', () {
      final home = move(to: kLudoHome);
      final yard = move(from: kLudoInYard, to: 0, tokenIndex: 1);
      expect(chooseLudoMove(LudoColor.red, [yard, home]), same(home));
    });

    test('leaving the yard beats an ordinary step', () {
      final yard = move(from: kLudoInYard, to: 0);
      final step = move(from: 5, to: 9, tokenIndex: 1);
      expect(chooseLudoMove(LudoColor.red, [step, yard]), same(yard));
    });

    test('a safe square beats an unsafe one at similar progress', () {
      // Red enters at 0, so progress 8 is ring cell 8 — a star.
      final safe = move(from: 4, to: 8);
      final unsafe = move(from: 5, to: 9, tokenIndex: 1);
      expect(chooseLudoMove(LudoColor.red, [unsafe, safe]), same(safe));
    });

    test('with nothing else to separate them, the leading token moves on', () {
      final behind = move(from: 3, to: 5);
      final ahead = move(from: 20, to: 22, tokenIndex: 1);
      expect(chooseLudoMove(LudoColor.red, [behind, ahead]), same(ahead));
    });
  });

  group('it is a real choice, not the first item', () {
    test('the best move is found wherever it sits in the list', () {
      // A chooser that returned moves.first would pass several tests above by
      // luck. Here the winner is deliberately last, then deliberately first.
      final ordinary = move(from: 3, to: 5);
      final capture = move(to: 12, captures: 1, tokenIndex: 1);
      expect(chooseLudoMove(LudoColor.red, [ordinary, capture]), same(capture));
      expect(chooseLudoMove(LudoColor.red, [capture, ordinary]), same(capture));
    });

    test('every colour is ranked on its own path', () {
      // Safety is a property of the SHARED ring cell, so the same progress is
      // safe for one colour and not another. Green enters at 13, so progress 8
      // is ring 21 — also a star — while progress 7 is not.
      final safeForGreen = move(from: 4, to: 8, color: LudoColor.green);
      final plain = move(from: 4, to: 7, color: LudoColor.green, tokenIndex: 1);
      expect(
        chooseLudoMove(LudoColor.green, [plain, safeForGreen]),
        same(safeForGreen),
      );
    });
  });

  group('auto-play never plays an illegal move', () {
    test('it only ever returns a move it was given', () {
      final options = [
        move(from: 3, to: 5),
        move(from: kLudoInYard, to: 0, tokenIndex: 1),
        move(to: 12, captures: 1, tokenIndex: 2),
      ];
      final pick = chooseLudoMove(LudoColor.red, options);
      expect(options, contains(pick));
    });

    test('a real position produces a move the engine agrees is legal', () {
      // The strongest form: generate the moves from the engine, let the chooser
      // pick, and confirm the pick is one the engine offered.
      final g = LudoGame(
        players: const [LudoColor.red, LudoColor.green],
        positions: {
          LudoColor.red: [1, 7, kLudoInYard, kLudoInYard],
          LudoColor.green: [12, kLudoInYard, kLudoInYard, kLudoInYard],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [],
        lastDice: 6,
      );
      final legal = g.legalMoves(6);
      expect(legal, isNotEmpty);
      final pick = chooseLudoMove(LudoColor.red, legal);
      expect(legal, contains(pick));
    });
  });
}
