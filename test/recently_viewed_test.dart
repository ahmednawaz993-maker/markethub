// Continue Browsing, stored on the device.
//
// The rail lists ads THIS user opened on THIS phone moments ago, so the phone
// already has every one of them. Reading them back from Firestore cost ten
// document reads on every launch and every resume — asking a database what the
// app itself had just done.
//
// The Firestore copy is still written: it is what carries the rail to another
// device, and what seeds a fresh install. It is simply no longer what the rail
// is drawn from.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Listing _ad(String id, {String title = 'Ad'}) => Listing(
  id: id,
  title: title,
  price: '1000',
  location: 'Rawalpindi',
  imageUrl: 'https://example.com/$id.jpg',
  images: const [],
  category: 'Vehicles',
  subcategory: 'Cars',
  phone: '',
  description: '',
  userId: 'seller-1',
  sellerName: 'Ahmed',
  condition: 'Used',
  unit: '',
  deliveryFee: '',
  deliveryAvailable: false,
  codAvailable: false,
  sellerVerified: false,
  negotiable: false,
  attributes: const {},
  city: 'Rawalpindi',
  latitude: null,
  longitude: null,
  views: 0,
  calls: 0,
  whatsapps: 0,
  chats: 0,
  isFeatured: false,
  isSold: false,
  status: 'in_stock',
  featuredUntil: null,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(1700000000000),
  previousPrice: '',
  priceDropAt: null,
  approvalStatus: 'approved',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an ad you opened is remembered, with what the card needs', () async {
    await cacheRecentlyViewed(_ad('a1', title: 'Toyota Corolla'));
    final back = await loadCachedRecentlyViewed();
    expect(back, hasLength(1));
    expect(back.single.id, 'a1');
    expect(back.single.title, 'Toyota Corolla');
    // Round-tripped through JSON, so the timestamp has to survive as well.
    expect(back.single.createdAt?.millisecondsSinceEpoch, 1700000000000);
  });

  test('the newest is first, which is what "continue" means', () async {
    await cacheRecentlyViewed(_ad('a1'));
    await cacheRecentlyViewed(_ad('a2'));
    await cacheRecentlyViewed(_ad('a3'));
    expect((await loadCachedRecentlyViewed()).map((l) => l.id), [
      'a3',
      'a2',
      'a1',
    ]);
  });

  test('re-opening an ad moves it up rather than listing it twice', () async {
    await cacheRecentlyViewed(_ad('a1'));
    await cacheRecentlyViewed(_ad('a2'));
    await cacheRecentlyViewed(_ad('a1'));
    final ids = (await loadCachedRecentlyViewed()).map((l) => l.id).toList();
    expect(ids, ['a1', 'a2']);
  });

  test('the list does not grow forever', () async {
    for (var i = 0; i < 40; i++) {
      await cacheRecentlyViewed(_ad('a$i'));
    }
    final back = await loadCachedRecentlyViewed();
    expect(back, hasLength(kRecentlyViewedCap));
    expect(back.first.id, 'a39');
  });

  test('signing out forgets it', () async {
    // A shared phone must not show one person's browsing to the next.
    await cacheRecentlyViewed(_ad('a1'));
    await clearCachedRecentlyViewed();
    expect(await loadCachedRecentlyViewed(), isEmpty);
  });

  test('a fresh install can be seeded from Firestore', () async {
    // The one time the ten reads are still paid: a device that has never
    // shown this rail before.
    await seedCachedRecentlyViewed([_ad('a1'), _ad('a2')]);
    expect((await loadCachedRecentlyViewed()).map((l) => l.id), ['a1', 'a2']);
  });

  test('a corrupt entry is skipped, not fatal', () async {
    SharedPreferences.setMockInitialValues({
      'recently_viewed_v1': ['not json at all', '{"id":"a1","title":"Fine"}'],
    });
    final back = await loadCachedRecentlyViewed();
    expect(back.map((l) => l.id), ['a1']);
  });

  test('an ad with no id is not stored', () async {
    // It could never be opened again, and it would occupy a slot.
    await cacheRecentlyViewed(_ad(''));
    expect(await loadCachedRecentlyViewed(), isEmpty);
  });
}
