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

  // Typography drifted furthest of the three scales: 27 distinct font sizes
  // across the app, including pairs a reader cannot tell apart (11 vs 11.5,
  // 17 vs 18, 12 vs 12.5). Perceptually identical steps are not a scale, they
  // are just noise, and noise is what makes type feel unconsidered.
  //
  // Unlike radii and spacing, there is no safe mechanical substitution here: a
  // bare TextStyle(fontSize: 12) is not swappable for AppType.label, because
  // the token also carries weight, colour and line-height. So this pins the
  // SIZES rather than requiring the tokens, and the per-site work of choosing
  // the right AppType style stays a screen-by-screen job.
  test('the app uses one type scale, with no perceptually duplicate steps', () {
    // Not const: Dart forbids doubles in a constant set.
    final allowed = <double>{9, 10, 11, 12, 13, 14, 15.5, 17, 20, 24, 28,
      34, 40};
    final re = RegExp(r'fontSize:\s*([\d.]+)');
    final offenders = <String>[];
    final seen = <double>{};
    for (final f in _uiSources(includeDesignSystem: true)) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in re.allMatches(lines[i])) {
          final v = double.parse(m.group(1)!);
          seen.add(v);
          if (!allowed.contains(v)) {
            offenders.add('${f.uri.pathSegments.last}:${i + 1} → ${v}px');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Off-scale font size. Snap to the nearest step, or add a step to '
          '`allowed` deliberately if the scale genuinely needs one:\n'
          '${offenders.join('\n')}',
    );
    expect(
      seen.length,
      lessThanOrEqualTo(allowed.length),
      reason: 'the scale should shrink or hold, never grow',
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

  // Every uniform inset that is genuinely CONTAINER PADDING — the spacing
  // rhythm a reader perceives — now uses AppSpacing. Thirteen literals remain
  // on purpose, because forcing them onto a 4-multiple scale would be applying
  // the wrong ruler:
  //
  //  * 3, 5, 6, 7 (9 sites) — insets between a glyph and the circle or square
  //    drawn around it: the verified-seller badge, the favourite button, the
  //    fullscreen control, a spinner. These size a control optically; they are
  //    not spacing between things, and snapping them changes hit targets to no
  //    design benefit.
  //  * 24, 32, 40 (4 sites) — whitespace around a centred spinner or error
  //    message on an otherwise empty screen. Nothing sits near them to be
  //    rhythmic with.
  //
  // The ceiling may only shrink. If a new raw inset is genuinely one of the two
  // cases above, lower the count deliberately rather than raising it.
  test('container padding is fully tokenised, and drift cannot grow', () {
    final re = RegExp(r'EdgeInsets\.all\(\s*(\d+)');
    final found = <String>[];
    for (final f in _uiSources(includeDesignSystem: true)) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final m = re.firstMatch(lines[i]);
        if (m != null) {
          found.add('${f.uri.pathSegments.last}:${i + 1} → ${m.group(1)}px');
        }
      }
    }
    expect(
      found.length,
      lessThanOrEqualTo(13),
      reason:
          'New code should use AppSpacing. ${found.length} raw insets found, '
          'ceiling is 13:\n${found.join('\n')}',
    );

    // The rhythm values are the ones that must never come back: each sits one
    // step off the scale, which is exactly how a layout drifts by 2px at a
    // time until nothing lines up.
    final rhythm = found.where((s) {
      final px = int.parse(s.split('→ ').last.replaceAll('px', ''));
      return px == 10 || px == 14 || px == 18;
    });
    expect(
      rhythm,
      isEmpty,
      reason: 'these are container padding — use AppSpacing:\n$rhythm',
    );
  });
}
