part of '../main.dart';

// Core data models and in-memory state.

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
  Timestamp? featuredUntil;
  Timestamp? createdAt;
  String previousPrice; // the price before the most recent reduction (optional)
  Timestamp? priceDropAt; // when the price was last reduced (optional)

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
    this.featuredUntil,
    this.createdAt,
    this.previousPrice = '',
    this.priceDropAt,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

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
      (featuredUntil == null || featuredUntil!.toDate().isAfter(DateTime.now()));

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
      'deliveryAvailable': deliveryAvailable,
      'codAvailable': codAvailable,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'views': views,
      'isFeatured': isFeatured,
      'isSold': isSold,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  factory Listing.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final rawImages = data['images'];
    final imagesList = rawImages is List
        ? rawImages.map((e) => e.toString()).toList()
        : <String>[];

    return Listing(
      id: doc.id,
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
      deliveryAvailable: data['deliveryAvailable'] == true,
      codAvailable: data['codAvailable'] == true,
      sellerVerified: data['sellerVerified'] == true,
      negotiable: data['negotiable'] == true,
      attributes:
          (data['attributes'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const {},
      // 'city' is the current field; fall back to legacy 'emirate' for old ads.
      city: data['city']?.toString() ?? data['emirate']?.toString() ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      views: (data['views'] as num?)?.toInt() ?? 0,
      calls: (data['calls'] as num?)?.toInt() ?? 0,
      whatsapps: (data['whatsapps'] as num?)?.toInt() ?? 0,
      chats: (data['chats'] as num?)?.toInt() ?? 0,
      isFeatured: data['isFeatured'] == true,
      isSold: data['isSold'] == true,
      featuredUntil: data['featuredUntil'] is Timestamp
          ? data['featuredUntil'] as Timestamp
          : null,
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      previousPrice: data['previousPrice']?.toString() ?? '',
      priceDropAt: data['priceDropAt'] is Timestamp
          ? data['priceDropAt'] as Timestamp
          : null,
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
