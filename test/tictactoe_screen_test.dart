// Playing tic-tac-toe on the screen.
//
// The engine is proven separately, including exhaustively that Hard cannot be
// beaten. What is only testable here is the wiring: that a tap plays where you
// tapped, that the computer answers on its own, and that a finished board
// stops accepting moves — the last one being how a scoreboard quietly becomes
// nonsense.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 950);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: TicTacToeScreen()));
  await tester.pump();
}

/// The marks on the board.
///
/// They are PAINTED rather than typed — a glyph is a dependency on the shipped
/// font actually containing it, and this app has shipped a blank button for
/// exactly that reason. Found by their semantics label, which they carry so a
/// screen reader can read the board out.
/// Scoped to the board, because the scoreboard above it also says "X".
Finder _mark(String label) => find.descendant(
  of: find.byKey(const ValueKey('ticBoard')),
  matching: find.bySemanticsLabel(label),
);

Finder _x() => _mark('X');
Finder _o() => _mark('O');

/// Taps cell [i] of the nine.
Future<void> _tapCell(WidgetTester tester, int i) async {
  await tester.tap(find.byType(GestureDetector).at(i), warnIfMissed: false);
  await tester.pump();
}

void main() {
  testWidgets('an empty board offers nine squares and no marks', (
    tester,
  ) async {
    await _pump(tester);
    expect(_x(), findsNothing);
    expect(_o(), findsNothing);
    expect(find.text('Your turn'), findsOneWidget);
  });

  testWidgets('tapping plays your mark, and the computer answers', (
    tester,
  ) async {
    await _pump(tester);
    await _tapCell(tester, 0);
    expect(_x(), findsOneWidget);

    // The computer pauses before replying, so its mark is not there yet.
    expect(_o(), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(_o(), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
  });

  testWidgets('an occupied square cannot be played again', (tester) async {
    await _pump(tester);
    await _tapCell(tester, 4);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final marksBefore = _x().evaluate().length;
    await _tapCell(tester, 4); // same square
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(_x().evaluate().length, marksBefore);
  });

  testWidgets('two players on one phone alternate X and O', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Play against the computer'));
    await tester.pumpAndSettle();
    expect(find.text('X to play'), findsOneWidget);

    await _tapCell(tester, 0);
    expect(_x(), findsOneWidget);
    expect(find.text('O to play'), findsOneWidget);
    await _tapCell(tester, 1);
    expect(_o(), findsOneWidget);
    expect(find.text('X to play'), findsOneWidget);
  });

  testWidgets('a finished game says so and stops taking moves', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Play against the computer'));
    await tester.pumpAndSettle();
    // X takes the top row: 0, 1, 2 with O in between.
    for (final i in [0, 3, 1, 4, 2]) {
      await _tapCell(tester, i);
    }
    await tester.pumpAndSettle();
    expect(find.text('X wins.'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);

    // A further tap must not add a mark to a finished board.
    final before = _x().evaluate().length;
    await _tapCell(tester, 8);
    await tester.pumpAndSettle();
    expect(_x().evaluate().length, before);
  });

  testWidgets('the scoreboard counts rounds', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Play against the computer'));
    await tester.pumpAndSettle();
    for (final i in [0, 3, 1, 4, 2]) {
      await _tapCell(tester, i);
    }
    await tester.pumpAndSettle();
    // One win recorded in X's column; the other two columns still zero.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));

    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();
    // The score survives the new round — that is the point of keeping it.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('X to play'), findsOneWidget);
  });

  testWidgets('leaving while the computer is thinking does not throw', (
    tester,
  ) async {
    await _pump(tester);
    await _tapCell(tester, 0);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
