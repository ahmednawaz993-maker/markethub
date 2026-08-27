import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Animation is easy to add and easy to break silently — a refactor that stops
// diffing the incoming state leaves tokens teleporting again, and nothing
// fails. These pin the behaviour rather than the appearance: that a change
// takes time, that it finishes where the game says, and that a piece in flight
// cannot be tapped.

LudoGame _game(Map<LudoColor, List<int>> positions, {int? dice}) => LudoGame(
  players: positions.keys.toList(),
  positions: positions,
  turn: 0,
  consecutiveSixes: 0,
  winners: const [],
  lastDice: dice,
);

Future<void> _pumpBoard(
  WidgetTester tester,
  LudoGame game, {
  List<LudoMove> moves = const [],
  void Function(LudoMove)? onMove,
}) async {
  tester.view.physicalSize = const Size(400, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: LudoBoard(game: game, moves: moves, onMove: onMove),
        ),
      ),
    ),
  );
}

void main() {
  group('token movement', () {
    test('a walk is measured in squares, a capture is a single hop', () {
      // Sanity on the engine values the animation keys off — a captured token
      // has no path back, so it cannot be walked.
      expect(kLudoInYard, lessThan(0));
      expect(kLudoHome, greaterThan(kLudoLastRingStep));
    });

    testWidgets('a position change takes time instead of teleporting', (
      tester,
    ) async {
      final before = _game({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      await _pumpBoard(tester, before);
      expect(
        tester.hasRunningAnimations,
        isFalse,
        reason: 'the first build must not animate',
      );

      // Red advances five squares.
      final after = _game({
        LudoColor.red: [9, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: LudoBoard(game: after, moves: const []),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.hasRunningAnimations,
        isTrue,
        reason: 'the token should be walking, not jumping',
      );

      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a longer move takes longer than a short one', (tester) async {
      Future<Duration> timeFor(int from, int to) async {
        await _pumpBoard(
          tester,
          _game({
            LudoColor.red: [from, kLudoInYard, kLudoInYard, kLudoInYard],
            LudoColor.green: [
              kLudoInYard,
              kLudoInYard,
              kLudoInYard,
              kLudoInYard,
            ],
          }),
        );
        final start = tester.binding.clock.now();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: LudoBoard(
                  game: _game({
                    LudoColor.red: [to, kLudoInYard, kLudoInYard, kLudoInYard],
                    LudoColor.green: [
                      kLudoInYard,
                      kLudoInYard,
                      kLudoInYard,
                      kLudoInYard,
                    ],
                  }),
                  moves: const [],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.binding.clock.now().difference(start);
      }

      final short = await timeFor(4, 5); // one square
      final long = await timeFor(4, 10); // six squares
      expect(
        long,
        greaterThan(short),
        reason: 'a six should visibly take longer than a one',
      );
    });

    testWidgets('a captured token returns to the yard without crashing', (
      tester,
    ) async {
      await _pumpBoard(
        tester,
        _game({
          LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
          LudoColor.green: [20, kLudoInYard, kLudoInYard, kLudoInYard],
        }),
      );
      // Green is sent home; red advances. Both animate at once.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: LudoBoard(
                game: _game({
                  LudoColor.red: [7, kLudoInYard, kLudoInYard, kLudoInYard],
                  LudoColor.green: [
                    kLudoInYard,
                    kLudoInYard,
                    kLudoInYard,
                    kLudoInYard,
                  ],
                }),
                moves: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // A second tap mid-animation would play a move against a board the player
    // can no longer see.
    testWidgets('a token in flight cannot be tapped', (tester) async {
      final before = _game({
        LudoColor.red: [4, kLudoInYard, kLudoInYard, kLudoInYard],
        LudoColor.green: [kLudoInYard, kLudoInYard, kLudoInYard, kLudoInYard],
      }, dice: 3);
      final moves = before.legalMoves(3);
      expect(moves, isNotEmpty);

      var taps = 0;
      await _pumpBoard(tester, before, moves: moves, onMove: (_) => taps++);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(taps, 1, reason: 'a settled token is tappable');

      // Now start a flight and try again.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: LudoBoard(
                game: _game({
                  LudoColor.red: [7, kLudoInYard, kLudoInYard, kLudoInYard],
                  LudoColor.green: [
                    kLudoInYard,
                    kLudoInYard,
                    kLudoInYard,
                    kLudoInYard,
                  ],
                }, dice: 3),
                moves: moves,
                onMove: (_) => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(taps, 1, reason: 'no move may be played mid-flight');
      await tester.pumpAndSettle();
    });
  });

  group('the dice face', () {
    testWidgets('renders every face and the pre-roll state', (tester) async {
      for (final v in [null, 1, 2, 3, 4, 5, 6]) {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: LudoDieFace(value: v)))),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'face $v');
      }
    });

    // The face shown while waiting is never the real value — it is scratch
    // theatre. What matters is that once rolling stops, the server's number is
    // what is displayed.
    testWidgets('settles on the value it was given, not a made-up one', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: LudoDice(value: 4, rolling: true))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.hasRunningAnimations, isTrue, reason: 'it should tumble');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: LudoDice(value: 4, rolling: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final face = tester.widget<LudoDieFace>(find.byType(LudoDieFace));
      expect(face.value, 4);
      expect(tester.takeException(), isNull);
    });
  });

  group('rendered', () {
    testWidgets('the six faces read as dice', (tester) async {
      tester.view.physicalSize = const Size(420, 160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFFF7F8FA),
            body: Center(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var v = 1; v <= 6; v++) LudoDieFace(value: v, size: 56),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(Wrap),
        matchesGoldenFile('goldens/ludo_dice_faces.png'),
      );
    });
  });
}
