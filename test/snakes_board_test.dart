// A picture of the Saanp Seerhi board.
//
// The board is drawn from the same list the rules use, so a snake cannot be
// painted where none exists — but "the ladder runs off the edge" and "the
// snake is a knot" are still only visible by looking.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  testWidgets('the board paints', (tester) async {
    tester.view.physicalSize = const Size(520, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final game = SnakesGame(
      // One piece near the start, one mid-board, one on a ladder foot, and two
      // sharing a square so the fan is in the picture.
      positions: const [4, 45, 82, 45],
      turn: 0,
      consecutiveSixes: 0,
      winner: null,
      lastMove: null,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 520, child: SnakesBoard(game: game))))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(SnakesBoard), matchesGoldenFile('goldens/snakes_board.png'));
  });
}
