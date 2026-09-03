// The ad page a buyer decides on, and the list they come back to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('a description that runs long', () {
    const long =
        'SUIT DETAILS:\n'
        'Front: Fully Heavy Embroidered Chiffon with Adda Work\n'
        'Neck: Heavy Embroidered Neck on Fabric with Adda Work\n'
        'Border: Heavy Embroidered Front Border with Pearls Work\n'
        'Sleeves: Heavy Embroidered Sleeves with Heavy Adda Work\n'
        'Cuffs: Heavy Embroidered Sleeves Cuff\n'
        'Back: Chiffon Back with Back Border\n'
        'Dupatta: Heavy Embroidered Chiffon Dupatta\n'
        '04 Sides Heavy Embroidered Cutwork Border\n'
        'Trouser: Shamoz Silk Fabric';

    Future<void> pump(WidgetTester tester, String text) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExpandableText(text: text, collapsedLines: 4),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('is offered with a Show more', (tester) async {
      await pump(tester, long);
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('opens and closes again', (tester) async {
      await pump(tester, long);

      await tester.tap(find.text('Show more'));
      await tester.pump();
      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);

      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('a short description is left alone', (tester) async {
      // The toggle appears only when the text really is longer than the
      // limit. A "Show more" over two lines of text is noise.
      await pump(tester, 'Barely used, box included.');
      expect(find.text('Show more'), findsNothing);
      expect(find.text('Show less'), findsNothing);
    });

    testWidgets('the text itself is always on screen', (tester) async {
      await pump(tester, long);
      expect(find.textContaining('SUIT DETAILS'), findsOneWidget);
    });
  });

  group('favourites come back newest first', () {
    test('the most recently saved is at the top', () {
      // There was no ordering at all, so Firestore returned saved ads by
      // document id — arbitrary, from the user's point of view. Somebody
      // saved an ad and it appeared somewhere in the middle.
      final sorted = byNewestSaved(
        [('old', 100), ('newest', 900), ('middle', 500)],
        (r) => r.$2,
      );
      expect(sorted.map((r) => r.$1), ['newest', 'middle', 'old']);
    });

    test('a favourite saved before timestamps existed is not lost', () {
      // Ordering in the QUERY would have dropped these entirely. Sorting
      // here only sinks them.
      final sorted = byNewestSaved(
        [('untimed', 0), ('recent', 500)],
        (r) => r.$2,
      );
      expect(sorted.map((r) => r.$1), ['recent', 'untimed']);
      expect(sorted.length, 2, reason: 'nothing may disappear');
    });

    test('an empty list stays empty', () {
      expect(byNewestSaved(<(String, int)>[], (r) => r.$2), isEmpty);
    });

    test('the original list is not reordered under the caller', () {
      final original = [('a', 1), ('b', 2)];
      byNewestSaved(original, (r) => r.$2);
      expect(original.map((r) => r.$1), ['a', 'b']);
    });
  });

  group('re-reading saved ads in batches', () {
    test('a short list is one query', () {
      expect(idBatches(['a', 'b', 'c']), [
        ['a', 'b', 'c'],
      ]);
    });

    test('exactly one batch stays one batch', () {
      final ids = List.generate(30, (i) => 'id$i');
      expect(idBatches(ids).length, 1);
    });

    test('one over the limit splits', () {
      final ids = List.generate(31, (i) => 'id$i');
      final batches = idBatches(ids);
      expect(batches.length, 2);
      expect(batches.first.length, 30);
      expect(batches.last.length, 1);
    });

    test('a full list of favourites is a handful of queries, not 200', () {
      final ids = List.generate(kMyListCap, (i) => 'id$i');
      final batches = idBatches(ids);
      expect(batches.length, lessThan(10));
      expect(
        batches.expand((b) => b).toSet().length,
        kMyListCap,
        reason: 'every id is asked for exactly once',
      );
    });

    test('no favourites means no queries', () {
      expect(idBatches([]), isEmpty);
    });

    test('every batch is within what Firestore accepts', () {
      final ids = List.generate(97, (i) => 'id$i');
      for (final b in idBatches(ids)) {
        expect(b.length, lessThanOrEqualTo(30));
        expect(b, isNotEmpty);
      }
    });
  });
}
