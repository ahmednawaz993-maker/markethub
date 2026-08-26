import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Renders the surfaces touched by the token work to actual pixels, so the
// elevation, radii and spacing changes can be LOOKED at rather than inferred
// from a passing overflow test. Run with `--update-goldens` to regenerate.
//
// Text renders in the test font, so these verify geometry — card separation,
// corner softness, the rhythm of the info block — not letterforms.
//
// TWO THINGS THAT WILL WASTE YOUR TIME IF YOU DON'T KNOW THEM:
//
//  * `tester.view.physicalSize` is in PHYSICAL pixels. Setting it to 320x300
//    with devicePixelRatio 2.0 gives a 160x150 LOGICAL screen, which is far too
//    small for these components and produces overflow errors that look exactly
//    like a product bug. Keep the ratio at 1.0 here so the two are the same.
//  * Goldens are platform-specific — antialiasing and font fallback differ
//    between Windows, macOS and Linux. No CI runs `flutter test` today, so
//    these are committed as-is; if that changes, regenerate them on the machine
//    that will run them, or the comparison will fail for reasons unrelated to
//    the design.

Listing _listing({bool featured = false}) => Listing(
  id: 'l1',
  title: 'Toyota Corolla Altis Grande X 1.8 CVT-i 2022 Single Owner',
  price: '12500000',
  location: 'Satellite Town, Rawalpindi',
  imageUrl: '',
  category: 'Motors',
  subcategory: 'Cars',
  city: 'Rawalpindi',
  condition: 'Used',
  sellerName: 'Al-Madina Motors',
  sellerVerified: true,
  isFeatured: featured,
  createdAt: Timestamp.now(),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required Size size,
  Brightness brightness = Brightness.light,
}) async {
  appBrightnessValue = brightness;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: AppColors.background, body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final original = appBrightnessValue;
  tearDown(() => appBrightnessValue = original);

  testWidgets('listing grid — light (shadow, no border)', (tester) async {
    await _pump(
      tester,
      Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: LayoutBuilder(
          builder: (context, c) => GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: MarketplaceListingCard.gridDelegate(
              context,
              availableWidth: c.maxWidth,
              columns: 2,
            ),
            itemCount: 4,
            itemBuilder: (_, i) =>
                MarketplaceListingCard(listing: _listing(featured: i == 0)),
          ),
        ),
      ),
      size: const Size(380, 620),
    );
    await expectLater(
      find.byType(GridView),
      matchesGoldenFile('goldens/listing_grid_light.png'),
    );
  });

  testWidgets('listing grid — dark (hairline, no shadow)', (tester) async {
    await _pump(
      tester,
      Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: LayoutBuilder(
          builder: (context, c) => GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: MarketplaceListingCard.gridDelegate(
              context,
              availableWidth: c.maxWidth,
              columns: 2,
            ),
            itemCount: 4,
            itemBuilder: (_, i) => MarketplaceListingCard(listing: _listing()),
          ),
        ),
      ),
      size: const Size(380, 620),
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(GridView),
      matchesGoldenFile('goldens/listing_grid_dark.png'),
    );
  });

  testWidgets('featured banner — height matches its text', (tester) async {
    await _pump(
      tester,
      Center(
        child: Builder(
          builder: (context) => SizedBox(
            height: FeaturedBannerCard.heightFor(context, 268),
            width: 268,
            child: const FeaturedBannerCard(
              title: 'Sell your property fast across all of Pakistan',
              subtitle:
                  'Reach thousands of verified buyers and tenants in every '
                  'major city, town and village',
              imageUrl: '',
              badge: 'Properties',
            ),
          ),
        ),
      ),
      size: const Size(320, 300),
    );
    await expectLater(
      find.byType(FeaturedBannerCard),
      matchesGoldenFile('goldens/featured_banner.png'),
    );
  });
}
