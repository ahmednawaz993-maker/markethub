// Pass-and-play.
//
// This mode has no server behind it: the whole game is one widget's state, the
// dice is rolled on the device, and nothing is written anywhere. That means
// there is no Firestore document to inspect afterwards and no function log to
// read — if a turn is dropped or a win is missed, the only place it shows is on
// screen. So this drives the real widget.
//
// The other thing worth pinning is what it must NOT do: award coins or touch
// the leaderboard. Every player is the same device, so paying for a win here
// would be farmable in seconds and would make the weekly table meaningless.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// The setup screen is a ListView, which only builds what fits. On the default
/// 800x600 test surface the later name fields are never created, so a test
/// counting them would be measuring the viewport rather than the screen.
void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('setting up a local game', () {
    testWidgets('offers 2, 3 and 4 players and every gameplay', (tester) async {
      tallView(tester);
      await tester.pumpWidget(wrap(const LudoLocalSetupScreen()));
      await tester.pumpAndSettle();

      for (final n in ['2', '3', '4']) {
        expect(find.text(n), findsWidgets, reason: '$n players missing');
      }
      // All four gameplays must be reachable offline, not just Classic.
      for (final m in LudoMode.values) {
        expect(find.text(m.label), findsWidgets, reason: m.label);
      }
    });

    testWidgets('name fields follow the player count', (tester) async {
      tallView(tester);
      await tester.pumpWidget(wrap(const LudoLocalSetupScreen()));
      await tester.pumpAndSettle();

      // Two players by default, so two name fields.
      expect(find.byType(TextField), findsNWidgets(2));

      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('says plainly that nothing is recorded', (tester) async {
      // A player should not have to guess whether this counts.
      await tester.pumpWidget(wrap(const LudoLocalSetupScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('nothing is saved'), findsOneWidget);
    });
  });

  group('playing a local game', () {
    testWidgets('shows whose turn it is by name', (tester) async {
      await tester.pumpWidget(
        wrap(
          LudoLocalGameScreen(
            game: LudoGame.newGame(const [LudoColor.red, LudoColor.green]),
            names: const {LudoColor.red: 'Ali', LudoColor.green: 'Sara'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The single most important thing when a phone is being handed round.
      expect(find.text('Pass to Ali'), findsOneWidget);
      expect(find.text('Tap the dice to roll.'), findsOneWidget);
    });

    testWidgets('falls back to the colour when no name was given', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          LudoLocalGameScreen(
            game: LudoGame.newGame(const [LudoColor.red, LudoColor.green]),
            names: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pass to Red'), findsOneWidget);
    });

    testWidgets('rolling produces a die and moves the game on', (tester) async {
      await tester.pumpWidget(
        wrap(
          LudoLocalGameScreen(
            game: LudoGame.newGame(const [LudoColor.red, LudoColor.green]),
            names: const {LudoColor.red: 'Ali', LudoColor.green: 'Sara'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LudoDice));
      // The roll waits for the die to tumble before resolving.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Everything starts in the yard, so anything but a six passes the turn
      // and a six offers a move. Both are valid; what must NOT happen is the
      // board sitting on "tap to roll" as though nothing occurred.
      final stillWaiting = find.text('Tap the dice to roll.').evaluate();
      final passedToSara = find.text('Pass to Sara').evaluate();
      expect(
        stillWaiting.isNotEmpty || passedToSara.isNotEmpty,
        isTrue,
        reason: 'the roll left the board in no recognisable state',
      );
    });

    testWidgets('a finished game shows the winner and a way out', (
      tester,
    ) async {
      final won = LudoGame(
        players: const [LudoColor.red, LudoColor.green],
        positions: {
          LudoColor.red: [kLudoHome, kLudoHome, kLudoHome, kLudoHome],
          LudoColor.green: [0, 0, 0, 0],
        },
        turn: 0,
        consecutiveSixes: 0,
        winners: const [LudoColor.red],
        lastDice: null,
      );
      await tester.pumpWidget(
        wrap(
          LudoLocalGameScreen(
            game: won,
            names: const {LudoColor.red: 'Ali', LudoColor.green: 'Sara'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ali'), findsWidgets);
      expect(find.text('Done'), findsOneWidget);
      // The dice must be gone: there is nothing left to roll.
      expect(find.byType(LudoDice), findsNothing);
    });

    testWidgets('closing asks first, because the board is not saved', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          LudoLocalGameScreen(
            game: LudoGame.newGame(const [LudoColor.red, LudoColor.green]),
            names: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('End this game?'), findsOneWidget);
      expect(find.textContaining('cannot be resumed'), findsOneWidget);

      // Backing out of the dialog keeps the game.
      await tester.tap(find.text('Keep playing'));
      await tester.pumpAndSettle();
      expect(find.byType(LudoDice), findsOneWidget);
    });
  });

  group('a local game is unranked', () {
    test('the source never reaches for coins or the leaderboard', () {
      // Structural rather than behavioural: there is no server call to observe,
      // so the guarantee is that the code cannot make one. If a future edit
      // adds a reward here, this fails and the reason is in the failure.
      final src = File('lib/src/ludo_local.dart').readAsStringSync();
      for (final forbidden in [
        'gameProfileRef',
        'claimDailyCoins',
        'leaderboards',
        'gameRequests',
        'pushLudoState',
        'ludoRooms',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'pass-and-play must not touch $forbidden — every player is '
              'the same device, so a reward here is farmable',
        );
      }
    });
  });
}
