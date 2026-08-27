// Deep links must land on the thing that was shared.
//
// THE BUG THIS PINS. Flutter web defaults to the HASH url strategy: the route
// comes from the fragment and the browser PATH is ignored. Firebase Hosting
// rewrites everything to index.html, so https://pakbazar24.com/ad/123 loaded
// the app and the address bar looked right — while Flutter saw an empty route
// and rendered the home screen. Every shared ad link and every Ludo invite
// landed on the login page.
//
// Nothing failed. The parsers were correct, generateAppRoute was correct, and
// their unit tests passed, because the path never reached them. So this file
// tests the two halves that were actually broken:
//
//   1. the ROUTING CONTRACT — MaterialApp(onGenerateRoute + home) really does
//      build a deep screen on top of home for a path initial route;
//   2. the WIRING — main() switches the web build to the path strategy, which
//      is the part no widget test can observe.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

/// Mirrors PakBazarApp's Navigator configuration: onGenerateRoute plus a home,
/// and deliberately no `routes` table — the combination that decides how an
/// initial path like /ad/123 is turned into a stack.
Widget appWithRoute(String route) => MaterialApp(
  initialRoute: route,
  onGenerateRoute: (settings) {
    final r = generateAppRoute(settings);
    if (r != null) {
      // Substitute a marker for the real screen: the screens themselves need
      // Firebase, and what is under test is the ROUTING, not their contents.
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(body: Text('DEEP ${settings.name}')),
      );
    }
    return null;
  },
  home: const Scaffold(body: Text('HOME')),
);

void main() {
  group('a path URL resolves to the shared screen', () {
    for (final path in [
      '/ad/abc123',
      '/ludo/room789',
      '/ad/abc123/', // a trailing slash, as pasted from a browser
    ]) {
      testWidgets(path, (tester) async {
        await tester.pumpWidget(appWithRoute(path));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('DEEP'),
          findsOneWidget,
          reason: '$path must open the deep-linked screen, not the home page',
        );
      });
    }

    testWidgets('an unknown path still lands the user in the app', (
      tester,
    ) async {
      // A stale or malformed link must not be a dead end.
      await tester.pumpWidget(appWithRoute('/nonsense/x'));
      await tester.pumpAndSettle();
      // Flutter reports "Could not navigate to initial route" and falls back to
      // "/". That message is the framework describing the behaviour we want, so
      // it is consumed rather than failing the test — but it IS asserted, so a
      // future change that starts throwing something else here gets caught.
      final logged = tester.takeException();
      expect(logged, isNotNull);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('the bare root is the home page', (tester) async {
      await tester.pumpWidget(appWithRoute('/'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.textContaining('DEEP'), findsNothing);
    });
  });

  group('the web build is wired to read the URL path', () {
    // A source check, because the failure lives in configuration that no
    // widget test can reach: usePathUrlStrategy() runs once, before runApp,
    // and only in the web build.
    test('main() configures the url strategy before runApp', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(
        src.contains('configureUrlStrategy()'),
        isTrue,
        reason: 'main() must call configureUrlStrategy()',
      );
      final call = src.indexOf('configureUrlStrategy()');
      final run = src.indexOf('runApp(');
      expect(
        call < run && run > 0,
        isTrue,
        reason: 'the strategy must be set BEFORE runApp — MaterialApp reads '
            'the initial route once, at build time',
      );
    });

    test('the web implementation opts into path URLs', () {
      final web = File('lib/url_strategy_web.dart').readAsStringSync();
      expect(
        web.contains('usePathUrlStrategy()'),
        isTrue,
        reason: 'without this, Flutter web reads the route from the URL '
            'fragment and ignores the path entirely',
      );
    });

    test('the mobile stub pulls in no web-only package', () {
      // flutter_web_plugins does not exist off the web; importing it in the
      // shared half would break the Android build.
      final stub = File('lib/url_strategy_stub.dart').readAsStringSync();
      // Match a real import directive, not the comment that explains why there
      // must not be one.
      expect(
        RegExp(r'''^\s*import\s+.*flutter_web_plugins''', multiLine: true)
            .hasMatch(stub),
        isFalse,
      );
    });
  });
}
