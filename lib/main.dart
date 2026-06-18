import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MarketHubApp());
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Currency shown across the app (Pakistani Rupee).
const String currencySymbol = 'Rs';

// ---------------------------------------------------------------------------
// Premium Pakistan-flag theme palette
// ---------------------------------------------------------------------------

const Color kPakGreenDeep = Color(0xFF013318); // darkest flag green
const Color kPakGreen = Color(0xFF015127); // primary flag green
const Color kPakGreenLight = Color(0xFF0A7D3B); // lighter accent green
const Color kGold = Color(0xFFC9A227); // premium gold accent

ThemeData buildAppTheme() {
  final base = ThemeData(
    primaryColor: kPakGreen,
    useMaterial3: false,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPakGreen,
      primary: kPakGreen,
      secondary: kGold,
    ),
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPakGreen,
        foregroundColor: Colors.white,
        elevation: 4,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPakGreen,
        side: const BorderSide(color: kPakGreen, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kPakGreen),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPakGreen,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPakGreen, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: kPakGreen,
      secondarySelectedColor: kPakGreen,
      labelStyle: const TextStyle(fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: kPakGreen,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      elevation: 16,
      // Smaller labels so all 5 items fit comfortably on narrow phones.
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 11),
    ),
    dividerColor: Colors.grey.shade300,
  );
}

/// True on phone-width screens (used to tune density/spacing for mobile).
bool isPhone(BuildContext context) => MediaQuery.of(context).size.width < 600;

/// Full-screen flag-green gradient with a faint crescent-and-star motif.
/// Rendered once behind every route via [MaterialApp.builder]; scaffolds are
/// transparent so this shows through on every page.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kPakGreenDeep, kPakGreen, kPakGreenDeep],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Crescent + star watermark (subtle, premium feel).
          Positioned(
            top: 60,
            right: -30,
            child: Opacity(
              opacity: 0.06,
              child: Transform.rotate(
                angle: 0.35,
                child: const Icon(
                  Icons.nightlight_round,
                  size: 280,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 90,
            right: 150,
            child: Opacity(
              opacity: 0.06,
              child: Icon(Icons.star, size: 110, color: Colors.white),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// Comprehensive list of Pakistani cities and towns (big and small), across all
// provinces, ICT, AJK and Gilgit-Baltistan. Kept alphabetical for the picker.
const List<String> pakistanCities = [
  'Abbottabad',
  'Ahmadpur East',
  'Aliabad (Hunza)',
  'Alipur',
  'Arifwala',
  'Astore',
  'Athmuqam',
  'Attock',
  'Awaran',
  'Badin',
  'Bagh',
  'Bahawalnagar',
  'Bahawalpur',
  'Balakot',
  'Bannu',
  'Barkhan',
  'Batkhela',
  'Battagram',
  'Bela',
  'Bhakkar',
  'Bhalwal',
  'Bhimber',
  'Burewala',
  'Chakwal',
  'Chaman',
  'Charsadda',
  'Chichawatni',
  'Chilas',
  'Chiniot',
  'Chishtian',
  'Chitral',
  'Chunian',
  'Dadu',
  'Daharki',
  'Dadyal',
  'Daggar',
  'Dalbandin',
  'Daska',
  'Dera Allah Yar',
  'Dera Bugti',
  'Dera Ghazi Khan',
  'Dera Ismail Khan',
  'Dera Murad Jamali',
  'Digri',
  'Dir',
  'Dunyapur',
  'Faisalabad',
  'Fort Abbas',
  'Gahkuch',
  'Gambat',
  'Ghotki',
  'Gilgit',
  'Gojra',
  'Gujar Khan',
  'Gujranwala',
  'Gujrat',
  'Gwadar',
  'Hafizabad',
  'Hala',
  'Hangu',
  'Haripur',
  'Haroonabad',
  'Hasilpur',
  'Hattian Bala',
  'Hub',
  'Hyderabad',
  'Islamabad',
  'Jacobabad',
  'Jalalpur Jattan',
  'Jampur',
  'Jamshoro',
  'Jaranwala',
  'Jatoi',
  'Jhang',
  'Jhelum',
  'Jiwani',
  'Kabirwala',
  'Kahror Pakka',
  'Kalat',
  'Kamalia',
  'Kamoke',
  'Kandhkot',
  'Karachi',
  'Karak',
  'Kashmore',
  'Kasur',
  'Khairpur',
  'Khanewal',
  'Khanpur',
  'Khaplu',
  'Kharan',
  'Kharian',
  'Khushab',
  'Khuzdar',
  'Kohat',
  'Kohlu',
  'Kot Addu',
  'Kot Diji',
  'Kotli',
  'Kotri',
  'Kulachi',
  'Lahore',
  'Lakki Marwat',
  'Larkana',
  'Lasbela',
  'Layyah',
  'Liaquatpur',
  'Lodhran',
  'Loralai',
  'Mach',
  'Mailsi',
  'Malakand',
  'Mandi Bahauddin',
  'Mansehra',
  'Mardan',
  'Mastung',
  'Matiari',
  'Mehar',
  'Mian Channu',
  'Mianwali',
  'Minchinabad',
  'Mingora (Swat)',
  'Mirpur (AJK)',
  'Mirpur Khas',
  'Mirpur Mathelo',
  'Moro',
  'Multan',
  'Muridke',
  'Murree',
  'Muzaffarabad',
  'Muzaffargarh',
  'Nankana Sahib',
  'Narowal',
  'Naushahro Feroze',
  'Nawabshah',
  'Nowshera',
  'Nowshera Virkan',
  'Nushki',
  'Oghi',
  'Okara',
  'Ormara',
  'Pakpattan',
  'Pallandri',
  'Panjgur',
  'Pano Akil',
  'Parachinar',
  'Pasni',
  'Pasrur',
  'Pattoki',
  'Peshawar',
  'Pind Dadan Khan',
  'Pishin',
  'Qila Abdullah',
  'Qila Saifullah',
  'Quetta',
  'Rabwah',
  'Rahim Yar Khan',
  'Rajanpur',
  'Ratodero',
  'Rawalakot',
  'Rawalpindi',
  'Renala Khurd',
  'Risalpur',
  'Rohri',
  'Sadiqabad',
  'Sahiwal',
  'Sakrand',
  'Sambrial',
  'Sangla Hill',
  'Sanghar',
  'Sargodha',
  'Sehwan',
  'Shabqadar',
  'Shahdadkot',
  'Shakargarh',
  'Sheikhupura',
  'Shikarpur',
  'Shorkot',
  'Sialkot',
  'Sibi',
  'Skardu',
  'Sukkur',
  'Surab',
  'Swabi',
  'Talagang',
  'Tando Adam',
  'Tando Allahyar',
  'Tando Muhammad Khan',
  'Tangi',
  'Tank',
  'Taunsa',
  'Taxila',
  'Thatta',
  'Timergara',
  'Toba Tek Singh',
  'Turbat',
  'Umerkot',
  'Usta Mohammad',
  'Vehari',
  'Wah Cantonment',
  'Wazirabad',
  'Yazman',
  'Zhob',
  'Ziarat',
];

const List<String> itemConditions = ['New', 'Used'];

class MarketplaceCategory {
  final String title;
  final IconData icon;
  final List<String> subcategories;

  const MarketplaceCategory({
    required this.title,
    required this.icon,
    required this.subcategories,
  });
}

const List<MarketplaceCategory> appCategories = [
  MarketplaceCategory(title: 'All', icon: Icons.apps, subcategories: ['All']),
  MarketplaceCategory(
    title: 'Motors',
    icon: Icons.directions_car,
    subcategories: [
      'Cars',
      'Motorcycles',
      'Auto Parts',
      'Boats',
      'Heavy Vehicles',
      'Number Plates',
      'Car Accessories',
      'Car Rental',
    ],
  ),
  MarketplaceCategory(
    title: 'Properties',
    icon: Icons.home,
    subcategories: [
      'Apartments for Rent',
      'Apartments for Sale',
      'Villas for Rent',
      'Villas for Sale',
      'Rooms for Rent',
      'Commercial Property',
      'Holiday Homes',
      'Land',
      'Property Services',
    ],
  ),
  MarketplaceCategory(
    title: 'Mobiles & Tablets',
    icon: Icons.phone_android,
    subcategories: [
      'Mobile Phones',
      'Tablets',
      'Smart Watches',
      'Mobile Accessories',
      'SIM Cards',
      'Repair Services',
    ],
  ),
  MarketplaceCategory(
    title: 'Electronics',
    icon: Icons.devices,
    subcategories: [
      'Computers & Laptops',
      'TV & Audio',
      'Cameras',
      'Gaming',
      'Home Appliances',
      'Kitchen Appliances',
      'Computer Accessories',
      'Security Cameras',
    ],
  ),
  MarketplaceCategory(
    title: 'Home & Furniture',
    icon: Icons.chair,
    subcategories: [
      'Furniture',
      'Home Decor',
      'Garden & Outdoor',
      'Kitchenware',
      'Lighting',
      'Beds & Mattresses',
      'Tools',
      'Moving & Storage',
    ],
  ),
  MarketplaceCategory(
    title: 'Men Essentials',
    icon: Icons.man,
    subcategories: [
      'Men Clothing',
      'Men Shoes',
      'Watches',
      'Wallets & Bags',
      'Grooming',
      'Perfumes',
      'Sportswear',
      'Sunglasses',
    ],
  ),
  MarketplaceCategory(
    title: 'Women Essentials',
    icon: Icons.woman,
    subcategories: [
      'Women Clothing',
      'Women Shoes',
      'Bags',
      'Jewellery',
      'Beauty & Makeup',
      'Perfumes',
      'Watches',
      'Accessories',
    ],
  ),
  MarketplaceCategory(
    title: 'Kids Essentials',
    icon: Icons.child_care,
    subcategories: [
      'Kids Clothing',
      'Kids Shoes',
      'Toys',
      'Baby Gear',
      'Strollers',
      'School Items',
      'Kids Furniture',
      'Maternity',
    ],
  ),
  MarketplaceCategory(
    title: 'Jobs',
    icon: Icons.work,
    subcategories: [
      'Accounting',
      'Admin',
      'Customer Service',
      'Drivers',
      'Engineering',
      'Hospitality',
      'IT',
      'Marketing',
      'Sales',
      'Real Estate',
      'Construction',
      'Domestic Staff',
    ],
  ),
  MarketplaceCategory(
    title: 'Services',
    icon: Icons.handyman,
    subcategories: [
      'Cleaning',
      'Maintenance',
      'Moving',
      'Car Services',
      'Beauty Services',
      'Tutoring',
      'Photography',
      'Events',
      'Legal Services',
      'Business Services',
      'Home Repair',
      'AC Repair',
      'Plumbing',
      'Electrical',
    ],
  ),
  MarketplaceCategory(
    title: 'Pets',
    icon: Icons.pets,
    subcategories: [
      'Cats',
      'Dogs',
      'Birds',
      'Fish',
      'Pet Food',
      'Pet Accessories',
      'Pet Services',
      'Adoption',
    ],
  ),
  MarketplaceCategory(
    title: 'Sports & Hobbies',
    icon: Icons.sports_soccer,
    subcategories: [
      'Gym Equipment',
      'Bicycles',
      'Sports Gear',
      'Musical Instruments',
      'Books',
      'Collectibles',
      'Camping',
      'Tickets',
    ],
  ),
  MarketplaceCategory(
    title: 'Business & Industrial',
    icon: Icons.business_center,
    subcategories: [
      'Office Furniture',
      'Restaurant Equipment',
      'Industrial Equipment',
      'Medical Equipment',
      'Retail Equipment',
      'Wholesale',
      'Machinery',
    ],
  ),
  MarketplaceCategory(
    title: 'Community',
    icon: Icons.groups,
    subcategories: [
      'Classes',
      'Activities',
      'Lost & Found',
      'Volunteers',
      'Announcements',
      'Free Stuff',
    ],
  ),
];

MarketplaceCategory categoryByTitle(String title) {
  return appCategories.firstWhere(
    (category) => category.title == title,
    orElse: () => appCategories.first,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Web Push (VAPID) public key from Firebase Console → Cloud Messaging →
/// "Web configuration" → Web Push certificates. Leave empty to disable web
/// push until configured (the app still works fully without it).
const String fcmVapidKey =
    'BAOvH3nPZu5Q8_NQivTrJuOM-i2YY1BvBx9gKf-df5RexGZhzejVShaMudQ1GBMejHjylLWMt75LY5xzuopJPPY';

/// Shows snackbars from anywhere (e.g. foreground push notifications).
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Requests notification permission, registers this device's FCM token under
/// users/{uid}/fcmTokens, and surfaces foreground messages. Fully guarded:
/// if messaging isn't configured/available it silently no-ops.
Future<void> setupPushNotifications() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // On web a VAPID key is required; skip cleanly until it's set.
    if (kIsWeb && fcmVapidKey.isEmpty) return;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: fcmVapidKey)
        : await messaging.getToken();

    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
            'createdAt': Timestamp.now(),
            'platform': kIsWeb ? 'web' : 'app',
          });
    }

    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null) {
        rootMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              [n.title, n.body].where((e) => (e ?? '').isNotEmpty).join(': '),
            ),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    });
  } catch (_) {
    // Messaging unavailable/unconfigured — ignore.
  }
}

/// Default country dialing code for Pakistan (used to build WhatsApp links).
const String defaultCountryCode = '92';

/// Converts a Pakistani number into the international digits WhatsApp expects
/// (e.g. "0300 1234567" -> "923001234567", "+92 300 1234567" -> "923001234567").
String normalizePhoneForWhatsApp(String phone) {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return digits;

  if (digits.startsWith('00')) {
    // International prefix typed as 00 -> drop it.
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    // Local format 03xx... -> 92 3xx...
    digits = '$defaultCountryCode${digits.substring(1)}';
  } else if (!digits.startsWith(defaultCountryCode)) {
    // Bare subscriber number (e.g. 3001234567) -> prefix country code.
    digits = '$defaultCountryCode$digits';
  }
  return digits;
}

/// Strips currency text and returns a numeric value for sorting/filtering.
double parsePrice(String price) {
  final cleaned = price.replaceAll(RegExp(r'[^0-9.]'), '');
  return double.tryParse(cleaned) ?? 0;
}

/// Human friendly "x ago" from a Firestore [Timestamp].
String timeAgo(Timestamp? timestamp) {
  if (timestamp == null) return '';

  final diff = DateTime.now().difference(timestamp.toDate());

  if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
  if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
  return 'Just now';
}

/// Resolves the device's current GPS position, handling service + permission
/// state. Throws a human-readable message on failure (e.g. permission denied).
Future<Position> determineCurrentPosition() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw 'Location services are turned off. Please enable them and retry.';
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw 'Location permission was denied.';
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw 'Location permission is permanently denied. Enable it in your '
        'browser/device settings.';
  }

  return Geolocator.getCurrentPosition();
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

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
  String city;
  double? latitude;
  double? longitude;
  int views;
  bool isFeatured;
  Timestamp? createdAt;

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
    this.city = '',
    this.latitude,
    this.longitude,
    this.views = 0,
    this.isFeatured = false,
    this.createdAt,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

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
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'views': views,
      'isFeatured': isFeatured,
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
      // 'city' is the current field; fall back to legacy 'emirate' for old ads.
      city: data['city']?.toString() ?? data['emirate']?.toString() ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      views: (data['views'] as num?)?.toInt() ?? 0,
      isFeatured: data['isFeatured'] == true,
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
    );
  }
}

final List<Listing> favoriteListings = [];

// ---------------------------------------------------------------------------
// Trust & reviews + discovery helpers
// ---------------------------------------------------------------------------

/// Read-only star display. Pass [count] to also show "4.5 (12)".
class StarRating extends StatelessWidget {
  final double rating;
  final double size;
  final int? count;
  final Color color;

  const StarRating({
    super.key,
    required this.rating,
    this.size = 16,
    this.count,
    this.color = kGold,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: size,
            color: color,
          ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text(
            count == 0
                ? 'No reviews'
                : '${rating.toStringAsFixed(1)} ($count)',
            style: TextStyle(fontSize: size * 0.8, color: Colors.grey[700]),
          ),
        ],
      ],
    );
  }
}

/// Adds or updates the current user's review of a seller and keeps the seller's
/// aggregate rating (ratingSum/ratingCount on their user doc) consistent.
Future<void> submitSellerReview({
  required String sellerId,
  required int rating,
  required String text,
}) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) return;

  final fs = FirebaseFirestore.instance;
  final reviewRef =
      fs.collection('users').doc(sellerId).collection('reviews').doc(me.uid);
  final userRef = fs.collection('users').doc(sellerId);

  await fs.runTransaction((tx) async {
    final reviewSnap = await tx.get(reviewRef);
    final userSnap = await tx.get(userRef);

    final existed = reviewSnap.exists;
    final oldRating =
        existed ? (reviewSnap.data()?['rating'] as num?)?.toInt() ?? 0 : 0;

    final userData = userSnap.data() ?? {};
    num sum = (userData['ratingSum'] as num?) ?? 0;
    int count = (userData['ratingCount'] as num?)?.toInt() ?? 0;

    sum = sum - oldRating + rating;
    if (!existed) count += 1;

    tx.set(reviewRef, {
      'reviewerId': me.uid,
      'reviewerName': me.email ?? 'User',
      'rating': rating,
      'text': text.trim(),
      'createdAt': Timestamp.now(),
    });
    tx.set(userRef, {
      'ratingSum': sum,
      'ratingCount': count,
    }, SetOptions(merge: true));
  });
}

/// Records that the current user viewed a listing (for the "Recently viewed"
/// rail on Home). Best-effort; failures are ignored.
Future<void> recordRecentlyViewed(Listing listing) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || listing.id.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('recentlyViewed')
        .doc(listing.id)
        .set({
          ...listing.toMap(),
          'viewedAt': Timestamp.now(),
        });
  } catch (_) {
    // Non-critical.
  }
}

// ---------------------------------------------------------------------------
// App root + auth
// ---------------------------------------------------------------------------

class MarketHubApp extends StatelessWidget {
  const MarketHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarketHub',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: buildAppTheme(),
      builder: (context, child) => AppBackground(child: child ?? const SizedBox()),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const HomeScreen();
        }

        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  String? errorMessage;

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Please enter email and password');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      // AuthGate listens to authStateChanges and navigates automatically.
    } on FirebaseAuthException catch (e) {
      setState(() => errorMessage = e.message ?? 'Authentication failed');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> continueAsGuest() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      setState(() => errorMessage = e.message ?? 'Could not continue as guest');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.storefront, size: 80, color: kPakGreen),
                    const SizedBox(height: 12),
                    const Text(
                      'MarketHub',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: kPakGreen,
                      ),
                    ),
                const SizedBox(height: 8),
                Text(
                  isLogin ? 'Log in to your account' : 'Create a new account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  enabled: !isLoading,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  enabled: !isLoading,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isLoading ? null : submit,
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isLogin ? 'Log In' : 'Sign Up'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          setState(() {
                            isLogin = !isLogin;
                            errorMessage = null;
                          });
                        },
                  child: Text(
                    isLogin
                        ? "Don't have an account? Sign up"
                        : 'Already have an account? Log in',
                  ),
                ),
                const Divider(height: 32),
                    OutlinedButton.icon(
                      onPressed: isLoading ? null : continueAsGuest,
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Continue as Guest'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable wrapper that is reachable with the keyboard.
///
/// Arrow keys move focus between [FocusableTap]s (directional focus, built into
/// MaterialApp), Enter/Space activates the focused one, and a blue ring shows
/// which item is currently selected. Off-screen items scroll into view when
/// they receive focus.
class FocusableTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;
  final BorderRadius borderRadius;

  const FocusableTap({
    super.key,
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) {
        setState(() => _focused = value);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _focused ? kGold : Colors.transparent,
            width: 3,
          ),
        ),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Opens a searchable, full-height city picker. Returns the chosen city, or
/// null if dismissed. Much friendlier on mobile than a 190-item dropdown.
Future<String?> showCityPicker(
  BuildContext context, {
  bool includeAll = false,
}) {
  final options = [if (includeAll) 'All', ...pakistanCities];

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = options
              .where((c) => c.toLowerCase().contains(query.toLowerCase()))
              .toList();

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    'Select City',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search city...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No city found'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final city = filtered[index];
                              return ListTile(
                                title: Text(city),
                                onTap: () => Navigator.pop(context, city),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// A tap-to-open city field that mirrors a form dropdown but uses the
/// searchable [showCityPicker].
class CitySelector extends StatelessWidget {
  final String value;
  final String label;
  final bool includeAll;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const CitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'City',
    this.includeAll = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final selected = await showCityPicker(
                context,
                includeAll: includeAll,
              );
              if (selected != null) onChanged(selected);
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_city, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(child: Text(value)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// A compact ad card used in the horizontal Home rails.
class HorizontalAdCard extends StatelessWidget {
  final Listing listing;

  const HorizontalAdCard({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final img = listing.galleryImages;
    final w = MediaQuery.of(context).size.width;
    // Narrower cards on phones so ~2 peek into view and feel app-like.
    final cardWidth = w < 600 ? (w * 0.44).clamp(150.0, 190.0) : 220.0;

    return FocusableTap(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: listing)),
      ),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(6),
        child: SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: img.isNotEmpty
                          ? Image.network(
                              img.first,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Container(
                                color: Colors.grey.shade300,
                                child: const Center(
                                  child: Icon(Icons.broken_image, size: 40),
                                ),
                              ),
                            )
                          : Container(
                              color: Colors.grey.shade300,
                              child: const Center(
                                child: Icon(Icons.image, size: 40),
                              ),
                            ),
                    ),
                    if (listing.isFeatured)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kGold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'FEATURED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$currencySymbol ${listing.price}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      listing.city.isEmpty ? listing.location : listing.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled horizontal rail of ads fed by a Firestore [stream]. Hides itself
/// entirely when the stream has no results (so empty sections never show).
class AdsRail extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Stream<QuerySnapshot> stream;

  const AdsRail({
    super.key,
    required this.title,
    required this.stream,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final listings =
            snapshot.data!.docs.map((d) => Listing.fromDoc(d)).toList();
        if (listings.isEmpty) return const SizedBox.shrink();
        final phone = isPhone(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: phone ? 19 : 22),
                  const SizedBox(width: 6),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: phone ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: phone ? 208 : 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: listings.length,
                itemBuilder: (context, index) =>
                    HorizontalAdCard(listing: listings[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single promo banner definition for the home carousel.
class PromoBannerData {
  final String title;
  final String subtitle;
  final String image;
  final List<Color> colors; // gradient fallback if the image fails to load
  final Widget Function() destination;

  const PromoBannerData({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.colors,
    required this.destination,
  });
}

/// Auto-advancing promotional banner carousel with dot indicators.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key});

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _index = 0;

  static const _banners = <PromoBannerData>[
    PromoBannerData(
      title: 'Cars & more',
      subtitle: 'Explore the best Motors deals',
      image:
          'https://images.unsplash.com/photo-1503376780353-7e6692767b70?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
      destination: _toMotors,
    ),
    PromoBannerData(
      title: 'Find your home',
      subtitle: 'Browse Properties across Pakistan',
      image:
          'https://images.unsplash.com/photo-1560518883-ce09059eeffa?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
      destination: _toProperties,
    ),
    PromoBannerData(
      title: 'Latest mobiles',
      subtitle: 'Phones, tablets & gadgets',
      image:
          'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
      destination: _toMobiles,
    ),
    PromoBannerData(
      title: 'Sell faster',
      subtitle: 'Post your ad free in 2 minutes',
      image:
          'https://images.unsplash.com/photo-1556742502-ec7c0e9f34b1?auto=format&fit=crop&w=900&q=70',
      colors: [kPakGreen, kPakGreenLight],
      destination: _toPostAd,
    ),
  ];

  static Widget _toPostAd() => const AddListingScreen();
  static Widget _toMotors() => const CategoryScreen(title: 'Motors');
  static Widget _toProperties() => const CategoryScreen(title: 'Properties');
  static Widget _toMobiles() =>
      const CategoryScreen(title: 'Mobiles & Tablets');

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % _banners.length,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _bannerGradient(List<Color> colors) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _banners.length,
            itemBuilder: (context, i) {
              final b = _banners[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Material(
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => b.destination()),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Real photo (with gradient fallback while loading/on error).
                        Image.network(
                          b.image,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : _bannerGradient(b.colors),
                          errorBuilder: (context, e, s) =>
                              _bannerGradient(b.colors),
                        ),
                        // Dark scrim so the text stays readable over any photo.
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                b.subtitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Tap to explore',
                                  style: TextStyle(
                                    color: b.colors.first,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _banners.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == _index ? kPakGreen : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dubizzle-style 2-column feed card: image with heart + featured badge, then
/// bold price, title, and location/time. Fills its grid cell.
class FeedAdCard extends StatefulWidget {
  final Listing listing;

  const FeedAdCard({super.key, required this.listing});

  @override
  State<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<FeedAdCard> {
  bool get isFav =>
      favoriteListings.any((i) => i.id == widget.listing.id);

  void toggleFav() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final was = isFav;
    setState(() {
      if (was) {
        favoriteListings.removeWhere((i) => i.id == widget.listing.id);
      } else {
        favoriteListings.add(widget.listing);
      }
    });
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.listing.id);
    if (was) {
      await ref.delete();
    } else {
      await ref.set(widget.listing.toMap());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    final img = l.galleryImages;
    final posted = timeAgo(l.createdAt);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: l)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  img.isNotEmpty
                      ? Image.network(
                          img.first,
                          fit: BoxFit.cover,
                          errorBuilder: (context, e, s) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 36),
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.image, size: 36),
                          ),
                        ),
                  if (l.isFeatured)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kGold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'FEATURED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: toggleFav,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white70,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$currencySymbol ${l.price}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.title.isEmpty ? 'Untitled ad' : l.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 1),
                      Expanded(
                        child: Text(
                          l.city.isEmpty ? l.location : l.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      if (posted.isNotEmpty)
                        Text(
                          posted,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  String searchQuery = '';
  String homeCity = 'All Pakistan';
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    ensureUserDoc();
    loadFavorites();
    setupPushNotifications();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  /// Creates a `users/{uid}` profile doc the first time we see this account,
  /// so seller profiles can show a "Member since" date.
  Future<void> ensureUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'email': user.email ?? '',
        'isAnonymous': user.isAnonymous,
        'verified': user.emailVerified,
        'createdAt': Timestamp.now(),
      });
    } else if (snap.data()?['verified'] != user.emailVerified) {
      // Keep the public "Verified" badge in sync with email verification.
      await ref.set({'verified': user.emailVerified}, SetOptions(merge: true));
    }
  }

  Future<void> loadFavorites() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    favoriteListings.clear();
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();

    if (!mounted) return;

    setState(() {
      for (final doc in snapshot.docs) {
        favoriteListings.add(Listing.fromDoc(doc));
      }
    });
  }

  void openSearch(String query) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SearchScreen(initialQuery: query)),
    );
  }

  Widget homeContent() =>
      isPhone(context) ? _mobileHome() : _desktopHome();

  /// Dubizzle-style phone home: search pill, round category strip, and a
  /// 2-column "Fresh recommendations" feed on a light background.
  Widget _mobileHome() {
    final w = MediaQuery.of(context).size.width;
    final cols = w > 1100 ? 4 : (w > 700 ? 3 : 2);
    final categories =
        appCategories.where((c) => c.title != 'All').toList();

    return Container(
      color: const Color(0xFFEFF1F2),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .orderBy('createdAt', descending: true)
            .limit(60)
            .snapshots(),
        builder: (context, snapshot) {
          var listings = (snapshot.data?.docs ?? [])
              .map((d) => Listing.fromDoc(d))
              .toList()
            ..sort((a, b) {
              if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
              final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
              final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
              return bt.compareTo(at);
            });

          if (homeCity != 'All Pakistan') {
            listings =
                listings.where((l) => l.city == homeCity).toList();
          }
          final featured = listings.where((l) => l.isFeatured).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Material(
                    elevation: 1.5,
                    borderRadius: BorderRadius.circular(30),
                    child: TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) => openSearch(v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Find cars, mobiles, property and more',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 102,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final cat = categories[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CategoryScreen(title: cat.title),
                          ),
                        ),
                        child: SizedBox(
                          width: 74,
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              CircleAvatar(
                                radius: 26,
                                backgroundColor:
                                    kPakGreen.withValues(alpha: 0.12),
                                child: Icon(
                                  cat.icon,
                                  color: kPakGreen,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cat.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: PromoCarousel(),
                ),
              ),
              if (featured.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Row(
                          children: [
                            Icon(Icons.star, color: kGold, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Featured',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 218,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          itemCount: featured.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              width: 165,
                              child: FeedAdCard(listing: featured[i]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(
                    'Fresh recommendations',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              if (!snapshot.hasData)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (listings.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: Text('No ads yet. Be the first to post!'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => FeedAdCard(listing: listings[i]),
                      childCount: listings.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          );
        },
      ),
    );
  }

  Widget _desktopHome() {
    final filteredCategories = appCategories.where((category) {
      return category.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
    final phone = isPhone(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 10 : 16, 12, phone ? 10 : 16, 0),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search all ads...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => openSearch(searchController.text.trim()),
              ),
            ),
            onChanged: (value) {
              setState(() {
                searchQuery = value;
              });
            },
            onSubmitted: (value) => openSearch(value.trim()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: () {
                        final w = MediaQuery.of(context).size.width;
                        if (w > 1100) return 4;
                        if (w > 700) return 3;
                        return 2;
                      }(),
                      childAspectRatio: phone ? 1.05 : 1.4,
                      crossAxisSpacing: phone ? 10 : 12,
                      mainAxisSpacing: phone ? 10 : 12,
                    ),
                    itemCount: filteredCategories.length,
                    itemBuilder: (context, index) {
                      final category = filteredCategories[index];

                      return FocusableTap(
                        autofocus: index == 0,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CategoryScreen(title: category.title),
                            ),
                          );
                        },
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(category.icon, size: 42, color: kPakGreen),
                              const SizedBox(height: 12),
                              Text(
                                category.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                category.title == 'All'
                                    ? 'Browse all ads'
                                    : '${category.subcategories.length} subcategories',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  AdsRail(
                    title: 'Featured',
                    icon: Icons.star,
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .where('isFeatured', isEqualTo: true)
                        .limit(10)
                        .snapshots(),
                  ),
                  AdsRail(
                    title: 'Latest Ads',
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .orderBy('createdAt', descending: true)
                        .limit(10)
                        .snapshots(),
                  ),
                  AdsRail(
                    title: 'Trending',
                    icon: Icons.trending_up,
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .orderBy('views', descending: true)
                        .limit(10)
                        .snapshots(),
                  ),
                  if (FirebaseAuth.instance.currentUser != null)
                    AdsRail(
                      title: 'Recently Viewed',
                      icon: Icons.history,
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser!.uid)
                          .collection('recentlyViewed')
                          .orderBy('viewedAt', descending: true)
                          .limit(10)
                          .snapshots(),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _postAd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddListingScreen()),
    );
    if (mounted) setState(() {});
  }

  /// dubizzle-style home top bar: location selector + favorites + alerts.
  PreferredSizeWidget _homeAppBar() {
    return AppBar(
      titleSpacing: 12,
      title: InkWell(
        onTap: () async {
          final c = await showCityPicker(context, includeAll: true);
          if (c != null) {
            setState(() => homeCity = c == 'All' ? 'All Pakistan' : c);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                homeCity,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.favorite_border, color: Colors.white),
          tooltip: 'Favorites',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FavoritesScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.white),
          tooltip: 'Saved search alerts',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SavedSearchesScreen()),
          ),
        ),
      ],
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = selectedIndex == index;
    final color = selected ? kPakGreen : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => selectedIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeContent(),
      const ChatsScreen(),
      const MyAdsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: selectedIndex == 0 ? _homeAppBar() : null,
      body: pages[selectedIndex],
      floatingActionButton: SizedBox(
        width: 58,
        height: 58,
        child: FloatingActionButton(
          onPressed: _postAd,
          backgroundColor: kPakGreen,
          shape: const CircleBorder(),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 22, color: Colors.white),
              Text(
                'SELL',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 62,
        color: Colors.white,
        elevation: 16,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _navItem(Icons.home, 'Home', 0),
            _navItem(Icons.chat, 'Chats', 1),
            const SizedBox(width: 64),
            _navItem(Icons.list_alt, 'My Ads', 2),
            _navItem(Icons.person, 'Profile', 3),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Browse + search + filters
// ---------------------------------------------------------------------------

class CategoryScreen extends StatelessWidget {
  final String title;

  const CategoryScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListingsBrowser(category: title),
    );
  }
}

class SearchScreen extends StatelessWidget {
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ListingsBrowser(initialQuery: initialQuery),
    );
  }
}

/// Lists the current user's saved searches, with run + delete. Alerts fire
/// server-side (notifyOnNewListing) when a new ad matches one of these.
class SavedSearchesScreen extends StatelessWidget {
  const SavedSearchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved Searches')),
        body: const Center(
          child: Text(
            'Please log in to see saved searches',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Searches')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('savedSearches')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved searches yet.\nTap the bell icon while browsing to '
                  'save a search and get alerts on new matching ads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.bookmark, color: kPakGreen),
                  title: Text(d['label']?.toString() ?? 'Saved search'),
                  subtitle: const Text('Tap to run · alerts on new matches'),
                  onTap: () {
                    final cat = d['category']?.toString();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: Text(d['label']?.toString() ?? 'Results'),
                          ),
                          body: ListingsBrowser(
                            category: (cat == null || cat == 'All')
                                ? null
                                : cat,
                            initialQuery: d['query']?.toString() ?? '',
                            initialSubcategory: d['subcategory']?.toString(),
                            initialCity: d['city']?.toString(),
                            initialMinPrice: (d['minPrice'] as num?)?.toDouble(),
                            initialMaxPrice: (d['maxPrice'] as num?)?.toDouble(),
                          ),
                        ),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('savedSearches')
                        .doc(docs[index].id)
                        .delete(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Reusable browse surface: search box, subcategory chips (when a category is
/// given), sort + price/emirate filters, and the results list.
class ListingsBrowser extends StatefulWidget {
  final String? category;
  final String initialQuery;
  final String? initialSubcategory;
  final String? initialCity;
  final double? initialMinPrice;
  final double? initialMaxPrice;

  const ListingsBrowser({
    super.key,
    this.category,
    this.initialQuery = '',
    this.initialSubcategory,
    this.initialCity,
    this.initialMinPrice,
    this.initialMaxPrice,
  });

  @override
  State<ListingsBrowser> createState() => _ListingsBrowserState();
}

class _ListingsBrowserState extends State<ListingsBrowser> {
  late String searchText;
  late final TextEditingController searchController;
  late String selectedSubcategory;
  String sortBy = 'Newest';
  late String cityFilter;
  double? minPrice;
  double? maxPrice;

  static const sortOptions = [
    'Newest',
    'Price: Low to High',
    'Price: High to Low',
  ];

  @override
  void initState() {
    super.initState();
    searchText = widget.initialQuery;
    searchController = TextEditingController(text: widget.initialQuery);
    selectedSubcategory = widget.initialSubcategory ?? 'All';
    cityFilter = widget.initialCity ?? 'All';
    minPrice = widget.initialMinPrice;
    maxPrice = widget.initialMaxPrice;
  }

  /// Saves the current search criteria so the user can be alerted when a new
  /// matching ad is posted.
  Future<void> saveCurrentSearch() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final parts = <String>[];
    if (searchText.trim().isNotEmpty) parts.add('"${searchText.trim()}"');
    if (hasCategory) parts.add(widget.category!);
    if (selectedSubcategory != 'All') parts.add(selectedSubcategory);
    if (cityFilter != 'All') parts.add('in $cityFilter');
    if (minPrice != null || maxPrice != null) {
      parts.add(
        'Rs ${minPrice?.toStringAsFixed(0) ?? '0'}-'
        '${maxPrice?.toStringAsFixed(0) ?? 'any'}',
      );
    }
    final label = parts.isEmpty ? 'All ads' : parts.join(' · ');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedSearches')
        .add({
          'label': label,
          'query': searchText.trim(),
          'category': widget.category ?? 'All',
          'subcategory': selectedSubcategory,
          'city': cityFilter,
          'minPrice': minPrice,
          'maxPrice': maxPrice,
          'createdAt': Timestamp.now(),
        });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "$label" — we\'ll alert you on new matches'),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  bool get hasCategory => widget.category != null && widget.category != 'All';

  Future<void> openFilters() async {
    final minController = TextEditingController(
      text: minPrice == null ? '' : minPrice!.toStringAsFixed(0),
    );
    final maxController = TextEditingController(
      text: maxPrice == null ? '' : maxPrice!.toStringAsFixed(0),
    );
    String tempCity = cityFilter;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CitySelector(
                    value: tempCity,
                    includeAll: true,
                    onChanged: (value) =>
                        setSheetState(() => tempCity = value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Min price',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max price',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              cityFilter = 'All';
                              minPrice = null;
                              maxPrice = null;
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              cityFilter = tempCity;
                              minPrice = double.tryParse(
                                minController.text.trim(),
                              );
                              maxPrice = double.tryParse(
                                maxController.text.trim(),
                              );
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int get activeFilterCount {
    var count = 0;
    if (cityFilter != 'All') count++;
    if (minPrice != null) count++;
    if (maxPrice != null) count++;
    return count;
  }

  List<Listing> applyFilters(List<Listing> listings) {
    final query = searchText.toLowerCase();

    final result = listings.where((listing) {
      final matchesSearch =
          query.isEmpty ||
          listing.title.toLowerCase().contains(query) ||
          listing.description.toLowerCase().contains(query) ||
          listing.location.toLowerCase().contains(query) ||
          listing.category.toLowerCase().contains(query) ||
          listing.subcategory.toLowerCase().contains(query);

      final matchesSub =
          selectedSubcategory == 'All' ||
          listing.subcategory == selectedSubcategory;

      final matchesCity =
          cityFilter == 'All' || listing.city == cityFilter;

      final price = parsePrice(listing.price);
      final matchesMin = minPrice == null || price >= minPrice!;
      final matchesMax = maxPrice == null || price <= maxPrice!;

      return matchesSearch &&
          matchesSub &&
          matchesCity &&
          matchesMin &&
          matchesMax;
    }).toList();

    result.sort((a, b) {
      // Featured ads always rank first.
      if (a.isFeatured != b.isFeatured) {
        return a.isFeatured ? -1 : 1;
      }
      switch (sortBy) {
        case 'Price: Low to High':
          return parsePrice(a.price).compareTo(parsePrice(b.price));
        case 'Price: High to Low':
          return parsePrice(b.price).compareTo(parsePrice(a.price));
        default:
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
      }
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'listings',
    );

    if (hasCategory) {
      query = query.where('category', isEqualTo: widget.category);
    }

    final currentCategory = categoryByTitle(widget.category ?? 'All');
    final subcategories = ['All', ...currentCategory.subcategories];

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading listings: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final allListings = docs.map((d) => Listing.fromDoc(d)).toList();
        final filtered = applyFilters(allListings);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by title, location or price...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    searchText = value;
                  });
                },
              ),
            ),
            // Sort + filter bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: sortBy,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sort',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: sortOptions
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => sortBy = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: openFilters,
                    icon: const Icon(Icons.tune),
                    label: Text(
                      activeFilterCount == 0
                          ? 'Filters'
                          : 'Filters ($activeFilterCount)',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      tooltip: 'Save this search & get alerts',
                      icon: const Icon(Icons.notification_add, color: kPakGreen),
                      onPressed: saveCurrentSearch,
                    ),
                  ),
                ],
              ),
            ),
            if (hasCategory)
              SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: subcategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final subcategory = subcategories[index];
                    final isSelected = selectedSubcategory == subcategory;

                    return ChoiceChip(
                      label: Text(subcategory),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          selectedSubcategory = subcategory;
                        });
                      },
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No listings found',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: filtered
                          .map((listing) => ListingCard(listing: listing))
                          .toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Listing card
// ---------------------------------------------------------------------------

class ListingCard extends StatefulWidget {
  final Listing listing;

  const ListingCard({super.key, required this.listing});

  @override
  State<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<ListingCard> {
  bool get isFavorite {
    return favoriteListings.any((item) => item.id == widget.listing.id);
  }

  void toggleFavorite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final wasFavorite = isFavorite;

    setState(() {
      if (wasFavorite) {
        favoriteListings.removeWhere((item) => item.id == widget.listing.id);
      } else {
        favoriteListings.add(widget.listing);
      }
    });

    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.listing.id);

    if (wasFavorite) {
      await ref.delete();
    } else {
      await ref.set(widget.listing.toMap());
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final images = listing.galleryImages;
    final hasImage = images.isNotEmpty;
    final posted = timeAgo(listing.createdAt);

    return FocusableTap(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: listing)),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Stack(
                children: [
                  hasImage
                      ? Image.network(
                          images.first,
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox(
                              height: 170,
                              child: Center(
                                child: Icon(Icons.broken_image, size: 60),
                              ),
                            );
                          },
                        )
                      : const SizedBox(
                          height: 170,
                          child: Center(child: Icon(Icons.image, size: 60)),
                        ),
                  if (listing.isFeatured)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kGold,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: Colors.red,
                        ),
                        onPressed: toggleFavorite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title.isEmpty ? 'Untitled ad' : listing.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$currencySymbol ${listing.price}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          [
                            listing.city,
                            listing.location,
                          ].where((e) => e.isNotEmpty).join(', '),
                          style: const TextStyle(color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (listing.condition.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: listing.condition == 'New'
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: listing.condition == 'New'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                          child: Text(
                            listing.condition,
                            style: TextStyle(
                              fontSize: 11,
                              color: listing.condition == 'New'
                                  ? Colors.green.shade800
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (posted.isNotEmpty)
                        Text(
                          posted,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Post ad
// ---------------------------------------------------------------------------

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  List<XFile> selectedImages = [];
  final ImagePicker picker = ImagePicker();

  final titleController = TextEditingController();
  final priceController = TextEditingController();
  final locationController = TextEditingController();
  final phoneController = TextEditingController();
  final descriptionController = TextEditingController();

  String selectedCategory = 'Motors';
  String selectedSubcategory = 'Cars';
  String selectedCondition = 'Used';
  String selectedCity = 'Karachi';
  double? latitude;
  double? longitude;
  bool isLocating = false;
  bool isSubmitting = false;

  List<String> get currentSubcategories {
    return categoryByTitle(selectedCategory).subcategories;
  }

  Future<void> useCurrentLocation() async {
    setState(() => isLocating = true);
    try {
      final position = await determineCurrentPosition();
      if (!mounted) return;
      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location added to your ad')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  Future<void> pickImages() async {
    final images = await picker.pickMultiImage();

    if (images.isNotEmpty) {
      setState(() {
        selectedImages = images;
      });
    }
  }

  Future<List<String>> uploadImages() async {
    final urls = <String>[];

    for (var i = 0; i < selectedImages.length; i++) {
      final bytes = await selectedImages[i].readAsBytes();

      final ref = FirebaseStorage.instance
          .ref()
          .child('listings')
          .child('${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  Future<void> submitListing() async {
    if (titleController.text.trim().isEmpty ||
        priceController.text.trim().isEmpty ||
        locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title, price, and location')),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      final imageUrls = await uploadImages();

      await FirebaseFirestore.instance.collection('listings').add({
        'title': titleController.text.trim(),
        'price': priceController.text.trim(),
        'location': locationController.text.trim(),
        'city': selectedCity,
        'latitude': latitude,
        'longitude': longitude,
        'phone': phoneController.text.trim(),
        'description': descriptionController.text.trim(),
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '',
        'images': imageUrls,
        'category': selectedCategory,
        'subcategory': selectedSubcategory,
        'condition': selectedCondition,
        'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'sellerName':
            FirebaseAuth.instance.currentUser?.email ?? 'Anonymous seller',
        'createdAt': Timestamp.now(),
        'views': 0,
        'isFeatured': false,
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to post ad: $e')));
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    priceController.dispose();
    locationController.dispose();
    phoneController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subcategories = currentSubcategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Post Ad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            OutlinedButton.icon(
              onPressed: isSubmitting ? null : pickImages,
              icon: const Icon(Icons.add_a_photo),
              label: Text(
                selectedImages.isEmpty
                    ? 'Add Photos'
                    : '${selectedImages.length} photo(s) selected',
              ),
            ),
            if (selectedImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: selectedImages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        selectedImages[index].path,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 90,
                          height: 90,
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.image),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(
                labelText: 'Price (PKR)',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Area / Block',
                hintText: 'Example: Gulshan-e-Iqbal, Block 5',
              ),
            ),
            const SizedBox(height: 12),
            CitySelector(
              value: selectedCity,
              enabled: !isSubmitting,
              onChanged: (value) => setState(() => selectedCity = value),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (isSubmitting || isLocating) ? null : useCurrentLocation,
              icon: isLocating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      latitude != null
                          ? Icons.location_on
                          : Icons.my_location,
                      color: latitude != null ? Colors.green : null,
                    ),
              label: Text(
                latitude != null
                    ? 'Current location added ✓'
                    : 'Use my current location',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCondition,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: itemConditions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: isSubmitting
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => selectedCondition = value);
                      }
                    },
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'WhatsApp / Phone Number',
                hintText: 'Example: 03001234567 or +92 300 1234567',
              ),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              decoration: const InputDecoration(labelText: 'Main Category'),
              items: appCategories
                  .where((category) => category.title != 'All')
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.title,
                      child: Text(category.title),
                    ),
                  )
                  .toList(),
              onChanged: isSubmitting
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          selectedCategory = value;
                          selectedSubcategory = categoryByTitle(
                            value,
                          ).subcategories.first;
                        });
                      }
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: subcategories.contains(selectedSubcategory)
                  ? selectedSubcategory
                  : subcategories.first,
              decoration: const InputDecoration(labelText: 'Subcategory'),
              items: subcategories
                  .map(
                    (subcategory) => DropdownMenuItem(
                      value: subcategory,
                      child: Text(subcategory),
                    ),
                  )
                  .toList(),
              onChanged: isSubmitting
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          selectedSubcategory = value;
                        });
                      }
                    },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isSubmitting ? null : submitListing,
              child: isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit'),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My ads + edit
// ---------------------------------------------------------------------------

class MyAdsScreen extends StatefulWidget {
  const MyAdsScreen({super.key});

  @override
  State<MyAdsScreen> createState() => _MyAdsScreenState();
}

class _MyAdsScreenState extends State<MyAdsScreen> {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('My Ads')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading ads: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No ads posted yet',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final listing = Listing.fromDoc(docs[index]);
              final images = listing.galleryImages;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: images.isEmpty
                      ? const Icon(Icons.image, size: 40)
                      : Image.network(
                          images.first,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.image, size: 40);
                          },
                        ),
                  title: Row(
                    children: [
                      Flexible(child: Text(listing.title)),
                      if (listing.isFeatured) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star, size: 16, color: kGold),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${[listing.city, listing.location].where((e) => e.isNotEmpty).join(', ')}'
                    '${listing.subcategory.isEmpty ? '' : ' • ${listing.subcategory}'}'
                    '\n${listing.views} views',
                  ),
                  isThreeLine: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditListingScreen(listing: listing),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: listing.isFeatured
                            ? 'Remove from Featured'
                            : 'Boost to Featured',
                        icon: Icon(
                          listing.isFeatured
                              ? Icons.star
                              : Icons.star_border,
                          color: kGold,
                        ),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('listings')
                              .doc(listing.id)
                              .update({'isFeatured': !listing.isFeatured});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  listing.isFeatured
                                      ? 'Removed from Featured'
                                      : 'Boosted! Your ad is now Featured',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('listings')
                              .doc(listing.id)
                              .delete();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EditListingScreen extends StatefulWidget {
  final Listing listing;

  const EditListingScreen({super.key, required this.listing});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  late TextEditingController titleController;
  late TextEditingController priceController;
  late TextEditingController locationController;
  late TextEditingController phoneController;
  late TextEditingController descriptionController;
  late String selectedCategory;
  late String selectedSubcategory;
  late String selectedCondition;
  late String selectedCity;
  double? latitude;
  double? longitude;
  bool isLocating = false;

  @override
  void initState() {
    super.initState();
    latitude = widget.listing.latitude;
    longitude = widget.listing.longitude;

    titleController = TextEditingController(text: widget.listing.title);
    priceController = TextEditingController(text: widget.listing.price);
    locationController = TextEditingController(text: widget.listing.location);
    phoneController = TextEditingController(text: widget.listing.phone);
    descriptionController = TextEditingController(
      text: widget.listing.description,
    );
    selectedCategory = widget.listing.category.isEmpty
        ? 'Motors'
        : widget.listing.category;
    selectedSubcategory = widget.listing.subcategory.isEmpty
        ? categoryByTitle(selectedCategory).subcategories.first
        : widget.listing.subcategory;
    selectedCondition = itemConditions.contains(widget.listing.condition)
        ? widget.listing.condition
        : 'Used';
    selectedCity = pakistanCities.contains(widget.listing.city)
        ? widget.listing.city
        : 'Karachi';
  }

  Future<void> useCurrentLocation() async {
    setState(() => isLocating = true);
    try {
      final position = await determineCurrentPosition();
      if (!mounted) return;
      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  Future<void> updateListing() async {
    await FirebaseFirestore.instance
        .collection('listings')
        .doc(widget.listing.id)
        .update({
          'title': titleController.text.trim(),
          'price': priceController.text.trim(),
          'location': locationController.text.trim(),
          'city': selectedCity,
          'latitude': latitude,
          'longitude': longitude,
          'phone': phoneController.text.trim(),
          'description': descriptionController.text.trim(),
          'category': selectedCategory,
          'subcategory': selectedSubcategory,
          'condition': selectedCondition,
        });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    titleController.dispose();
    priceController.dispose();
    locationController.dispose();
    phoneController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subcategories = categoryByTitle(selectedCategory).subcategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Ad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Price (PKR)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: 'Area / Block'),
            ),
            const SizedBox(height: 12),
            CitySelector(
              value: selectedCity,
              onChanged: (value) => setState(() => selectedCity = value),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isLocating ? null : useCurrentLocation,
              icon: isLocating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      latitude != null ? Icons.location_on : Icons.my_location,
                      color: latitude != null ? Colors.green : null,
                    ),
              label: Text(
                latitude != null
                    ? 'Current location set ✓'
                    : 'Use my current location',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCondition,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: itemConditions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => selectedCondition = value);
              },
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'WhatsApp / Phone Number',
                hintText: 'Example: 03001234567 or +92 300 1234567',
              ),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              decoration: const InputDecoration(labelText: 'Main Category'),
              items: appCategories
                  .where((category) => category.title != 'All')
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.title,
                      child: Text(category.title),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selectedCategory = value;
                    selectedSubcategory = categoryByTitle(
                      value,
                    ).subcategories.first;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: subcategories.contains(selectedSubcategory)
                  ? selectedSubcategory
                  : subcategories.first,
              decoration: const InputDecoration(labelText: 'Subcategory'),
              items: subcategories
                  .map(
                    (subcategory) => DropdownMenuItem(
                      value: subcategory,
                      child: Text(subcategory),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selectedSubcategory = value;
                  });
                }
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: updateListing,
              child: const Text('Update'),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ad details
// ---------------------------------------------------------------------------

class AdDetailsScreen extends StatefulWidget {
  final Listing listing;

  const AdDetailsScreen({super.key, required this.listing});

  @override
  State<AdDetailsScreen> createState() => _AdDetailsScreenState();
}

class _AdDetailsScreenState extends State<AdDetailsScreen> {
  int currentImage = 0;

  @override
  void initState() {
    super.initState();
    _incrementViews();
    recordRecentlyViewed(widget.listing);
  }

  Future<void> _incrementViews() async {
    final id = widget.listing.id;
    if (id.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(id)
          .update({'views': FieldValue.increment(1)});
    } catch (_) {
      // Non-critical; ignore failures (e.g. favorites cache docs).
    }
  }

  Future<void> openWhatsApp() async {
    if (widget.listing.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone number is missing')),
      );
      return;
    }

    final cleanedPhone = normalizePhoneForWhatsApp(widget.listing.phone);
    final url = Uri.parse('https://wa.me/$cleanedPhone');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  Future<void> callSeller() async {
    if (widget.listing.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone number is missing')),
      );
      return;
    }

    final url = Uri.parse('tel:${widget.listing.phone.trim()}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void openChat() {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final listing = widget.listing;
    final buyerId = me.uid;
    final sellerId = listing.userId;
    final chatId = '${listing.id}_$buyerId';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          listingId: listing.id,
          listingTitle: listing.title,
          listingImage: listing.galleryImages.isEmpty
              ? ''
              : listing.galleryImages.first,
          buyerId: buyerId,
          sellerId: sellerId,
          buyerName: me.email ?? 'Buyer',
          sellerName: listing.sellerName.isEmpty
              ? 'Seller'
              : listing.sellerName,
        ),
      ),
    );
  }

  Future<void> reportAd() async {
    final reasons = [
      'Spam or scam',
      'Prohibited item',
      'Wrong category',
      'Fraudulent / fake',
      'Other',
    ];
    String selected = reasons.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Report this ad'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return RadioGroup<String>(
                groupValue: selected,
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selected = value);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reasons
                      .map(
                        (r) => RadioListTile<String>(
                          title: Text(r),
                          value: r,
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('reports').add({
      'listingId': widget.listing.id,
      'listingTitle': widget.listing.title,
      'reason': selected,
      'reporterId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'createdAt': Timestamp.now(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks, your report was submitted')),
    );
  }

  Future<void> openMap() async {
    final listing = widget.listing;
    if (!listing.hasCoordinates) return;

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${listing.latitude},${listing.longitude}',
    );

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the map')));
    }
  }

  void openSellerProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProfileScreen(
          sellerId: widget.listing.userId,
          sellerName: widget.listing.sellerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final images = listing.galleryImages;
    final me = FirebaseAuth.instance.currentUser;
    final isOwnAd = me != null && me.uid == listing.userId;
    final posted = timeAgo(listing.createdAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(listing.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report ad',
            onPressed: reportAd,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (images.isNotEmpty) ...[
              SizedBox(
                height: isPhone(context) ? 230 : 280,
                width: double.infinity,
                child: PageView.builder(
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => currentImage = i),
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        images[index],
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.image, size: 80),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              if (images.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) {
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == currentImage
                            ? kPakGreen
                            : Colors.grey.shade400,
                      ),
                    );
                  }),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Text(
              listing.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$currencySymbol ${listing.price}',
              style: const TextStyle(
                fontSize: 24,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (posted.isNotEmpty)
                  _IconText(icon: Icons.access_time, text: posted),
                _IconText(
                  icon: Icons.remove_red_eye,
                  text: '${listing.views} views',
                ),
                if (listing.condition.isNotEmpty)
                  _IconText(icon: Icons.verified, text: listing.condition),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _IconText(
                    icon: Icons.location_on,
                    text: [
                      listing.city,
                      listing.location,
                    ].where((e) => e.isNotEmpty).join(', '),
                  ),
                ),
                if (listing.hasCoordinates)
                  TextButton.icon(
                    onPressed: openMap,
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('View on map'),
                  ),
              ],
            ),
            if (listing.category.isNotEmpty) ...[
              const SizedBox(height: 8),
              _IconText(
                icon: Icons.category,
                text: listing.subcategory.isEmpty
                    ? listing.category
                    : '${listing.category} • ${listing.subcategory}',
              ),
            ],
            const Divider(height: 32),
            // Seller row
            InkWell(
              onTap: openSellerProfile,
              child: StreamBuilder<DocumentSnapshot>(
                stream: listing.userId.isEmpty
                    ? null
                    : FirebaseFirestore.instance
                          .collection('users')
                          .doc(listing.userId)
                          .snapshots(),
                builder: (context, snap) {
                  final data =
                      snap.data?.data() as Map<String, dynamic>? ?? {};
                  final count =
                      (data['ratingCount'] as num?)?.toInt() ?? 0;
                  final sum = (data['ratingSum'] as num?)?.toDouble() ?? 0;
                  final avg = count > 0 ? sum / count : 0.0;
                  final verified = data['verified'] == true;

                  return Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: kPakGreen,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    listing.sellerName.isEmpty
                                        ? 'Seller'
                                        : listing.sellerName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (verified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified,
                                    size: 16,
                                    color: kPakGreen,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            StarRating(rating: avg, count: count, size: 14),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 32),
            const Text(
              'Description',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              listing.description.isNotEmpty
                  ? listing.description
                  : 'No description provided.',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            const _SafetyTips(),
            const SizedBox(height: 24),
            if (!isOwnAd) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: callSeller,
                      icon: const Icon(Icons.phone),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: openWhatsApp,
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: openChat,
                  icon: const Icon(Icons.message),
                  label: const Text('Chat with Seller'),
                ),
              ),
            ] else
              const Center(
                child: Text(
                  'This is your ad',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: TextStyle(color: Colors.grey[800])),
        ),
      ],
    );
  }
}

class _SafetyTips extends StatelessWidget {
  const _SafetyTips();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade50,
      child: const ExpansionTile(
        leading: Icon(Icons.shield_outlined, color: Colors.amber),
        title: Text('Safety tips'),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '• Meet in a public place during the day.\n'
              '• Inspect the item before you pay.\n'
              '• Never send money or a deposit in advance.\n'
              '• Avoid sharing personal/banking details.\n'
              '• Report suspicious ads using the flag icon.',
              style: TextStyle(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seller profile + reviews
// ---------------------------------------------------------------------------

/// Star-picker + text dialog for rating a seller. No-op if not signed in or
/// reviewing yourself.
Future<void> showReviewDialog(BuildContext context, String sellerId) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null || me.uid == sellerId) return;

  int rating = 5;
  final textController = TextEditingController();

  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Rate this seller'),
        content: StatefulBuilder(
          builder: (context, setS) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 1; i <= 5; i++)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          i <= rating ? Icons.star : Icons.star_border,
                          color: kGold,
                          size: 36,
                        ),
                        onPressed: () => setS(() => rating = i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Your review (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      );
    },
  );

  if (submitted == true) {
    try {
      await submitSellerReview(
        sellerId: sellerId,
        rating: rating,
        text: textController.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your review!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not submit review: $e')));
      }
    }
  }
}

class ReviewsScreen extends StatelessWidget {
  final String sellerId;
  final String sellerName;

  const ReviewsScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
  });

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    final canReview = me != null && me.uid != sellerId;

    return Scaffold(
      appBar: AppBar(title: Text('Reviews · $sellerName')),
      floatingActionButton: canReview
          ? FloatingActionButton.extended(
              onPressed: () => showReviewDialog(context, sellerId),
              icon: const Icon(Icons.rate_review),
              label: const Text('Write'),
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(sellerId)
            .collection('reviews')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final reviews = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final at =
                  ((a.data() as Map)['createdAt'] as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              final bt =
                  ((b.data() as Map)['createdAt'] as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              return bt.compareTo(at);
            });

          if (reviews.isEmpty) {
            return const Center(
              child: Text(
                'No reviews yet',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final r = reviews[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r['reviewerName']?.toString() ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            timeAgo(r['createdAt'] as Timestamp?),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      StarRating(
                        rating: (r['rating'] as num?)?.toDouble() ?? 0,
                        size: 16,
                      ),
                      if ((r['text']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(r['text'].toString()),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SellerProfileScreen extends StatelessWidget {
  final String sellerId;
  final String sellerName;

  const SellerProfileScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seller Profile')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(sellerId)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
              String memberSince = '';
              final created = data['createdAt'];
              if (created is Timestamp) {
                final d = created.toDate();
                memberSince = 'Member since ${d.month}/${d.year}';
              }
              final count = (data['ratingCount'] as num?)?.toInt() ?? 0;
              final sum = (data['ratingSum'] as num?)?.toDouble() ?? 0;
              final avg = count > 0 ? sum / count : 0.0;
              final verified = data['verified'] == true;
              final me = FirebaseAuth.instance.currentUser;
              final isSelf = me != null && me.uid == sellerId;

              return Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 32,
                            backgroundColor: kPakGreen,
                            child: Icon(
                              Icons.person,
                              size: 36,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        sellerName.isEmpty
                                            ? 'Seller'
                                            : sellerName,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (verified) ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.verified,
                                        size: 18,
                                        color: kPakGreen,
                                      ),
                                    ],
                                  ],
                                ),
                                if (memberSince.isNotEmpty)
                                  Text(
                                    memberSince,
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                const SizedBox(height: 6),
                                StarRating(rating: avg, count: count, size: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (!isSelf) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    showReviewDialog(context, sellerId),
                                icon: const Icon(Icons.rate_review),
                                label: const Text('Write a review'),
                              ),
                            ),
                            if (count > 0) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReviewsScreen(
                                        sellerId: sellerId,
                                        sellerName: sellerName,
                                      ),
                                    ),
                                  ),
                                  child: Text('See $count reviews'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ads by this seller',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('listings')
                  .where('userId', isEqualTo: sellerId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final listings = snapshot.data!.docs
                    .map((d) => Listing.fromDoc(d))
                    .toList()
                  ..sort((a, b) {
                    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                    return bt.compareTo(at);
                  });

                if (listings.isEmpty) {
                  return const Center(
                    child: Text(
                      'No ads from this seller',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: listings
                      .map((listing) => ListingCard(listing: listing))
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favorites')),
        body: const Center(
          child: Text(
            'Please log in to see favorites',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('favorites')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading favorites: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No favorites yet',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return ListingCard(listing: Listing.fromDoc(docs[index]));
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Seller Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 44,
                      backgroundColor: kPakGreen,
                      child: Icon(
                        Icons.person,
                        size: 50,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.email ?? 'Anonymous user',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'User ID: ${user?.uid ?? 'Unknown'}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    if (!(user?.isAnonymous ?? true)) ...[
                      const SizedBox(height: 10),
                      if (user?.emailVerified ?? false)
                        const Chip(
                          avatar: Icon(
                            Icons.verified,
                            color: kPakGreen,
                            size: 18,
                          ),
                          label: Text('Verified'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await user!.sendEmailVerification();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Verification email sent. Verify, then '
                                      'log out and back in to get your badge.',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not send: $e')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.mark_email_read),
                          label: const Text('Verify email'),
                        ),
                    ],
                    if (user?.isAnonymous ?? false) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'You are browsing as a guest. Log in to keep your ads, '
                        'favorites and chats across devices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SavedSearchesScreen()),
              ),
              icon: const Icon(Icons.bookmark),
              label: const Text('Saved Searches'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                favoriteListings.clear();
                await FirebaseAuth.instance.signOut();
                // AuthGate listens to authStateChanges and shows the login screen.
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chats')),
        body: const Center(
          child: Text(
            'Please log in to see your chats',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading chats: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final at =
                  ((a.data() as Map<String, dynamic>)['lastTime']
                          as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              final bt =
                  ((b.data() as Map<String, dynamic>)['lastTime']
                          as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              return bt.compareTo(at);
            });

          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'No chats yet. Message a seller to start one.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final data = chats[index].data() as Map<String, dynamic>;
              final isBuyer = data['buyerId'] == uid;
              final otherName = isBuyer
                  ? (data['sellerName']?.toString() ?? 'Seller')
                  : (data['buyerName']?.toString() ?? 'Buyer');
              final listingImage = data['listingImage']?.toString() ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                leading: listingImage.isEmpty
                    ? const CircleAvatar(child: Icon(Icons.image))
                    : CircleAvatar(
                        backgroundImage: NetworkImage(listingImage),
                      ),
                title: Text(otherName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['listingTitle']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      data['lastMessage']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                isThreeLine: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        chatId: data['chatId']?.toString() ?? chats[index].id,
                        listingId: data['listingId']?.toString() ?? '',
                        listingTitle: data['listingTitle']?.toString() ?? '',
                        listingImage: listingImage,
                        buyerId: data['buyerId']?.toString() ?? '',
                        sellerId: data['sellerId']?.toString() ?? '',
                        buyerName: data['buyerName']?.toString() ?? 'Buyer',
                        sellerName: data['sellerName']?.toString() ?? 'Seller',
                      ),
                    ),
                  );
                },
              ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String listingId;
  final String listingTitle;
  final String listingImage;
  final String buyerId;
  final String sellerId;
  final String buyerName;
  final String sellerName;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.listingId,
    required this.listingTitle,
    required this.listingImage,
    required this.buyerId,
    required this.sellerId,
    required this.buyerName,
    required this.sellerName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();

  DocumentReference get chatRef =>
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId);

  Future<void> sendMessage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final text = messageController.text.trim();
    if (uid == null || text.isEmpty) return;

    messageController.clear();

    await chatRef.set({
      'chatId': widget.chatId,
      'listingId': widget.listingId,
      'listingTitle': widget.listingTitle,
      'listingImage': widget.listingImage,
      'buyerId': widget.buyerId,
      'sellerId': widget.sellerId,
      'buyerName': widget.buyerName,
      'sellerName': widget.sellerName,
      'participants': [widget.buyerId, widget.sellerId],
      'lastMessage': text,
      'lastTime': Timestamp.now(),
    }, SetOptions(merge: true));

    await chatRef.collection('messages').add({
      'senderId': uid,
      'text': text,
      'createdAt': Timestamp.now(),
    });
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final otherName = widget.buyerId == uid
        ? widget.sellerName
        : widget.buyerName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(otherName),
            Text(
              widget.listingTitle,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: chatRef
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Say hello 👋',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data =
                        messages[index].data() as Map<String, dynamic>;
                    final isMine = data['senderId'] == uid;

                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        decoration: BoxDecoration(
                          color: isMine ? kPakGreen : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          data['text']?.toString() ?? '',
                          style: TextStyle(
                            color: isMine ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: kPakGreen,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
