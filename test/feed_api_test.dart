// The browse feed, as it arrives from the CDN.
//
// The home screen no longer holds a live Firestore listener; it reads a cached
// JSON feed served from the edge. That removes a connection per browsing user —
// and it introduces a second way for a listing to be built, which is exactly
// where a quiet inconsistency would live. So there is ONE parser
// (Listing.fromMap) and both paths go through it, and these tests pin the
// shapes the server actually sends.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

/// A card exactly as functions/feed.js serialises it.
Map<String, dynamic> _card({String id = 'l1', Map<String, dynamic>? extra}) => {
  'id': id,
  'title': 'Toyota Corolla 2022',
  'price': '12500000',
  'city': 'Rawalpindi',
  'category': 'Vehicles',
  'subcategory': 'Cars',
  'condition': 'Used',
  'unit': '',
  'description': 'Single owner',
  'sellerName': 'Ahmed',
  'userId': 'uid-123',
  'imageUrl': 'https://example.com/a.jpg',
  'images': ['https://example.com/a.jpg'],
  'deliveryFee': '500',
  'deliveryAvailable': true,
  'codAvailable': true,
  'sellerVerified': true,
  'negotiable': true,
  'isFeatured': false,
  'isSold': false,
  'status': 'in_stock',
  'approvalStatus': 'approved',
  'views': 42,
  'previousPrice': '',
  'createdAt': 1786330446375,
  'priceDropAt': null,
  'featuredUntil': null,
  ...?extra,
};

void main() {
  group('a card from the feed', () {
    test('carries everything the grid needs to draw one', () {
      final page = parseFeedBody({
        'items': [_card()],
        'next': 1786330446375,
      });
      expect(page.items, hasLength(1));
      final l = page.items.single;
      expect(l.id, 'l1');
      expect(l.title, 'Toyota Corolla 2022');
      expect(l.price, '12500000');
      expect(l.city, 'Rawalpindi');
      expect(l.imageUrl, 'https://example.com/a.jpg');
      expect(l.sellerName, 'Ahmed');
      expect(l.sellerVerified, isTrue);
      expect(l.views, 42);
      // Without userId the app cannot hide sellers you have blocked, and a
      // blocked seller's ads would reappear in the feed.
      expect(l.userId, 'uid-123');
    });

    test('is visible in the feed, which is the whole point', () {
      // isApproved and isPubliclyVisible are what the home screen filters on.
      // A projection that dropped `approvalStatus` would parse perfectly and
      // then show an empty marketplace.
      final l = parseFeedBody({'items': [_card()], 'next': null}).items.single;
      expect(l.isApproved, isTrue);
      expect(l.isPubliclyVisible, isTrue);
    });

    test('milliseconds become a Timestamp, so sorting by date works', () {
      final l = parseFeedBody({'items': [_card()], 'next': null}).items.single;
      expect(l.createdAt, isA<Timestamp>());
      expect(l.createdAt!.millisecondsSinceEpoch, 1786330446375);
    });

    test('a Firestore Timestamp still parses, so the fallback path agrees', () {
      // loadFeedPage falls back to reading Firestore directly, and that path
      // hands the same parser real Timestamps. Both must work or the fallback
      // would crash precisely when it is needed.
      final l = Listing.fromMap('l1', {
        ..._card(),
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1786330446375),
      });
      expect(l.createdAt!.millisecondsSinceEpoch, 1786330446375);
    });

    test('a sold listing is still marked sold', () {
      final l = parseFeedBody({
        'items': [_card(extra: {'status': 'sold', 'isSold': true})],
        'next': null,
      }).items.single;
      expect(l.isSold, isTrue);
    });
  });

  group('when the feed is not a feed', () {
    test('HTML is rejected rather than read as an empty marketplace', () {
      // The catch-all hosting rewrite serves index.html for anything it does
      // not recognise, so a broken route arrives as a 200 full of HTML. Parsed
      // leniently that is an empty feed — a failure that looks like a fact,
      // and the user is told the marketplace has nothing in it.
      expect(() => parseFeedBody('<!doctype html><html>...'), throwsFormatException);
      expect(() => parseFeedBody({'error': 'unavailable'}), throwsFormatException);
      expect(() => parseFeedBody(null), throwsFormatException);
    });

    test('one broken listing does not take the others with it', () {
      final page = parseFeedBody({
        'items': [
          _card(id: 'good1'),
          'this is not an object',
          {'id': ''}, // no id, so nothing to open
          _card(id: 'good2'),
        ],
        'next': null,
      });
      expect(page.items.map((l) => l.id), ['good1', 'good2']);
    });

    test('a missing cursor means the end of the feed', () {
      expect(parseFeedBody({'items': [], 'next': null}).next, isNull);
      expect(parseFeedBody({'items': [], 'next': 'nonsense'}).next, isNull);
      expect(parseFeedBody({'items': [], 'next': 12345}).next, 12345);
    });
  });

  test('the feed is read through the CDN, not from the function', () {
    // The function's own *.cloudfunctions.net URL bypasses Firebase Hosting,
    // which is where the caching happens — pointing at it would give every
    // caller a cold origin read and quietly undo the entire change.
    expect(kFeedEndpoint, contains('pakbazar24.com'));
    expect(kFeedEndpoint, isNot(contains('cloudfunctions.net')));
  });
}
