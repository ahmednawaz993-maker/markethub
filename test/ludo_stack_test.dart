// Two of your own tokens on one square.
//
// This became possible when the "a token may not land on one of its own" rule
// was removed — the rule that made a six unable to open the yard while your
// first token stood on the start, and made a roll offer only some of the
// tokens you had out. Both were reported as the game misbehaving.
//
// Drawing is the part that can silently go wrong: two pieces at the same
// coordinates land exactly on top of each other, and the buried one is not
// only invisible but untappable, so the move it offers cannot be played. Same
// colour, same square means the same moves, so they are drawn as ONE piece
// carrying a count.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

LudoGame _game(Map<LudoColor, List<int>> pos) => LudoGame(
  players: LudoBoardSpec.four.colours,
  positions: {
    for (final c in LudoBoardSpec.four.colours)
      c: pos[c] ?? const [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
  },
  turn: 0,
  consecutiveSixes: 0,
  winners: const [],
  lastDice: 6,
);

Future<void> _pump(WidgetTester tester, LudoGame game,
    {void Function(LudoMove)? onMove}) async {
  tester.view.physicalSize = const Size(440, 440);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 440,
            child: LudoBoard(
              game: game,
              moves: game.legalMoves(game.lastDice!),
              onMove: onMove,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('two of a colour on one square are drawn as one piece with a 2',
      (tester) async {
    await _pump(tester, _game({LudoColor.red: [0, 0, 12, kLudoInYard]}));
    expect(tester.takeException(), isNull);
    expect(find.text('2'), findsOneWidget);
    // Not three widgets stacked invisibly on top of each other.
    expect(find.text('3'), findsNothing);
  });

  testWidgets('three on one square say three', (tester) async {
    await _pump(tester, _game({LudoColor.green: [7, 7, 7, kLudoInYard]}));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a lone token wears no number at all', (tester) async {
    await _pump(tester, _game({LudoColor.red: [0, 12, 20, kLudoInYard]}));
    for (final n in ['1', '2', '3', '4']) {
      expect(find.text(n), findsNothing, reason: 'a single piece is unlabelled');
    }
  });

  testWidgets('a stacked piece is still playable', (tester) async {
    // The failure this guards: the piece drawn on top takes the taps, so if
    // the stack were drawn as two overlapping widgets the move offered by the
    // buried one could never be played.
    LudoMove? played;
    final game = _game({LudoColor.red: [0, 0, kLudoInYard, kLudoInYard]});
    await _pump(tester, game, onMove: (m) => played = m);
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(played, isNotNull);
    expect(played!.color, LudoColor.red);
  });

  testWidgets('tokens waiting in the yard are never merged', (tester) async {
    // Yard tokens each have their own seat in the corner, so four in the yard
    // must still read as four pieces, not one wearing a 4.
    await _pump(tester, _game({}));
    expect(find.text('4'), findsNothing);
  });
}
