part of '../main.dart';

// Core data models and in-memory state.

/// The four seller-controlled inventory states.
const Set<String> kValidListingStatuses = {
  'in_stock',
  'out_of_stock',
  'sold',
  'inactive',
};

/// Derives a listing's inventory status: honour a valid explicit [rawStatus],
/// otherwise migrate from the legacy [isSoldLegacy] bool ('sold' when it was
/// sold, else 'in_stock'). Pure and unit-tested — the single migration point.
String listingStatusFrom(String? rawStatus, bool isSoldLegacy) {
  final s = rawStatus ?? '';
  if (kValidListingStatuses.contains(s)) return s;
  return isSoldLegacy ? 'sold' : 'in_stock';
}

class Listing {
  String id;
  String title;
  String price;
  String location;
  String imageUrl;
  List<String> images;
  String category;
  String subcategory;
  String phone;
  String description;
  String userId;
  String sellerName;
  String condition;
  String unit; // pricing unit e.g. 'kg', 'dozen', 'plate' (optional)
  String deliveryFee; // extra delivery charge (String like price; '' = free)
  bool deliveryAvailable;
  bool codAvailable; // Cash on Delivery offered for this ad
  bool sellerVerified;
  bool negotiable;
  Map<String, String> attributes; // e.g. {'Year': '2018', 'KM driven': '50000'}
  String city;
  double? latitude;
  double? longitude;
  int views;
  int calls;
  int whatsapps;
  int chats;
  bool isFeatured;
  bool isSold;
  // Seller-controlled inventory state: 'in_stock' | 'out_of_stock' | 'sold' |
  // 'inactive'. Legacy listings without this field are migrated on read from
  // isSold (see fromDoc). isSold is kept in sync (true iff status=='sold') so
  // the many existing `!isSold` feed filters keep working unchanged.
  String status;
  Timestamp? featuredUntil;
  Timestamp? createdAt;
  String previousPrice; // the price before the most recent reduction (optional)
  Timestamp? priceDropAt; // when the price was last reduced (optional)
  String approvalStatus; // '', 'pending', 'approved', or 'rejected'

  /// Why an admin rejected the ad, in their words. Shown to the seller on My
  /// Ads — before this was stored, a rejected ad carried a red chip and no
  /// explanation, and the reason existed only inside a notification the seller
  /// may never have opened.
  String rejectionReason;

  Listing({
    required this.id,
    required this.title,
    required this.price,
    required this.location,
    required this.imageUrl,
    required this.category,
    this.images = const [],
    this.subcategory = '',
    this.phone = '',
    this.description = '',
    this.userId = '',
    this.sellerName = '',
    this.condition = '',
    this.unit = '',
    this.deliveryFee = '',
    this.deliveryAvailable = false,
    this.codAvailable = false,
    this.sellerVerified = false,
    this.negotiable = false,
    this.attributes = const {},
    this.city = '',
    this.latitude,
    this.longitude,
    this.views = 0,
    this.calls = 0,
    this.whatsapps = 0,
    this.chats = 0,
    this.isFeatured = false,
    this.isSold = false,
    this.status = 'in_stock',
    this.featuredUntil,
    this.createdAt,
    this.previousPrice = '',
    this.priceDropAt,
    this.approvalStatus = '',
    this.rejectionReason = '',
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Whether an ad is cleared for public display. New ads await admin approval
  /// (`approvalStatus == 'pending'`) and rejected ads stay hidden. Ads created
  /// before moderation existed have no status and are treated as approved.
  bool get isApproved =>
      approvalStatus != 'pending' && approvalStatus != 'rejected';

  /// Only an in-stock listing can be purchased. Sold / out-of-stock / inactive
  /// all block checkout (enforced again server-side in placeListingOrder).
  bool get isAvailableForSale => status == 'in_stock';

  /// Whether the listing should appear in public discovery feeds. Inactive
  /// listings are hidden (seller paused them) without being deleted; sold and
  /// out-of-stock still show (with a badge) so buyers see the seller's catalog.
  bool get isPubliclyVisible => status != 'inactive';

  /// Short, buyer-facing label for a non-purchasable status ('' when in stock).
  String get statusLabel => switch (status) {
    'sold' => 'Sold',
    'out_of_stock' => 'Out of stock',
    'inactive' => 'Inactive',
    _ => '',
  };

  /// True if the price was reduced within the last 30 days — drives the
  /// "Price dropped" badge and the struck-through old price on cards.
  bool get hasRecentPriceDrop {
    if (priceDropAt == null || previousPrice.trim().isEmpty) return false;
    if (isSold) return false;
    final dropped = priceDropAt!.toDate();
    return DateTime.now().difference(dropped).inDays < 30;
  }

  /// True only while a paid Featured window is still active. Acts as a client
  /// safety net in case the daily expireFeatured job hasn't run yet.
  bool get isCurrentlyFeatured =>
      isFeatured &&
      (featuredUntil == null ||
          featuredUntil!.toDate().isAfter(DateTime.now()));

  /// All gallery images, falling back to the single [imageUrl] for old ads.
  List<String> get galleryImages {
    if (images.isNotEmpty) return images;
    if (imageUrl.trim().isNotEmpty) return [imageUrl];
    return const [];
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'price': price,
      'location': location,
      'imageUrl': imageUrl,
      'images': images,
      'category': category,
      'subcategory': subcategory,
      'phone': phone,
      'description': description,
      'userId': userId,
      'sellerName': sellerName,
      'condition': condition,
      'unit': unit,
      'deliveryFee': deliveryFee,
      'deliveryAvailable': deliveryAvailable,
      'codAvailable': codAvailable,
      'sellerVerified': sellerVerified,
      'negotiable': negotiable,
      'attributes': attributes,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'views': views,
      'calls': calls,
      'whatsapps': whatsapps,
      'chats': chats,
      'isFeatured': isFeatured,
      'isSold': isSold,
      'status': status,
      'previousPrice': previousPrice,
      'approvalStatus': approvalStatus,
      'rejectionReason': rejectionReason,
      if (featuredUntil != null) 'featuredUntil': featuredUntil,
      if (createdAt != null) 'createdAt': createdAt,
      if (priceDropAt != null) 'priceDropAt': priceDropAt,
    };
  }

  /// A listing from a Firestore document.
  factory Listing.fromDoc(DocumentSnapshot doc) =>
      Listing.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});

  /// A listing from a plain map.
  ///
  /// Exists because the browse feed now arrives as JSON from the CDN rather
  /// than as documents from Firestore, and the two must produce IDENTICAL
  /// objects — a feed card built one way and the same card built the other way
  /// differing in some field is the kind of bug that shows up as "the app is
  /// weird sometimes". So there is one parser and [fromDoc] delegates to it.
  ///
  /// Timestamps therefore have to be accepted in both shapes: a Firestore
  /// [Timestamp] from the database, or milliseconds since epoch from JSON.
  factory Listing.fromMap(String id, Map<String, dynamic> data) {

    // Tolerant numeric read: a single doc with a stringified/odd number field
    // (legacy or hand-edited) must not throw and blank the entire feed.
    num? asNum(Object? v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    // A Firestore Timestamp, or milliseconds from JSON, or nothing.
    Timestamp? asTime(Object? v) {
      if (v is Timestamp) return v;
      final n = asNum(v);
      return n == null ? null : Timestamp.fromMillisecondsSinceEpoch(n.toInt());
    }

    final rawImages = data['images'];
    final imagesList = rawImages is List
        ? rawImages.map((e) => e.toString()).toList()
        : <String>[];

    // Inventory status, migrated on read: honour an explicit valid `status`,
    // else derive from the legacy `isSold` bool (sold -> 'sold', else
    // 'in_stock'). No write needed — existing docs migrate transparently.
    final invStatus = listingStatusFrom(
      data['status']?.toString(),
      data['isSold'] == true,
    );

    return Listing(
      id: id,
      title: data['title']?.toString() ?? '',
      price: data['price']?.toString() ?? '',
      location: data['location']?.toString() ?? '',
      imageUrl: data['imageUrl']?.toString() ?? '',
      images: imagesList,
      category: data['category']?.toString() ?? '',
      subcategory: data['subcategory']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      sellerName: data['sellerName']?.toString() ?? '',
      condition: data['condition']?.toString() ?? '',
      unit: data['unit']?.toString() ?? '',
      deliveryFee: data['deliveryFee']?.toString() ?? '',
      deliveryAvailable: data['deliveryAvailable'] == true,
      codAvailable: data['codAvailable'] == true,
      sellerVerified: data['sellerVerified'] == true,
      negotiable: data['negotiable'] == true,
      attributes: data['attributes'] is Map
          ? (data['attributes'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )
          : const {},
      // 'city' is the current field; fall back to legacy 'emirate' for old ads.
      city: data['city']?.toString() ?? data['emirate']?.toString() ?? '',
      latitude: asNum(data['latitude'])?.toDouble(),
      longitude: asNum(data['longitude'])?.toDouble(),
      views: asNum(data['views'])?.toInt() ?? 0,
      calls: asNum(data['calls'])?.toInt() ?? 0,
      whatsapps: asNum(data['whatsapps'])?.toInt() ?? 0,
      chats: asNum(data['chats'])?.toInt() ?? 0,
      isFeatured: data['isFeatured'] == true,
      // Keep isSold in sync with the migrated status so all existing `!isSold`
      // feed filters keep hiding sold items.
      isSold: invStatus == 'sold',
      status: invStatus,
      featuredUntil: asTime(data['featuredUntil']),
      createdAt: asTime(data['createdAt']),
      previousPrice: data['previousPrice']?.toString() ?? '',
      priceDropAt: asTime(data['priceDropAt']),
      approvalStatus: data['approvalStatus']?.toString() ?? '',
      rejectionReason: data['rejectionReason']?.toString() ?? '',
    );
  }
}

final List<Listing> favoriteListings = [];

/// Users the current user has blocked — their ads/chats are hidden. Loaded at
/// startup (loadBlocked) and kept in sync by blockUser/unblockUser.
final Set<String> blockedUserIds = <String>{};

/// Users an admin has suspended platform-wide (profile `blocked: true`). Their
/// listings are hidden from everyone's feeds/search. Loaded at startup
/// (loadPlatformBlockedUsers); separate from the personal [blockedUserIds].
final Set<String> platformBlockedUserIds = <String>{};

/// True if a listing's seller is hidden for the current viewer — either the
/// viewer personally blocked them, or an admin suspended them platform-wide.
bool isHiddenSeller(String? userId) =>
    blockedUserIds.contains(userId) || platformBlockedUserIds.contains(userId);

/// Phone number captured during email sign-up, handed to ensureUserDoc so it
/// lands on the profile when the user doc is first created (avoids a write race
/// with the doc-creation that happens on the first home load). Cleared after.
String? pendingSignupPhone;
