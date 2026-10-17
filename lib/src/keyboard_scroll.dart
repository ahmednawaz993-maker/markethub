part of '../main.dart';

// Arrow-key scrolling for the website (and any device with a keyboard).
//
// Flutter only scrolls with the keyboard when the list itself holds focus, and
// on desktop web nothing ever focuses one — a click on a card focuses nothing,
// and ListViews there do not attach to the PrimaryScrollController that the
// built-in ScrollAction falls back to. So the arrows did nothing on every page.
//
// This sits around the Navigator and catches the keys nothing below it used,
// then scrolls the page the user is looking at: the largest vertical list that
// is on screen in the top route. Typing in a field, a list that does have
// focus, and screens with their own key handling (the photo viewer's
// left/right) all see the key first and keep their behaviour.

/// How far one arrow press moves. Flutter's own ScrollAction uses 50.
const double kKeyboardScrollLine = 50;

/// Page Up/Down move this fraction of the visible height, like ScrollAction.
const double kKeyboardScrollPageFraction = 0.8;

enum _KeyScroll { lineUp, lineDown, pageUp, pageDown, top, bottom }

_KeyScroll? _keyScrollFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return _KeyScroll.lineUp;
  if (key == LogicalKeyboardKey.arrowDown) return _KeyScroll.lineDown;
  if (key == LogicalKeyboardKey.pageUp) return _KeyScroll.pageUp;
  if (key == LogicalKeyboardKey.pageDown) return _KeyScroll.pageDown;
  if (key == LogicalKeyboardKey.home) return _KeyScroll.top;
  if (key == LogicalKeyboardKey.end) return _KeyScroll.bottom;
  return null;
}

/// Where [position] should go for [action]. Pure, so it is tested directly.
///
/// [reversed] is a list laid out bottom-up (a chat), where a larger offset is
/// further UP the screen — so "down" has to lower the offset there.
double keyboardScrollTarget({
  required double pixels,
  required double min,
  required double max,
  required double viewport,
  required bool reversed,
  required LogicalKeyboardKey key,
}) {
  final action = _keyScrollFor(key);
  if (action == null) return pixels;
  final page = viewport * kKeyboardScrollPageFraction;
  // Delta toward the visual bottom of the screen.
  double down;
  switch (action) {
    case _KeyScroll.lineUp:
      down = -kKeyboardScrollLine;
    case _KeyScroll.lineDown:
      down = kKeyboardScrollLine;
    case _KeyScroll.pageUp:
      down = -page;
    case _KeyScroll.pageDown:
      down = page;
    case _KeyScroll.top:
      return reversed ? max : min;
    case _KeyScroll.bottom:
      return reversed ? min : max;
  }
  final target = pixels + (reversed ? -down : down);
  return target.clamp(min, max).toDouble();
}

class KeyboardScroll extends StatelessWidget {
  final Widget child;
  const KeyboardScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Only ever reached by bubbling; it must never take focus itself or it
      // would steal it from whatever the user last clicked.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _handle(context, event),
      child: child,
    );
  }

  static KeyEventResult _handle(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_keyScrollFor(event.logicalKey) == null) return KeyEventResult.ignored;
    // Ctrl/Alt/Cmd/Shift + arrow belong to the browser and to text selection.
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed ||
        kb.isAltPressed ||
        kb.isMetaPressed ||
        kb.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null) {
      // A text field moves its caret with these keys.
      if (focused.widget is EditableText ||
          focused.findAncestorStateOfType<EditableTextState>() != null) {
        return KeyEventResult.ignored;
      }
      // Something inside a vertical list has focus: Flutter's own ScrollAction
      // already knows which list that is, so leave it alone. (A focused
      // horizontal carousel cannot use up/down, so the page still scrolls.)
      if (Scrollable.maybeOf(focused, axis: Axis.vertical) != null) {
        return KeyEventResult.ignored;
      }
    }

    final target = _pageScrollable(context);
    if (target == null) return KeyEventResult.ignored;
    final pos = target.position;
    final to = keyboardScrollTarget(
      pixels: pos.pixels,
      min: pos.minScrollExtent,
      max: pos.maxScrollExtent,
      viewport: pos.viewportDimension,
      reversed: target.axisDirection == AxisDirection.up,
      key: event.logicalKey,
    );
    if (to == pos.pixels) return KeyEventResult.handled;
    if (event is KeyRepeatEvent) {
      // Held key: an animation per repeat would queue up and lag behind.
      pos.jumpTo(to);
    } else {
      pos.animateTo(
        to,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
      );
    }
    return KeyEventResult.handled;
  }

  /// The list the user is looking at: the biggest on-screen vertical
  /// scrollable, in the top route, that actually has something to scroll.
  static ScrollableState? _pageScrollable(BuildContext root) {
    ScrollableState? best;
    double bestArea = 0;

    void visit(Element el) {
      final w = el.widget;
      // Hidden tabs of an IndexedStack (Visibility(visible: false), still laid
      // out at full size) and routes covered by another page (ticker-disabled /
      // offstage) are kept alive; never scroll those.
      if (w is Visibility && !w.visible) return;
      if (w is SliverVisibility && !w.visible) return;
      if (w is TickerMode && !w.enabled) return;
      if (w is Offstage && w.offstage) return;

      if (el is StatefulElement && el.state is ScrollableState) {
        final s = el.state as ScrollableState;
        if (_isCandidate(el, s)) {
          final box = el.findRenderObject();
          if (box is RenderBox && box.hasSize) {
            final area = box.size.width * box.size.height;
            if (area > bestArea) {
              bestArea = area;
              best = s;
            }
          }
        }
      }
      el.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return best;
  }

  static bool _isCandidate(Element el, ScrollableState s) {
    if (axisDirectionToAxis(s.axisDirection) != Axis.vertical) return false;
    // A dialog is not opaque, so the page under it is still "visible" — but
    // the keys belong to the dialog.
    final route = ModalRoute.of(el);
    if (route != null && !route.isCurrent) return false;
    final pos = s.position;
    return pos.hasContentDimensions &&
        pos.hasViewportDimension &&
        pos.maxScrollExtent > pos.minScrollExtent;
  }
}
