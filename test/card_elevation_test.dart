import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// The listing card gets its separation from the page by opposite means in the
// two themes: a soft shadow in light, a hairline in dark. Both at once reads as
// a heavy outlined box; neither at all makes a grid of cards dissolve into the
// background. Exactly one must be doing the work, and that is easy to undo by
// accident later, so it is pinned here.

void main() {
  final original = appBrightnessValue;
  tearDown(() => appBrightnessValue = original);

  group('AppShadow', () {
    test('light mode lifts the card with a shadow and drops the border', () {
      appBrightnessValue = Brightness.light;
      expect(AppShadow.card, isNotEmpty);
      expect(
        AppShadow.cardBorder,
        isNull,
        reason: 'a hairline under the shadow reads as a heavy outlined box',
      );
    });

    // A shadow cast on a near-black ground is invisible, so dark mode must not
    // silently lose its separation when the shadow stops being visible.
    test('dark mode keeps the hairline and spends nothing on a shadow', () {
      appBrightnessValue = Brightness.dark;
      expect(AppShadow.card, isEmpty);
      expect(AppShadow.cardBorder, isNotNull);
    });

    test('exactly one mechanism is active in either theme', () {
      for (final b in [Brightness.light, Brightness.dark]) {
        appBrightnessValue = b;
        final hasShadow = AppShadow.card.isNotEmpty;
        final hasBorder = AppShadow.cardBorder != null;
        expect(
          hasShadow ^ hasBorder,
          isTrue,
          reason: 'in $b the card has shadow=$hasShadow border=$hasBorder',
        );
      }
    });

    // The shade sits in the app's own colour world rather than being pure
    // black, and stays soft — a dark or tight shadow is the difference between
    // "premium" and "sticker".
    test('the light shadow is soft and ink-tinted, not black', () {
      appBrightnessValue = Brightness.light;
      for (final s in AppShadow.card) {
        expect(s.color.a, lessThan(0.12), reason: 'shadow must stay subtle');
        expect(
          s.color.b,
          greaterThan(s.color.r),
          reason: 'tinted toward the app ink navy, not neutral black',
        );
      }
    });
  });

  group('the card still cannot overflow with elevation applied', () {
    // The shadow paints outside the box and removing the border returns 2px of
    // content space, so the deterministic-height guarantee should be intact.
    // This re-checks it at the tightest combination the app supports.
    testWidgets('renders in a grid at 320px and 1.3x text', (tester) async {
      appBrightnessValue = Brightness.light;
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: LayoutBuilder(
                builder: (context, c) => GridView.builder(
                  gridDelegate: MarketplaceListingCard.gridDelegate(
                    context,
                    availableWidth: c.maxWidth,
                    columns: MarketplaceListingCard.columnsFor(c.maxWidth),
                  ),
                  itemCount: 4,
                  itemBuilder: (_, _) => MarketplaceListingCard(
                    listing: Listing(
                      id: 'l1',
                      title:
                          'Toyota Corolla Altis Grande X 1.8 CVT-i Black '
                          'Interior 2022 Single Owner Non-Accidental',
                      price: '12500000',
                      location: 'Satellite Town Block C, Rawalpindi Cantt',
                      imageUrl: '',
                      category: 'Motors',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
