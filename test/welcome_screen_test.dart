// The page shown before sign-in.
//
// It exists so that a first-time visitor — and an app-store reviewer, who will
// not create an account either — can see what PakBazar is before being asked
// for anything. So the things worth testing are that the explanation is there,
// that both ways in are there, and that it still explains the platform when
// the live-listings strip cannot load, which is exactly the state a reviewer
// on a bad connection would see.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: const WelcomeScreen(),
    ),
  );
  // The feed fetch fails in a test (no network), which is the point of the
  // first test below. Let it settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('it explains the platform without any network', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);

    // What the platform IS, said plainly at the top.
    expect(find.text('PakBazar'), findsOneWidget);
    expect(find.text('Pakistan’s online marketplace.'), findsOneWidget);
    expect(find.textContaining('a place to buy and sell'), findsOneWidget);

    // And the three things somebody deciding whether to open a marketplace
    // actually wants to know.
    expect(find.text('Your money is held safely'), findsOneWidget);
    expect(find.text('Selling is free'), findsOneWidget);
    expect(find.text('Checked before it appears'), findsOneWidget);
  });

  testWidgets('the money story is spelled out, because it is the point', (
    tester,
  ) async {
    await _pump(tester);
    // Escrow is the reason to use a marketplace rather than meet a stranger
    // with cash, so it has to be on the page in words.
    expect(find.textContaining('held until the item reaches'), findsWidgets);
    expect(find.textContaining('Cash on delivery'), findsOneWidget);
  });

  testWidgets('both ways in are offered', (tester) async {
    await _pump(tester);
    // Sign in, and browse without an account. The second matters most here:
    // the app has had anonymous sign-in all along, buried at the bottom of the
    // login form where nobody arriving for the first time would find it.
    expect(find.text('Create account or sign in'), findsWidgets);
    expect(find.text('Browse without an account'), findsOneWidget);
    // And sign-in is reachable from the very top without scrolling, for
    // somebody who already has an account.
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('it names categories the marketplace actually carries', (
    tester,
  ) async {
    await _pump(tester);
    // Taken from the live stock. The first draft of this page advertised
    // livestock, which PakBazar does not sell — the quickest way to make a
    // landing page a lie is to describe a marketplace you wish you had.
    for (final c in const [
      'Women Essentials',
      'Home & Furniture',
      'Mobiles & Tablets',
      'Motors',
    ]) {
      expect(find.text(c), findsOneWidget, reason: '$c should be listed');
    }
    expect(find.textContaining('livestock'), findsNothing);
  });

  testWidgets('the safety claims are the ones the app actually implements', (
    tester,
  ) async {
    await _pump(tester);
    // Every line here describes something in this codebase — moderation of new
    // ads, ID verification, escrow, refunds, blocking, and the fact that the
    // public feed and the SEO pages never carry a phone number. A landing page
    // that promises something the app does not do is a lie told to a reviewer.
    expect(find.textContaining('reviewed by our team'), findsOneWidget);
    expect(find.textContaining('verify their identity'), findsOneWidget);
    expect(find.textContaining('never shown publicly'), findsOneWidget);
  });

  testWidgets('the live strip is absent rather than broken when offline', (
    tester,
  ) async {
    await _pump(tester);
    // No spinner left running, no error box, no empty grey shelf — the strip
    // is evidence, and losing it must not cost the visitor the explanation.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('On PakBazar right now'), findsNothing);
    expect(find.text('Checked before it appears'), findsOneWidget);
  });

  testWidgets('it scrolls, so nothing is stranded off-screen on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    expect(find.text('Ready to start?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
