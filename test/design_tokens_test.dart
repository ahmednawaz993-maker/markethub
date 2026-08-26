import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Design-system drift is invisible in review — one `BorderRadius.circular(10)`
// looks harmless in a diff, and it is only after a hundred of them that the app
// starts feeling inconsistent without anyone being able to point at why.
//
// This scans the source rather than the widget tree, because the failure it
// guards is "a value that never went through the scale", which no rendered
// output can show you.

/// Every source file that composes UI. design_system.dart is excluded from the
/// literal checks because it is where the scale is *defined*.
List<File> _uiSources({bool includeDesignSystem = false}) {
  final dir = Directory('lib/src');
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where(
        (f) =>
            includeDesignSystem ||
            !f.path.replaceAll(r'\', '/').endsWith('design_system.dart'),
      )
      .toList();
}

void main() {
  test('lib/src is where the UI lives', () {
    // Guards the guard: if the layout moves, the checks below would silently
    // pass by scanning nothing.
    expect(_uiSources().length, greaterThan(20));
  });

  test('no raw corner radius outside the design system', () {
    final offenders = <String>[];
    final re = RegExp(r'BorderRadius\.circular\(\s*\d');
    for (final f in _uiSources()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (re.hasMatch(lines[i])) {
          offenders.add('${f.uri.pathSegments.last}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use an AppRadius token (xs 4 / sm 8 / md 12 / card 14 / lg 16 / '
          'xl 20 / pill). If none fits, add a step to the scale rather than a '
          'one-off literal:\n${offenders.join('\n')}',
    );
  });

  group('the radius scale', () {
    // The steps are load-bearing: several screens were snapped onto them, so
    // changing a value here silently restyles the app.
    test('holds its published steps', () {
      expect(AppRadius.xs, 4);
      expect(AppRadius.sm, 8);
      expect(AppRadius.md, 12);
      expect(AppRadius.card, 14);
      expect(AppRadius.lg, 16);
      expect(AppRadius.xl, 20);
    });

    test('ascends without gaps big enough to invite a one-off', () {
      const steps = [
        AppRadius.xs,
        AppRadius.sm,
        AppRadius.md,
        AppRadius.card,
        AppRadius.lg,
        AppRadius.xl,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]));
        expect(
          steps[i] - steps[i - 1],
          lessThanOrEqualTo(4),
          reason:
              'a gap wider than 4 is what makes someone reach for a literal '
              'instead of the nearest step',
        );
      }
    });
  });

  // Spacing is deliberately NOT asserted clean yet: 43 uniform insets are still
  // off-scale, and unlike a radius, changing one moves layout and can overflow.
  // They need a screen-by-screen pass. This pins the number so the count can
  // only go down.
  test('uniform-inset drift does not grow', () {
    final re = RegExp(r'EdgeInsets\.all\(\s*\d');
    var count = 0;
    for (final f in _uiSources()) {
      for (final l in f.readAsLinesSync()) {
        if (re.hasMatch(l)) count++;
      }
    }
    expect(
      count,
      lessThanOrEqualTo(43),
      reason:
          'New code should use AppSpacing. $count raw EdgeInsets.all remain; '
          'the agreed ceiling is 43 and it may only shrink.',
    );
  });
}
