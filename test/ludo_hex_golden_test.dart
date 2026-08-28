// A committed picture of the hexagon.
//
// The six-player board is the only one drawn from polar coordinates, and the
// one bug it has already had — every start square sitting 30 degrees off its
// own yard — was invisible to every rules test that passed at the time, because
// the rules were right and only the DRAWING was wrong. A golden is the only
// kind of test that would have caught it.
//
// Text renders in the test font, so this checks geometry: that each yard faces
// its own start, that the ring closes, that home columns run inward.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  testWidgets('the six-player board paints', (tester) async {
    tester.view.physicalSize = const Size(440, 440);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // One token of each colour out on the ring, one part-way home, two still in
    // the yard — so the picture shows every state a token can be in.
    final spec = LudoBoardSpec.six;
    final game = LudoGame(
      players: spec.colours,
      positions: {
        for (var i = 0; i < spec.seats; i++)
          spec.colours[i]: [
            spec.startCellOf(spec.colours[i]),
            spec.lastRingStep + 2,
            kLudoInYard,
            kLudoInYard,
          ],
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
            child: SizedBox(width: 440, child: LudoHexBoard(game: game)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(LudoHexBoard),
      matchesGoldenFile('goldens/ludo_hex_board.png'),
    );
  });
}
