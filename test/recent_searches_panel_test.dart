// Offering back the searches somebody already ran.
//
// The app has stored recent searches since they were added to Home, and the
// screen people actually search on never showed them: tapping the field gave
// you a cursor and nothing else. So a query from yesterday had to be typed
// again from memory, on a phone keyboard.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Future<void> _pump(
  WidgetTester tester,
  List<RecentSearch> items,
  void Function(RecentSearch) onRun,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: RecentSearchesPanel(items: items, onRun: onRun)),
  ),
);

void main() {
  group('what a remembered search says about itself', () {
    test('a plain query has no scope line', () {
      expect(
        RecentSearchesPanel.scopeLabel(const RecentSearch(query: 'iphone')),
        isNull,
      );
    });

    test('the city it was made in', () {
      expect(
        RecentSearchesPanel.scopeLabel(
          const RecentSearch(query: 'iphone', city: 'Lahore'),
        ),
        'in Lahore',
      );
    });

    test('the category and the city together', () {
      expect(
        RecentSearchesPanel.scopeLabel(
          const RecentSearch(
            query: 'iphone',
            category: 'Mobiles',
            city: 'Lahore',
          ),
        ),
        'Mobiles · in Lahore',
      );
    });

    test("'All' is not a scope", () {
      // Both fields carry 'All' when nothing was narrowed, and "All · in All"
      // under every row would be noise that says nothing.
      expect(
        RecentSearchesPanel.scopeLabel(
          const RecentSearch(query: 'iphone', category: 'All', city: 'All'),
        ),
        isNull,
      );
    });
  });

  group('the panel', () {
    const items = [
      RecentSearch(query: 'honda 125', city: 'Karachi'),
      RecentSearch(query: 'iphone 13'),
    ];

    testWidgets('lists what was searched for, newest first', (tester) async {
      await _pump(tester, items, (_) {});

      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('honda 125'), findsOneWidget);
      expect(find.text('iphone 13'), findsOneWidget);

      final first = tester.getTopLeft(find.text('honda 125')).dy;
      final second = tester.getTopLeft(find.text('iphone 13')).dy;
      expect(first, lessThan(second));
    });

    testWidgets('shows where a search was made', (tester) async {
      await _pump(tester, items, (_) {});
      expect(find.text('in Karachi'), findsOneWidget);
    });

    testWidgets('tapping one runs it', (tester) async {
      RecentSearch? ran;
      await _pump(tester, items, (s) => ran = s);

      await tester.tap(find.text('honda 125'));
      await tester.pump();

      expect(ran?.query, 'honda 125');
      expect(ran?.city, 'Karachi', reason: 'the scope goes with the query');
    });

    testWidgets('each row can be forgotten on its own', (tester) async {
      await _pump(tester, items, (_) {});
      // One × per remembered search, plus the "Clear all" for the lot.
      expect(find.byIcon(Icons.close), findsNWidgets(items.length));
      expect(find.text('Clear all'), findsOneWidget);
    });

    testWidgets('an empty history is not offered at all', (tester) async {
      // The panel itself is never built with nothing in it — the screen keeps
      // showing results. This pins the contract the screen relies on.
      await _pump(tester, const [], (_) {});
      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('the store behind it', () {
    setUp(() => recentSearches.value = const []);
    tearDown(() => recentSearches.value = const []);

    test('the same search twice is one entry, moved to the top', () {
      addRecentSearch(const RecentSearch(query: 'iphone'));
      addRecentSearch(const RecentSearch(query: 'honda'));
      addRecentSearch(const RecentSearch(query: 'iphone'));

      expect(recentSearches.value.map((s) => s.query), ['iphone', 'honda']);
    });

    test('the same words in a different city are a different search', () {
      // Scope is part of what was searched for: "iphone in Lahore" and
      // "iphone in Karachi" returned different things.
      addRecentSearch(const RecentSearch(query: 'iphone', city: 'Lahore'));
      addRecentSearch(const RecentSearch(query: 'iphone', city: 'Karachi'));

      expect(recentSearches.value.length, 2);
    });

    test('an empty query is not remembered', () {
      addRecentSearch(const RecentSearch(query: '   '));
      expect(recentSearches.value, isEmpty);
    });

    test('the list is capped', () {
      for (var i = 0; i < 25; i++) {
        addRecentSearch(RecentSearch(query: 'search $i'));
      }
      expect(recentSearches.value.length, lessThanOrEqualTo(10));
      expect(
        recentSearches.value.first.query,
        'search 24',
        reason: 'the newest survives, not the oldest',
      );
    });
  });
}
