// Playing Saanp Seerhi on the screen.
//
// The engine is tested separately; what can only go wrong here is the sequence
// the screen puts around a roll — the piece has to be shown landing on the
// square the die gave it BEFORE the snake takes it away, or the whole point of
// the game happens off-screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Future<void> _pumpGame(
  WidgetTester tester, {
  int players = 2,
  bool vsComputer = false,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SnakesScreen(players: players, vsComputer: vsComputer),
    ),
  );
  await tester.pump();
}

/// Pumps until [condition] holds, or gives up.
///
/// A roll is a CHAIN of awaited delays — read the number, step the piece,
/// slide down the snake — and a single pump(duration) advances the clock once,
/// which is not enough to drain a chain. pumpAndSettle does not help either:
/// it returns as soon as no frame is scheduled, and a pending Future.delayed
/// schedules none. The result was a test that passed on its own and failed
/// only in the full parallel suite, which is the worst kind.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('the setup screen offers 2 to 4 players and starts a game', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SnakesSetupScreen()));
    await tester.pump();

    for (final n in ['2', '3', '4']) {
      expect(find.widgetWithText(ChoiceChip, n), findsOneWidget);
    }
    // The rules are on the setup screen, because a player who has to guess
    // whether they need a six to start will guess wrong.
    expect(find.textContaining('exactly'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SnakesBoard), findsOneWidget);
  });

  testWidgets('the board and both players are on screen', (tester) async {
    await _pumpGame(tester);
    expect(find.byType(SnakesBoard), findsOneWidget);
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    expect(find.textContaining('Tap the dice'), findsOneWidget);
  });

  testWidgets('rolling moves a piece and hands the turn on', (tester) async {
    await _pumpGame(tester);
    expect(find.textContaining("Player 1's turn"), findsOneWidget);

    await tester.tap(find.byType(LudoDice));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.textContaining('Tap the dice').evaluate().isEmpty,
    );

    // Either it is now player 2's turn, or player 1 rolled a six and goes
    // again. Both are correct; a screen stuck on neither is not.
    final onePlays = find.textContaining("Player 1's turn").evaluate().isNotEmpty;
    final twoPlays = find.textContaining("Player 2's turn").evaluate().isNotEmpty;
    expect(onePlays || twoPlays, isTrue);
    expect(find.textContaining('Tap the dice'), findsNothing);
  });

  testWidgets('single player reads as Your turn, not the possessive of You', (
    tester,
  ) async {
    await _pumpGame(tester, vsComputer: true);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.textContaining("You's"), findsNothing);
  });

  testWidgets('the computer takes its own turn without being tapped', (
    tester,
  ) async {
    await _pumpGame(tester, vsComputer: true);
    // Player one is the human, so the computer only moves after they do.
    await tester.tap(find.byType(LudoDice));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.textContaining('Tap the dice').evaluate().isEmpty,
    );
    // The computer has rolled at least once by now, so the board is no longer
    // in its opening state.
    expect(find.textContaining('Tap the dice'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a game played to the end offers another', (tester) async {
    // Played rather than injected: the screen's state is private to its own
    // library, and reaching into it would test a back door instead of the game.
    // An average game is about forty rolls, so three hundred taps is a wide
    // margin — and if it ever runs out, that is a game that cannot be won,
    // which is worth failing over.
    await _pumpGame(tester);
    var taps = 0;
    while (find.text('Play again').evaluate().isEmpty && taps < 300) {
      final dice = find.byType(LudoDice);
      if (dice.evaluate().isEmpty) break;
      await tester.tap(dice, warnIfMissed: false);
      await tester.pump();
      await _pumpUntil(tester, () => false, maxPumps: 12);
      taps++;
    }
    await tester.pumpAndSettle();

    expect(
      find.text('Play again'),
      findsOneWidget,
      reason: 'nobody won in $taps rolls',
    );
    expect(find.textContaining('wins'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Play again'));
    await tester.pump();
    expect(find.textContaining('wins'), findsNothing);
    expect(find.byType(SnakesBoard), findsOneWidget);
  });

  testWidgets('leaving mid-roll does not throw', (tester) async {
    // The roll is a sequence of awaited delays; popping the screen part way
    // through used to be the classic way to get "setState after dispose".
    await _pumpGame(tester);
    await tester.tap(find.byType(LudoDice));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
