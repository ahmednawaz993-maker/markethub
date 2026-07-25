// Layout regression tests for the marketplace design system.
//
// These pump the reusable components at real Android screen widths, with
// deliberately pathological content (very long titles, prices, locations and
// category names) and at a large text scale. Any RenderFlex overflow, clipped
// title or unbounded-constraint error surfaces as a test failure, which is the
// only cheap way to guarantee the "no overflow anywhere" rule keeps holding.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

/// A listing whose every text field is far longer than the space available.
Listing _longListing() => Listing(
  id: 'l1',
  title:
      'Toyota Corolla Altis Grande X 1.8 CVT-i Black Interior 2022 Model '
      'Single Owner Total Genuine Non-Accidental Army Officer Driven',
  price: '12500000',
  location: 'Near Chandni Chowk Roundabout, Satellite Town, Block C Extension',
  imageUrl: '',
  category: 'Motors',
  subcategory: 'Cars',
  city: 'Rawalpindi Cantonment Board Area',
  unit: 'kilogram',
  condition: 'Used',
  sellerName: 'Al-Madina Motors & General Traders (Pvt) Limited',
  sellerVerified: true,
  deliveryAvailable: true,
  negotiable: true,
  previousPrice: '13900000',
  priceDropAt: Timestamp.now(),
  createdAt: Timestamp.now(),
  images: const [
    'https://example.invalid/a.png',
    'https://example.invalid/b.png',
  ],
  attributes: const {'Color': 'Black', 'Year': '2022'},
);

/// Pumps [child] inside the real app theme at a given size and text scale.
Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

/// Android phone/tablet widths worth covering: small, common, large, tablet.
const _sizes = <Size>[
  Size(320, 640), // very small phone
  Size(360, 780), // most common Android phone
  Size(411, 891), // large phone
  Size(768, 1024), // tablet
];

void main() {
  group('MarketplaceListingCard', () {
    for (final size in _sizes) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'no overflow in a grid at ${size.width.toInt()}px, text x$scale',
          (tester) async {
            final listing = _longListing();
            await _pumpAt(
              tester,
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = MarketplaceListingCard.columnsFor(
                    constraints.maxWidth,
                  );
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.page,
                    ),
                    gridDelegate: MarketplaceListingCard.gridDelegate(
                      context,
                      availableWidth:
                          constraints.maxWidth - AppSpacing.page * 2,
                      columns: columns,
                    ),
                    itemCount: 6,
                    itemBuilder: (_, _) =>
                        MarketplaceListingCard(listing: listing),
                  );
                },
              ),
              size: size,
              textScale: scale,
            );

            expect(tester.takeException(), isNull);
            // The title must be capped at two lines and ellipsised, never
            // wrapped down into a column of letters.
            final title = tester
                .widgetList<Text>(find.byType(Text))
                .firstWhere((t) => (t.data ?? '').startsWith('Toyota Corolla'));
            expect(title.maxLines, 2);
            expect(title.overflow, TextOverflow.ellipsis);
          },
        );
      }
    }
  });

  group('MarketplaceListingTile', () {
    for (final size in _sizes) {
      testWidgets('no overflow at ${size.width.toInt()}px', (tester) async {
        await _pumpAt(
          tester,
          ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              MarketplaceListingTile(
                listing: _longListing(),
                details: const [
                  MetaChip(icon: Icons.remove_red_eye_outlined, label: '12345'),
                  MetaChip(icon: Icons.call_outlined, label: '999'),
                  MetaChip(icon: Icons.chat_bubble_outline, label: '4321'),
                ],
                trailing: const Icon(Icons.more_vert),
              ),
            ],
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Home components', () {
    for (final size in _sizes) {
      testWidgets('search bar + section header + rails at '
          '${size.width.toInt()}px', (tester) async {
        await _pumpAt(
          tester,
          ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: AppSearchBar(
                  hintText: 'Search in PakBazar',
                  locationLabel: 'Rawalpindi Cantonment Board Area',
                  onLocationTap: () {},
                ),
              ),
              const SectionHeader(
                title:
                    'Popular in Business & Industrial Equipment and Machinery',
                subtitle: 'Most viewed across every city in Pakistan this week',
              ),
              HorizontalListingSection(
                title: 'Recommended for you',
                listings: List.generate(4, (_) => _longListing()),
              ),
              Builder(
                builder: (context) => SizedBox(
                  height: FeaturedBannerCard.heightFor(context, 268),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const [
                      FeaturedBannerCard(
                        title: 'Sell your property fast across all of Pakistan',
                        subtitle:
                            'Reach thousands of verified buyers and tenants in '
                            'every major city, town and village',
                        imageUrl: '',
                        badge: 'Properties & Real Estate',
                      ),
                    ],
                  ),
                ),
              ),
              const RecentSearchCard(
                query: 'honda civic reborn 2013 automatic islamabad registered',
                category: 'Motors',
                location: 'Islamabad Capital Territory',
              ),
            ],
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('AppBottomNavigation', () {
    /// The live configuration: Home · Chats · [SELL] · My Ads · Menu.
    const production = <AppNavDestination>[
      AppNavDestination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
      ),
      AppNavDestination(
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: 'Chats',
      ),
      AppNavDestination(
        icon: Icons.list_alt_outlined,
        activeIcon: Icons.list_alt,
        label: 'My Ads',
      ),
      AppNavDestination(
        icon: Icons.menu,
        activeIcon: Icons.menu_open,
        label: 'Menu',
      ),
    ];

    /// Worst case: the longest labels any translation is likely to produce.
    const longLabels = <AppNavDestination>[
      AppNavDestination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home page',
      ),
      AppNavDestination(
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: 'Messages',
      ),
      AppNavDestination(
        icon: Icons.list_alt_outlined,
        activeIcon: Icons.list_alt,
        label: 'My listings',
      ),
      AppNavDestination(
        icon: Icons.menu,
        activeIcon: Icons.menu_open,
        label: 'More options',
      ),
    ];

    for (final size in _sizes) {
      for (final scale in [1.0, 1.3]) {
        for (final entry in {
          'production': production,
          'long labels': longLabels,
        }.entries) {
          testWidgets('fits 4 tabs + Sell at ${size.width.toInt()}px, '
              'text x$scale, ${entry.key}', (tester) async {
            await _pumpAt(
              tester,
              Align(
                alignment: Alignment.bottomCenter,
                child: AppBottomNavigation(
                  currentIndex: 0,
                  onTap: (_) {},
                  onSell: () {},
                  destinations: entry.value,
                ),
              ),
              size: size,
              textScale: scale,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('AppCard', () {
    // Regression: AppCard used to paint its background with a DecoratedBox,
    // which sits ABOVE the nearest Material. Any ListTile/InkWell inside it
    // then drew its ink where nothing could see it, and Flutter asserted
    // "ListTile background color or ink splashes may be invisible" — every
    // row of the Menu tab. The card must supply the Material itself.
    testWidgets('hosts a ListTile without hiding its ink', (tester) async {
      await _pumpAt(
        tester,
        ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.list_alt),
                    title: const Text('My Ads'),
                    subtitle: const Text('Edit, promote, mark sold'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {},
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: const Text('My Orders'),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
        size: const Size(360, 780),
      );
      expect(tester.takeException(), isNull);

      // Tapping must produce ink on a Material the card owns.
      await tester.tap(find.text('My Ads'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('Empty and error states', () {
    testWidgets('render without overflow on a small phone', (tester) async {
      await _pumpAt(
        tester,
        const EmptyStateWidget(
          icon: Icons.search_off,
          title: 'No listings found',
          subtitle: 'Try a different search or adjust your filters.',
          actionLabel: 'Clear all filters and start again',
        ),
        size: const Size(320, 480),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);

      await _pumpAt(
        tester,
        const ErrorStateWidget(message: 'We could not load listings.'),
        size: const Size(320, 480),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
