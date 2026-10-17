// Arrow keys scroll the website.
//
// On desktop web nothing focuses a list, so Flutter's own keyboard scrolling
// never fired and the arrows did nothing on any page. KeyboardScroll catches
// the keys nothing else used and scrolls the page the user is looking at.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Widget _app(Widget home) => MaterialApp(
  builder: (context, child) => KeyboardScroll(child: child!),
  home: home,
);

Widget _longList({ScrollController? controller, Key? key}) => ListView.builder(
  key: key,
  controller: controller,
  itemCount: 200,
  itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
);

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('arrow down/up scroll the page with nothing focused', (t) async {
    final c = ScrollController();
    await t.pumpWidget(_app(Scaffold(body: _longList(controller: c))));

    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(c.offset, kKeyboardScrollLine);
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(c.offset, 2 * kKeyboardScrollLine);
    await _press(t, LogicalKeyboardKey.arrowUp);
    expect(c.offset, kKeyboardScrollLine);
  });

  testWidgets('page down, end and home', (t) async {
    final c = ScrollController();
    await t.pumpWidget(_app(Scaffold(body: _longList(controller: c))));

    await _press(t, LogicalKeyboardKey.pageDown);
    expect(c.offset, closeTo(c.position.viewportDimension * 0.8, 0.01));
    await _press(t, LogicalKeyboardKey.end);
    expect(c.offset, c.position.maxScrollExtent);
    await _press(t, LogicalKeyboardKey.home);
    expect(c.offset, 0);
  });

  testWidgets('a hidden IndexedStack tab is never the one scrolled', (t) async {
    final visible = ScrollController();
    final hidden = ScrollController();
    await t.pumpWidget(
      _app(
        Scaffold(
          body: IndexedStack(
            index: 1,
            children: [
              _longList(controller: hidden),
              _longList(controller: visible),
            ],
          ),
        ),
      ),
    );

    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(visible.offset, kKeyboardScrollLine);
    expect(hidden.offset, 0);
  });

  testWidgets('the vertical page scrolls, not a horizontal carousel', (
    t,
  ) async {
    final page = ScrollController();
    final carousel = ScrollController();
    await t.pumpWidget(
      _app(
        Scaffold(
          body: ListView(
            controller: page,
            children: [
              SizedBox(
                height: 120,
                child: ListView.builder(
                  controller: carousel,
                  scrollDirection: Axis.horizontal,
                  itemCount: 50,
                  itemBuilder: (_, i) => const SizedBox(width: 120),
                ),
              ),
              for (var i = 0; i < 100; i++) const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );

    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(page.offset, kKeyboardScrollLine);
    expect(carousel.offset, 0);
  });

  testWidgets('a reversed (chat) list scrolls the way the screen looks', (
    t,
  ) async {
    final c = ScrollController();
    await t.pumpWidget(
      _app(
        Scaffold(
          body: ListView.builder(
            controller: c,
            reverse: true,
            itemCount: 200,
            itemBuilder: (_, i) => const SizedBox(height: 40),
          ),
        ),
      ),
    );

    // Starts at the bottom (offset 0). Up goes back through older messages.
    await _press(t, LogicalKeyboardKey.arrowUp);
    expect(c.offset, kKeyboardScrollLine);
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(c.offset, 0);
  });

  testWidgets('a focused text field keeps its arrow keys', (t) async {
    final c = ScrollController();
    await t.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: [
              const TextField(autofocus: true),
              Expanded(child: _longList(controller: c)),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await _press(t, LogicalKeyboardKey.arrowDown);
    await _press(t, LogicalKeyboardKey.end);
    expect(c.offset, 0);
  });

  testWidgets('with a dialog open, the page underneath does not move', (
    t,
  ) async {
    final c = ScrollController();
    await t.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(content: Text('hi')),
                  ),
                  child: const Text('open'),
                ),
                Expanded(child: _longList(controller: c)),
              ],
            ),
          ),
        ),
      ),
    );

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(c.offset, 0);
  });

  testWidgets('a pushed page scrolls; the one under it does not', (t) async {
    final below = ScrollController();
    final top = ScrollController();
    await t.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          Scaffold(body: _longList(controller: top)),
                    ),
                  ),
                  child: const Text('go'),
                ),
                Expanded(child: _longList(controller: below)),
              ],
            ),
          ),
        ),
      ),
    );

    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(top.offset, kKeyboardScrollLine);
    expect(below.offset, 0);
  });

  test('targets clamp to the scroll range', () {
    double go(LogicalKeyboardKey k, double px, {bool reversed = false}) =>
        keyboardScrollTarget(
          pixels: px,
          min: 0,
          max: 1000,
          viewport: 500,
          reversed: reversed,
          key: k,
        );
    expect(go(LogicalKeyboardKey.arrowUp, 10), 0);
    expect(go(LogicalKeyboardKey.arrowDown, 990), 1000);
    expect(go(LogicalKeyboardKey.pageDown, 0), 400);
    expect(go(LogicalKeyboardKey.end, 0, reversed: true), 0);
    expect(go(LogicalKeyboardKey.home, 0, reversed: true), 1000);
    expect(go(LogicalKeyboardKey.keyA, 123), 123);
  });
}
