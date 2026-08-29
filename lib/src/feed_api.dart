part of '../main.dart';

// Reading the browse feed from the edge instead of from Firestore.
//
// The home screen used to hold a live Firestore listener on the newest sixty
// approved listings. That listener is a CONNECTION, and Firestore allows one
// million concurrent connections per database — so a million people browsing is
// not a bill to optimise, it is a wall. And the sixty documents behind it are
// identical for every one of those people: a million connections delivering one
// answer.
//
// So the answer is computed once, on the server, and served from Firebase
// Hosting's CDN. Browsing costs no Firestore connection, no Firestore reads,
// and is served from an edge near the phone rather than from us-central1.
//
// This is deliberately NOT how the rest of the app reads data. Your orders,
// your chats, your ads are yours, they are different for everybody, and they
// stay on live Firestore listeners where being instant matters. Only the parts
// that are the same for everyone belong on a cache.
//
// See functions/feed.js for what the server will and will not publish.

/// Where the cached feed lives. Served by Firebase Hosting, which is why it is
/// an absolute URL to the site rather than to the function — the function's own
/// URL bypasses the CDN and would give every caller a cold origin read.
const String kFeedEndpoint = 'https://pakbazar24.com/api/feed';

/// A featured business, as its rail draws it.
///
/// Deliberately not a user document: see businessView in functions/feed.js for
/// what the server will and will not publish about an account.
class FeaturedBusiness {
  const FeaturedBusiness({
    required this.id,
    required this.name,
    required this.tagline,
    required this.logoUrl,
    required this.verified,
    required this.until,
  });

  factory FeaturedBusiness.fromMap(Map<String, dynamic> m) => FeaturedBusiness(
    id: m['id']?.toString() ?? '',
    name: m['businessName']?.toString() ?? 'Business',
    tagline: m['tagline']?.toString() ?? '',
    logoUrl: m['logoUrl']?.toString() ?? '',
    verified: m['businessVerified'] == true,
    until: m['featuredBusinessUntil'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (m['featuredBusinessUntil'] as num).toInt(),
          )
        : null,
  );

  final String id;
  final String name;
  final String tagline;
  final String logoUrl;
  final bool verified;

  /// When the placement lapses. The rail hides an expired one.
  final DateTime? until;
}

/// One page of the browse feed, plus the rails that come with its first page.
class FeedPage {
  const FeedPage({
    required this.items,
    required this.next,
    this.deals = const [],
    this.businesses = const [],
  });

  final List<Listing> items;

  /// Cursor for the next page, or null at the end of the feed.
  final int? next;

  /// Recent price drops. Same for everybody, so it travels with the feed
  /// rather than on a listener of its own.
  final List<Listing> deals;

  /// Featured businesses. Likewise.
  final List<FeaturedBusiness> businesses;
}

/// Fetches a page of the browse feed from the CDN.
///
/// Throws on any failure — a caller is expected to fall back to Firestore
/// rather than show an empty marketplace. See [loadFeedPage].
Future<FeedPage> fetchFeedPage({int? before, int limit = 60, bool fresh = false}) async {
  final uri = Uri.parse(kFeedEndpoint).replace(
    queryParameters: {
      'limit': '$limit',
      if (before != null) 'before': '$before',
    },
  );
  final res = await http
      .get(uri, headers: {
        // Pull-to-refresh means "I want to know NOW", so it asks the edge to
        // revalidate rather than serve what it already has.
        if (fresh) 'Cache-Control': 'no-cache',
      })
      .timeout(const Duration(seconds: 12));

  if (res.statusCode != 200) {
    throw Exception('feed ${res.statusCode}');
  }
  return parseFeedBody(jsonDecode(utf8.decode(res.bodyBytes)));
}

/// Turns a decoded feed response into listings.
///
/// Separate from the fetch so it can be tested without a network: the parsing
/// is where the failures live, not the HTTP.
FeedPage parseFeedBody(Object? body) {
  if (body is! Map || body['items'] is! List) {
    // The catch-all hosting rewrite serves index.html for anything it does not
    // recognise, so a misconfigured route arrives as HTML rather than as a 404.
    // Without this check that would parse as an empty feed and present as a
    // marketplace with nothing in it — the failure looking exactly like a fact.
    throw const FormatException('feed returned something that is not a feed');
  }
  final items = <Listing>[];
  for (final raw in (body['items'] as List)) {
    if (raw is! Map) continue;
    final map = raw.cast<String, dynamic>();
    final id = map['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    // One malformed listing must not blank the feed for everybody.
    try {
      items.add(Listing.fromMap(id, map));
    } catch (_) {}
  }
  final rails = body['rails'];
  final deals = <Listing>[];
  final businesses = <FeaturedBusiness>[];
  if (rails is Map) {
    for (final raw in (rails['deals'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      try {
        deals.add(Listing.fromMap(id, map));
      } catch (_) {}
    }
    for (final raw in (rails['businesses'] as List? ?? const [])) {
      if (raw is! Map) continue;
      try {
        final b = FeaturedBusiness.fromMap(raw.cast<String, dynamic>());
        if (b.id.isNotEmpty) businesses.add(b);
      } catch (_) {}
    }
  }

  final next = body['next'];
  return FeedPage(
    items: items,
    next: next is num ? next.toInt() : null,
    deals: deals,
    businesses: businesses,
  );
}

/// The browse feed, from the CDN, falling back to Firestore.
///
/// The fallback is the point. A cache in front of a database is a second thing
/// that can be broken — a bad deploy, an expired rewrite, a region having a bad
/// day — and "the marketplace is empty" is the worst possible way for that to
/// present. If the edge cannot answer, this reads Firestore directly, exactly
/// as the app did before, and the user sees a feed either way.
Future<FeedPage> loadFeedPage({
  int? before,
  int limit = 60,
  bool fresh = false,
}) async {
  try {
    final page = await fetchFeedPage(before: before, limit: limit, fresh: fresh);
    // An empty first page is treated as a failure rather than as an empty
    // marketplace: this app always has listings, so nothing coming back means
    // something is wrong upstream, and Firestore is the second opinion.
    if (page.items.isNotEmpty || before != null) return page;
  } catch (err, stack) {
    // Recorded rather than swallowed: the fallback means nobody SEES this
    // happen, so without a report a broken cache layer could sit there quietly
    // costing every user a slow first load and costing us the reads it was
    // built to avoid.
    recordHandledError(
      err,
      stack,
      context: 'feed endpoint failed, fell back to Firestore',
    );
  }

  Query<Map<String, dynamic>> q = FirebaseFirestore.instance
      .collection('listings')
      .where('approvalStatus', isEqualTo: 'approved')
      .orderBy('createdAt', descending: true);
  if (before != null) {
    q = q.startAfter([Timestamp.fromMillisecondsSinceEpoch(before)]);
  }
  final snap = await q.limit(limit).get();
  // The rails come back empty on this path. They are decoration on a screen
  // that is already in trouble, and reading them here would mean three more
  // Firestore queries at exactly the moment something is wrong.
  return FeedPage(
    items: snap.docs.map(Listing.fromDoc).toList(),
    next: null,
  );
}
