// Asking for the next page when there is nothing to scroll.
//
// The trigger listened only for ScrollNotification, which arrives when
// somebody SCROLLS. A page of results shorter than the screen has nothing to
// scroll, so the next page was never requested: the list sat at whatever it
// had, under a count reading "2+ results", above a screenful of nothing.
//
// On a marketplace this young that is most searches, and it reads as the app
// being broken rather than as the search being narrow. Found by searching
// "shoes" on the live site and photographing the result.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Future<void> _pump(WidgetTester tester, Widget list, VoidCallback onLoadMore) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfiniteScrollTrigger(onLoadMore: onLoadMore, child: list),
        ),
      ),
    );

void main() {
  testWidgets('a list too short to scroll still asks for more', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var asked = 0;
    // Two results on an 800px screen: nothing to scroll, which is exactly the
    // case that used to stall.
    await _pump(
      tester,
      ListView(children: const [SizedBox(height: 100), SizedBox(height: 100)]),
      () => asked++,
    );
    await tester.pump();

    expect(asked, greaterThan(0), reason: 'a short list must still load more');
  });

  testWidgets('a long list does not ask until it is scrolled near the end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var asked = 0;
    await _pump(
      tester,
      ListView(
        children: [for (var i = 0; i < 40; i++) const SizedBox(height: 200)],
      ),
      () => asked++,
    );
    await tester.pump();
    // 8000px of content, a 600px threshold: the top of the list is nowhere
    // near the bottom, so nothing should be requested yet.
    expect(asked, 0, reason: 'a full screen of results is not the end of them');

    await tester.drag(find.byType(ListView), const Offset(0, -8000));
    await tester.pump();
    expect(asked, greaterThan(0), reason: 'reaching the end must load more');
  });

  testWidgets('it settles instead of asking for ever', (tester) async {
    // The risk of listening to metrics rather than to scrolling: if every
    // request produced another notification, a list at its end would spin.
    // It cannot, because a load that adds nothing changes no metrics.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var asked = 0;
    await _pump(
      tester,
      ListView(children: const [SizedBox(height: 100)]),
      () => asked++,
    );
    await tester.pump();
    final afterFirstFrame = asked;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      asked,
      afterFirstFrame,
      reason: 'idle frames must not keep asking for pages',
    );
  });
}
