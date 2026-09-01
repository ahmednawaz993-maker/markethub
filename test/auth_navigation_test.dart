// Getting into the app after signing in.
//
// The gate decides what sits at the BOTTOM of the navigation stack. The login
// screen is pushed on top of it, so when somebody signs in the home screen
// appears underneath while they carry on looking at the login form. That is
// what "it does not open the app after signing in with Google" was.
//
// It worked before only because the login form used to be the gate's
// signed-out branch. Putting a landing page in front of it introduced the gap
// — the fix pops back to the root on the signed-out to signed-in edge, and
// this pins the edge, because getting it wrong in the other direction throws a
// browsing user out of whatever screen they were reading.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('when to clear what is stacked on the gate', () {
    test('signing in clears it', () {
      expect(shouldClearAuthRoutes(false, true), isTrue);
    });

    test('the app opening already signed in does not', () {
      // First state after launch. There is nothing pushed yet, and treating it
      // as a sign-in would pop a deep link the app had just opened on.
      expect(shouldClearAuthRoutes(null, true), isFalse);
    });

    test('a token refresh while browsing does not', () {
      // authStateChanges fires on refresh too. Popping then would throw
      // somebody out of the ad, chat or game they were in the middle of.
      expect(shouldClearAuthRoutes(true, true), isFalse);
    });

    test('signing out does not', () {
      expect(shouldClearAuthRoutes(true, false), isFalse);
      expect(shouldClearAuthRoutes(null, false), isFalse);
      expect(shouldClearAuthRoutes(false, false), isFalse);
    });
  });

  testWidgets('a pushed screen is popped when the flag says to', (
    tester,
  ) async {
    // The mechanism itself, without Firebase: push a screen over a root, then
    // do what the gate does on the sign-in edge.
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('login'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);

    if (shouldClearAuthRoutes(false, true)) {
      final nav = navKey.currentState!;
      if (nav.canPop()) nav.popUntil((r) => r.isFirst);
    }
    await tester.pumpAndSettle();

    expect(find.text('login'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  test('the gate actually uses the rule', () {
    // A source check, because the wiring is the part that broke: the rule
    // being right is no help if the gate does not consult it.
    final src = File(
      'lib/src/app.dart',
    ).readAsStringSync();
    expect(src, contains('shouldClearAuthRoutes(_wasSignedIn, signedIn)'));
    expect(src, contains('popUntil'));
  });
}
