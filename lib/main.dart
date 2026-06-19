import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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

  runApp(const PakBazarApp());
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Currency shown across the app (Pakistani Rupee).
const String currencySymbol = 'Rs';

/// Formats a price string with thousands separators, e.g. "4250000" ->
/// "Rs 4,250,000". Non-numeric values (e.g. "Negotiable") are shown as-is.
String formatPrice(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
  final value = double.tryParse(cleaned);
  if (value == null || cleaned.isEmpty) {
    return raw.trim().isEmpty ? currencySymbol : '$currencySymbol ${raw.trim()}';
  }
  final intPart = value.truncate();
  final digits = intPart.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  var out = buf.toString();
  if (value != intPart.toDouble()) {
    out += (value - intPart).toStringAsFixed(2).substring(1);
  }
  return '$currencySymbol $out';
}

/// Emails granted admin access (also enforced in Firestore rules via the
/// auth token email). Add more to expand the admin team.
const List<String> adminEmails = ['ahmednawaz993@gmail.com'];

bool isAdminUser() =>
    adminEmails.contains(FirebaseAuth.instance.currentUser?.email);

/// Price with an optional unit suffix, e.g. "Rs 250 / kg".
String priceLabel(Listing l) =>
    formatPrice(l.price) + (l.unit.isEmpty ? '' : ' / ${l.unit}');

/// Paid promotion packages (seller pays to Feature an ad).
class PromoPackage {
  final String name;
  final int days;
  final int price;
  const PromoPackage(this.name, this.days, this.price);
}

const List<PromoPackage> promoPackages = [
  PromoPackage('Featured · 7 days', 7, 500),
  PromoPackage('Featured · 15 days', 15, 900),
  PromoPackage('Featured · 30 days', 30, 1500),
];

/// Creates a pending promotion order. An admin approves it (after payment),
/// which sets the ad Featured with an expiry.
Future<void> createPromotionOrder(Listing listing, PromoPackage pkg) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await FirebaseFirestore.instance.collection('promotions').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'sellerId': user.uid,
    'sellerName': user.email ?? '',
    'package': pkg.name,
    'days': pkg.days,
    'price': pkg.price,
    'status': 'pending',
    'createdAt': Timestamp.now(),
  });
}

/// Bottom sheet to choose a promotion package for a listing.
Future<void> showPromoteSheet(BuildContext context, Listing listing) async {
  await showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Promote your ad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Get more views with a FEATURED badge and top placement.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            for (final p in promoPackages)
              ListTile(
                leading: const Icon(Icons.star, color: kGold),
                title: Text(p.name),
                trailing: Text(
                  formatPrice(p.price.toString()),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTap: () async {
                  await createPromotionOrder(listing, p);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Promotion requested — your ad will be Featured once '
                          'payment is approved.',
                        ),
                      ),
                    );
                  }
                },
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Payment via bank transfer / JazzCash, approved by admin. '
                'Automated card/wallet checkout coming soon.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Platform commission taken on each successful on-platform deal.
const double commissionRate = 0.02; // 2%

/// Creates a buy order for a listing. Commission (2%) is recorded so the
/// platform can take its cut once gateway payments go live (Phase 2).
Future<void> createOrder(Listing listing) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final amount = parsePrice(listing.price);
  final commission = amount * commissionRate;
  await FirebaseFirestore.instance.collection('orders').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'listingImage':
        listing.galleryImages.isEmpty ? '' : listing.galleryImages.first,
    'sellerId': listing.userId,
    'sellerName': listing.sellerName,
    'buyerId': user.uid,
    'buyerName': user.email ?? 'Buyer',
    'amount': amount,
    'commission': commission,
    'sellerPayout': amount - commission,
    'status': 'pending_payment',
    'createdAt': Timestamp.now(),
  });
}

/// Confirmation sheet for "Buy now".
Future<void> showBuyNowSheet(BuildContext context, Listing listing) async {
  await showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Confirm purchase',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(listing.title)),
                  Text(
                    priceLabel(listing),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'You pay',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    priceLabel(listing),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kPakGreen,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Online payment is coming soon. Placing an order notifies the '
                'seller so you can arrange a safe handover. Track it in '
                'Profile → My Orders.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  await createOrder(listing);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Order placed! See it in Profile → My Orders.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Place order'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

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

/// Friendly empty-state placeholder (icon + message) for screens shown over
/// the green background.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
  'Adilpur',
  'Ahmadpur East',
  'Akora Khattak',
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
  'Bhera',
  'Bhimber',
  'Bhiria',
  'Bostan',
  'Burewala',
  'Chak Azam',
  'Chak Jhumra',
  'Chakwal',
  'Chaman',
  'Charsadda',
  'Chichawatni',
  'Chilas',
  'Chiniot',
  'Chishtian',
  'Chitral',
  'Choa Saidan Shah',
  'Chuharkana',
  'Chunian',
  'Dadu',
  'Dadyal',
  'Daggar',
  'Daharki',
  'Dalbandin',
  'Daska',
  'Daud Khel',
  'Depalpur',
  'Dera Allah Yar',
  'Dera Bugti',
  'Dera Ghazi Khan',
  'Dera Ismail Khan',
  'Dera Murad Jamali',
  'Digri',
  'Dinga',
  'Dir',
  'Dokri',
  'Dunga Bunga',
  'Dunyapur',
  'Faisalabad',
  'Fort Abbas',
  'Fortabbas',
  'Forward Kahuta',
  'Gahkuch',
  'Gambat',
  'Garhi Khairo',
  'Ghotki',
  'Gilgit',
  'Gojra',
  'Gujar Khan',
  'Gujranwala',
  'Gujrat',
  'Gupis',
  'Gwadar',
  'Hadali',
  'Hafizabad',
  'Hajira',
  'Hala',
  'Hangu',
  'Haripur',
  'Haroonabad',
  'Hasilpur',
  'Hattian Bala',
  'Haveli Lakha',
  'Hub',
  'Hujra Shah Muqeem',
  'Hunza',
  'Hyderabad',
  'Isa Khel',
  'Islamabad',
  'Islamkot',
  'Jacobabad',
  'Jahanian',
  'Jalalpur Jattan',
  'Jalalpur Pirwala',
  'Jampur',
  'Jamshoro',
  'Jand',
  'Jaranwala',
  'Jatoi',
  'Jhang',
  'Jhelum',
  'Jiwani',
  'Kabirwala',
  'Kahror Pakka',
  'Kahuta',
  'Kalabagh',
  'Kalat',
  'Kallar Kahar',
  'Kallar Syedan',
  'Kamalia',
  'Kamar Mushani',
  'Kamoke',
  'Kandhkot',
  'Kandiaro',
  'Karachi',
  'Karak',
  'Kashmore',
  'Kasur',
  'Khairpur',
  'Khairpur Mirs',
  'Khairpur Nathan Shah',
  'Khanewal',
  'Khanpur',
  'Khaplu',
  'Kharan',
  'Kharian',
  'Khipro',
  'Khuiratta',
  'Khushab',
  'Khuzdar',
  'Kohat',
  'Kohlu',
  'Kot Addu',
  'Kot Diji',
  'Kot Momin',
  'Kotli',
  'Kotli Loharan',
  'Kotli Sattian',
  'Kotri',
  'Kuchlak',
  'Kulachi',
  'Kunri',
  'Lachi',
  'Lahore',
  'Lakhi',
  'Lakki Marwat',
  'Lalamusa',
  'Larkana',
  'Lasbela',
  'Layyah',
  'Liaquatpur',
  'Lodhran',
  'Loralai',
  'Mach',
  'Mailsi',
  'Malakand',
  'Mamu Kanjan',
  'Mananwala',
  'Mandi Bahauddin',
  'Mansehra',
  'Mardan',
  'Mastung',
  'Matiari',
  'Mehar',
  'Mehrabpur',
  'Mian Channu',
  'Mianwali',
  'Minchinabad',
  'Mingora (Swat)',
  'Mirpur (AJK)',
  'Mirpur Khas',
  'Mirpur Mathelo',
  'Mithi',
  'Moro',
  'Multan',
  'Muridke',
  'Murree',
  'Muslim Bagh',
  'Muzaffarabad',
  'Muzaffargarh',
  'Nagar',
  'Nankana Sahib',
  'Narowal',
  'Naukot',
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
  'Phalia',
  'Pind Dadan Khan',
  'Pindi Bhattian',
  'Pir Mahal',
  'Pishin',
  'Qadirpur',
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
  'Sahianwala',
  'Sahiwal',
  'Sakrand',
  'Salehpat',
  'Sambrial',
  'Sanghar',
  'Sangla Hill',
  'Sargodha',
  'Sehnsa',
  'Sehwan',
  'Serai Naurang',
  'Shabqadar',
  'Shahdadkot',
  'Shahdadpur',
  'Shakargarh',
  'Sharaqpur',
  'Sheikhupura',
  'Shikarpur',
  'Shorkot',
  'Shujabad',
  'Sialkot',
  'Sibi',
  'Sillanwali',
  'Sinjhoro',
  'Skardu',
  'Sohbatpur',
  'Sukheke Mandi',
  'Sukkur',
  'Surab',
  'Swabi',
  'Talagang',
  'Tandlianwala',
  'Tando Adam',
  'Tando Allahyar',
  'Tando Bago',
  'Tando Muhammad Khan',
  'Tangi',
  'Tangwani',
  'Tank',
  'Taunsa',
  'Taxila',
  'Thatta',
  'Thul',
  'Timergara',
  'Toba Tek Singh',
  'Tret',
  'Turbat',
  'Ubaro',
  'Ubauro',
  'Umerkot',
  'Usta Mohammad',
  'Vehari',
  'Wah Cantonment',
  'Wazirabad',
  'Yasin',
  'Yazman',
  'Zhob',
  'Ziarat',
];

const List<String> itemConditions = ['New', 'Used'];

/// Optional pricing units (for food/grocery and bulk sellers). 'None' = blank.
const List<String> pricingUnits = [
  'None',
  'kg',
  'gram',
  'dozen',
  'piece',
  'plate',
  'litre',
  'pack',
  'box',
  'person',
  'hour',
  'day',
  'month',
];

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
    title: 'Food & Grocery',
    icon: Icons.storefront,
    subcategories: [
      'Restaurants',
      'Supermarkets',
      'Grocery Stores',
      'Meat Shops',
      'Fruit & Vegetables',
      'Bakery & Sweets',
      'Dairy & Eggs',
      'Catering',
      'Home Kitchen',
    ],
  ),
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
  String unit; // pricing unit e.g. 'kg', 'dozen', 'plate' (optional)
  bool deliveryAvailable;
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
      'unit': unit,
      'deliveryAvailable': deliveryAvailable,
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

class PakBazarApp extends StatelessWidget {
  const PakBazarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PakBazar',
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kPakGreen, Color(0xFF0B6E3D)],
          ),
        ),
        child: Center(
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
                      'PakBazar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: kPakGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pakistan ka apna online bazaar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kPakGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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

/// A "SOLD" overlay for sold listings. Must be placed inside a Stack.
class SoldTag extends StatelessWidget {
  const SoldTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: -0.14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'SOLD',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
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
                    if (listing.isSold) const SoldTag(),
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
                      priceLabel(listing),
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
  /// Category to open on tap; empty/null opens Post Ad.
  final String? category;
  /// If set, tapping opens this seller's storefront (business banner ads).
  final String? sellerId;

  const PromoBannerData({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.colors,
    this.category,
    this.sellerId,
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

  // Default banners, used until/unless custom ones are configured in the
  // `banners` Firestore collection (each pointing to a Storage image).
  static const _defaultBanners = <PromoBannerData>[
    PromoBannerData(
      title: 'Cars & more',
      subtitle: 'Explore the best Motors deals',
      image:
          'https://images.unsplash.com/photo-1503376780353-7e6692767b70?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
      category: 'Motors',
    ),
    PromoBannerData(
      title: 'Find your home',
      subtitle: 'Browse Properties across Pakistan',
      image:
          'https://images.unsplash.com/photo-1560518883-ce09059eeffa?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
      category: 'Properties',
    ),
    PromoBannerData(
      title: 'Latest mobiles',
      subtitle: 'Phones, tablets & gadgets',
      image:
          'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
      category: 'Mobiles & Tablets',
    ),
    PromoBannerData(
      title: 'Sell faster',
      subtitle: 'Post your ad free in 2 minutes',
      image:
          'https://images.unsplash.com/photo-1556742502-ec7c0e9f34b1?auto=format&fit=crop&w=900&q=70',
      colors: [kPakGreen, kPakGreenLight],
      category: null,
    ),
  ];

  List<PromoBannerData> _banners = _defaultBanners;

  @override
  void initState() {
    super.initState();
    _loadBanners();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % _banners.length,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Loads custom banners from Firestore (`banners` where active == true),
  /// falling back to the defaults if none are configured.
  Future<void> _loadBanners() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('banners')
          .where('active', isEqualTo: true)
          .get();
      final docs = snap.docs.toList()
        ..sort(
          (a, b) => ((a.data()['order'] as num?) ?? 0)
              .compareTo((b.data()['order'] as num?) ?? 0),
        );
      if (docs.isNotEmpty && mounted) {
        setState(() {
          _banners = docs.map((d) {
            final m = d.data();
            return PromoBannerData(
              title: m['title']?.toString() ?? '',
              subtitle: m['subtitle']?.toString() ?? '',
              image: m['imageUrl']?.toString() ?? '',
              colors: const [kPakGreen, kPakGreenLight],
              category: m['category']?.toString(),
              sellerId: m['sellerId']?.toString(),
            );
          }).toList();
        });
      }
    } catch (_) {
      // Keep defaults on any error.
    }
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
                    onTap: () {
                      final sid = b.sellerId;
                      final cat = b.category;
                      final Widget dest;
                      if (sid != null && sid.isNotEmpty) {
                        dest = SellerProfileScreen(
                          sellerId: sid,
                          sellerName: b.title,
                        );
                      } else if (cat != null && cat.isNotEmpty && cat != 'All') {
                        dest = CategoryScreen(title: cat);
                      } else {
                        dest = const AddListingScreen();
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => dest),
                      );
                    },
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

/// Grey placeholder shown in the feed grid while ads load.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Container(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 16, width: 90, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: double.infinity,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 6),
                Container(height: 10, width: 70, color: Colors.grey.shade200),
              ],
            ),
          ),
        ],
      ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  if (l.isSold) const SoldTag(),
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
                    priceLabel(l),
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
                  if (l.condition.isNotEmpty && l.condition != 'N/A') ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: l.condition == 'New'
                            ? Colors.green.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l.condition,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: l.condition == 'New'
                              ? Colors.green.shade800
                              : Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                  if (l.deliveryAvailable) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: const [
                        Icon(
                          Icons.delivery_dining,
                          size: 13,
                          color: kPakGreen,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'Delivery',
                          style: TextStyle(
                            fontSize: 10,
                            color: kPakGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
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

/// Full grid of every category.
class AllCategoriesScreen extends StatelessWidget {
  const AllCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cats = appCategories.where((c) => c.title != 'All').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('All Categories')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.95,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: cats.length,
        itemBuilder: (context, i) {
          final c = cats[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CategoryScreen(title: c.title)),
            ),
            child: Card(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: kPakGreen.withValues(alpha: 0.12),
                    child: Icon(c.icon, color: kPakGreen, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      c.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Home rail of paid Featured Businesses (admin-approved). Hidden when empty.
class FeaturedBusinessesRail extends StatelessWidget {
  const FeaturedBusinessesRail({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('featuredBusiness', isEqualTo: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.storefront, color: kPakGreen, size: 22),
                  SizedBox(width: 6),
                  Text(
                    'Featured Businesses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final name = d['businessName']?.toString() ?? 'Business';
                  final tagline = d['tagline']?.toString() ?? '';
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SellerProfileScreen(
                          sellerId: docs[i].id,
                          sellerName: name,
                        ),
                      ),
                    ),
                    child: Container(
                      width: 160,
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kGold, width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Builder(
                            builder: (context) {
                              final logo = d['logoUrl']?.toString() ?? '';
                              return CircleAvatar(
                                radius: 28,
                                backgroundColor: kPakGreen.withValues(
                                  alpha: 0.12,
                                ),
                                backgroundImage: logo.isNotEmpty
                                    ? NetworkImage(logo)
                                    : null,
                                child: logo.isEmpty
                                    ? const Icon(
                                        Icons.storefront,
                                        color: kPakGreen,
                                        size: 30,
                                      )
                                    : null,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (tagline.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              tagline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  String searchQuery = '';
  String homeCity = 'All Pakistan';
  String homeSort = 'Newest';
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
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          initialQuery: query,
          // Scope search to the city chosen in the home location bar.
          initialCity: homeCity == 'All Pakistan' ? null : homeCity,
        ),
      ),
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
              // Featured first, then by the chosen sort.
              if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
              switch (homeSort) {
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

          if (homeCity != 'All Pakistan') {
            listings =
                listings.where((l) => l.city == homeCity).toList();
          }
          final featured = listings.where((l) => l.isFeatured).toList();
          final topDeals =
              listings.where((l) => !l.isSold && l.views > 0).toList()
                ..sort((a, b) => b.views.compareTo(a.views));
          final topDealsList = topDeals.take(10).toList();

          return RefreshIndicator(
            color: kPakGreen,
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 600));
              if (mounted) setState(() {});
            },
            child: CustomScrollView(
              slivers: [
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: kPakGreen,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(30),
                    child: TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) => openSearch(v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Find cars, mobiles, property and more',
                        prefixIcon: const Icon(Icons.search, color: kPakGreen),
                        suffixIcon: Container(
                          margin: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: kPakGreen,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () =>
                                openSearch(searchController.text.trim()),
                          ),
                        ),
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
                child: Container(
                  margin: const EdgeInsets.fromLTRB(8, 10, 8, 2),
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                        child: Row(
                          children: [
                            const Text(
                              'Browse categories',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AllCategoriesScreen(),
                                ),
                              ),
                              child: const Text('See all'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 100,
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
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const CategoryScreen(title: 'Food & Grocery'),
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF7043), Color(0xFFE53935)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.restaurant, color: Colors.white, size: 34),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order Food & Groceries',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Restaurants, fresh produce, meat & more',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: PromoCarousel(),
                ),
              ),
              const SliverToBoxAdapter(child: FeaturedBusinessesRail()),
              if (topDealsList.length >= 3)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              color: Colors.deepOrange,
                              size: 22,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Top Deals',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Most viewed',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 218,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          itemCount: topDealsList.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              width: 165,
                              child: FeedAdCard(listing: topDealsList[i]),
                            ),
                          ),
                        ),
                      ),
                    ],
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recommended for you',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        initialValue: homeSort,
                        onSelected: (v) => setState(() => homeSort = v),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'Newest', child: Text('Newest')),
                          PopupMenuItem(
                            value: 'Price: Low to High',
                            child: Text('Price: Low to High'),
                          ),
                          PopupMenuItem(
                            value: 'Price: High to Low',
                            child: Text('Price: High to Low'),
                          ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort, size: 18, color: Colors.grey[700]),
                            const SizedBox(width: 4),
                            Text(
                              homeSort == 'Newest'
                                  ? 'Newest'
                                  : (homeSort == 'Price: Low to High'
                                        ? 'Price ↑'
                                        : 'Price ↓'),
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!snapshot.hasData)
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
                      (context, i) => const _SkeletonCard(),
                      childCount: cols * 3,
                    ),
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
            ),
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
        const NotificationBell(),
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
  final String? initialCity;

  const SearchScreen({super.key, this.initialQuery = '', this.initialCity});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ListingsBrowser(
        initialQuery: initialQuery,
        initialCity: initialCity,
      ),
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
          listing.city.toLowerCase().contains(query) ||
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
                  ? const EmptyState(
                      icon: Icons.search_off,
                      title: 'No listings found',
                      subtitle: 'Try a different search or adjust your filters.',
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
                  if (listing.isSold) const SoldTag(),
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
                    priceLabel(listing),
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
  String selectedUnit = 'None';
  bool deliveryAvailable = false;
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
        'unit': selectedUnit == 'None' ? '' : selectedUnit,
        'deliveryAvailable': deliveryAvailable,
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
                      child: FutureBuilder<Uint8List>(
                        future: selectedImages[index].readAsBytes(),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return Container(
                              width: 90,
                              height: 90,
                              color: Colors.grey.shade300,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          return Image.memory(
                            snap.data!,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          );
                        },
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedUnit,
              decoration: const InputDecoration(
                labelText: 'Price unit (optional, e.g. per kg/dozen/plate)',
              ),
              items: pricingUnits
                  .map(
                    (u) => DropdownMenuItem(
                      value: u,
                      child: Text(u == 'None' ? 'None' : 'per $u'),
                    ),
                  )
                  .toList(),
              onChanged: isSubmitting
                  ? null
                  : (value) {
                      if (value != null) setState(() => selectedUnit = value);
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delivery available'),
              subtitle: const Text('Show a delivery badge on your ad'),
              value: deliveryAvailable,
              activeThumbColor: kPakGreen,
              onChanged: isSubmitting
                  ? null
                  : (v) => setState(() => deliveryAvailable = v),
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

/// Seller dashboard: totals across the user's ads + top performers.
class SellerAnalyticsScreen extends StatelessWidget {
  const SellerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .where('userId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ads = snapshot.data!.docs
              .map((d) => Listing.fromDoc(d))
              .toList();
          if (ads.isEmpty) {
            return const EmptyState(
              icon: Icons.bar_chart,
              title: 'No data yet',
              subtitle: 'Post ads to start seeing views and leads.',
            );
          }
          int views = 0, calls = 0, chats = 0, waps = 0, sold = 0;
          for (final a in ads) {
            views += a.views;
            calls += a.calls;
            chats += a.chats;
            waps += a.whatsapps;
            if (a.isSold) sold++;
          }
          final leads = calls + chats + waps;
          final top = [...ads]
            ..sort(
              (a, b) => (b.calls + b.chats + b.whatsapps + b.views).compareTo(
                a.calls + a.chats + a.whatsapps + a.views,
              ),
            );
          final maxViews = ads
              .map((a) => a.views)
              .fold<int>(1, (m, v) => v > m ? v : m);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _statCard(Icons.remove_red_eye, '$views', 'Views'),
                  _statCard(Icons.call, '$calls', 'Calls'),
                  _statCard(Icons.chat, '$chats', 'Chats'),
                  _statCard(Icons.whatshot, '$waps', 'WhatsApp'),
                  _statCard(Icons.trending_up, '$leads', 'Total leads'),
                  _statCard(Icons.inventory_2, '${ads.length}', 'Active ads'),
                  _statCard(Icons.sell, '$sold', 'Sold'),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Top performing ads',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              ...top.take(10).map((a) {
                final l = a.calls + a.chats + a.whatsapps;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title.isEmpty ? '(untitled)' : a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (a.views / maxViews).clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation(kPakGreen),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${a.views} views · $l leads '
                          '(📞 ${a.calls}  💬 ${a.chats}  🟢 ${a.whatsapps})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) {
    return SizedBox(
      width: 108,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: kPakGreen, size: 26),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      appBar: AppBar(
        title: const Text('My Ads'),
        actions: [
          IconButton(
            tooltip: 'Analytics',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SellerAnalyticsScreen()),
            ),
          ),
        ],
      ),
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
            return const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No ads posted yet',
              subtitle: 'Tap the green SELL button to post your first ad.',
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
                    '\n👁 ${listing.views}  📞 ${listing.calls}  '
                    '💬 ${listing.chats}  🟢 ${listing.whatsapps}',
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
                            ? 'Featured'
                            : 'Promote (Feature)',
                        icon: Icon(
                          listing.isFeatured
                              ? Icons.star
                              : Icons.campaign_outlined,
                          color: kGold,
                        ),
                        onPressed: () => showPromoteSheet(context, listing),
                      ),
                      IconButton(
                        tooltip: listing.isSold
                            ? 'Mark as available'
                            : 'Mark as sold',
                        icon: Icon(
                          listing.isSold
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          color: listing.isSold ? Colors.red : Colors.grey,
                        ),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('listings')
                              .doc(listing.id)
                              .update({'isSold': !listing.isSold});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  listing.isSold
                                      ? 'Marked as available'
                                      : 'Marked as sold',
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
  late String selectedUnit;
  late bool deliveryAvailable;
  late String selectedCity;
  double? latitude;
  double? longitude;
  bool isLocating = false;

  final ImagePicker picker = ImagePicker();
  List<XFile> newImages = [];
  bool isSaving = false;

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
    selectedUnit = pricingUnits.contains(widget.listing.unit)
        ? widget.listing.unit
        : 'None';
    deliveryAvailable = widget.listing.deliveryAvailable;
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

  Future<void> pickImages() async {
    final imgs = await picker.pickMultiImage();
    if (imgs.isNotEmpty) setState(() => newImages = imgs);
  }

  Future<List<String>> uploadImages() async {
    final urls = <String>[];
    for (var i = 0; i < newImages.length; i++) {
      final bytes = await newImages[i].readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('listings')
          .child('${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> updateListing() async {
    setState(() => isSaving = true);
    try {
      final data = <String, dynamic>{
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
        'unit': selectedUnit == 'None' ? '' : selectedUnit,
        'deliveryAvailable': deliveryAvailable,
      };
      if (newImages.isNotEmpty) {
        final urls = await uploadImages();
        data['images'] = urls;
        data['imageUrl'] = urls.isNotEmpty ? urls.first : '';
      }
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listing.id)
          .update(data);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => isSaving = false);
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
    final subcategories = categoryByTitle(selectedCategory).subcategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Ad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Photos',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (newImages.isNotEmpty)
                    for (final x in newImages)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FutureBuilder<Uint8List>(
                            future: x.readAsBytes(),
                            builder: (context, snap) => snap.hasData
                                ? Image.memory(
                                    snap.data!,
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 90,
                                    height: 90,
                                    color: Colors.grey.shade300,
                                  ),
                          ),
                        ),
                      )
                  else
                    for (final u in widget.listing.galleryImages)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            u,
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
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isSaving ? null : pickImages,
              icon: const Icon(Icons.add_a_photo),
              label: Text(
                newImages.isEmpty
                    ? 'Change photos'
                    : '${newImages.length} new photo(s) selected',
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedUnit,
              decoration: const InputDecoration(
                labelText: 'Price unit (optional, e.g. per kg/dozen/plate)',
              ),
              items: pricingUnits
                  .map(
                    (u) => DropdownMenuItem(
                      value: u,
                      child: Text(u == 'None' ? 'None' : 'per $u'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => selectedUnit = value);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delivery available'),
              subtitle: const Text('Show a delivery badge on your ad'),
              value: deliveryAvailable,
              activeThumbColor: kPakGreen,
              onChanged: (v) => setState(() => deliveryAvailable = v),
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
              onPressed: isSaving ? null : updateListing,
              child: isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update'),
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

/// Fullscreen, swipeable, pinch-to-zoom image viewer.
class FullScreenGallery extends StatelessWidget {
  final List<String> images;
  final int initialIndex;

  const FullScreenGallery({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: images.length,
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              images[i],
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image,
                color: Colors.white,
                size: 80,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    await _bumpStat('views');
  }

  /// Increments a non-owner lead/stat counter on the listing (best-effort).
  Future<void> _bumpStat(String field) async {
    final id = widget.listing.id;
    if (id.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(id)
          .update({field: FieldValue.increment(1)});
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

    _bumpStat('whatsapps');
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

    _bumpStat('calls');
    final url = Uri.parse('tel:${widget.listing.phone.trim()}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void openChat() {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    _bumpStat('chats');

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

  Future<void> shareAd() async {
    final l = widget.listing;
    final loc = [l.city, l.location].where((e) => e.isNotEmpty).join(', ');
    final text = [
      l.title,
      '${formatPrice(l.price)}${loc.isEmpty ? '' : ' · $loc'}',
      if (l.phone.isNotEmpty) 'Contact: ${l.phone}',
      'See more on PakBazar: https://pakbazar24.com',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ad details copied — paste anywhere to share'),
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
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: shareAd,
          ),
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
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullScreenGallery(
                            images: images,
                            initialIndex: index,
                          ),
                        ),
                      ),
                      child: ClipRRect(
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
            if (listing.isSold)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SOLD',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 3,
                  ),
                ),
              ),
            Text(
              listing.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              priceLabel(listing),
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
                if (listing.deliveryAvailable)
                  const _IconText(
                    icon: Icons.delivery_dining,
                    text: 'Delivery available',
                  ),
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
                                if (data['isBusiness'] == true) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kPakGreen,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'BUSINESS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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
              if (!listing.isSold) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPakGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => showBuyNowSheet(context, listing),
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text(
                      'Buy Now',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => showOfferSheet(context, listing),
                    icon: const Icon(Icons.local_offer_outlined),
                    label: const Text('Make an Offer'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
            _SimilarAds(listing: listing),
            const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal rail of other ads in the same category (excludes this ad).
class _SimilarAds extends StatelessWidget {
  final Listing listing;

  const _SimilarAds({required this.listing});

  @override
  Widget build(BuildContext context) {
    if (listing.category.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('category', isEqualTo: listing.category)
          .limit(12)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final items = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .where((l) => l.id != listing.id)
            .toList()
          ..sort((a, b) {
            final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
            final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
        final shown = items.take(10).toList();
        if (shown.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            const Text(
              'Similar ads',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: shown.length,
                itemBuilder: (context, i) =>
                    HorizontalAdCard(listing: shown[i]),
              ),
            ),
          ],
        );
      },
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
              final isBusiness = data['isBusiness'] == true;
              final businessName = data['businessName']?.toString() ?? '';
              final tagline = data['tagline']?.toString() ?? '';
              final logoUrl = data['logoUrl']?.toString() ?? '';
              final displayName = (isBusiness && businessName.isNotEmpty)
                  ? businessName
                  : (sellerName.isEmpty ? 'Seller' : sellerName);
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
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: kPakGreen,
                            backgroundImage: logoUrl.isNotEmpty
                                ? NetworkImage(logoUrl)
                                : null,
                            child: logoUrl.isEmpty
                                ? Icon(
                                    isBusiness
                                        ? Icons.storefront
                                        : Icons.person,
                                    size: 36,
                                    color: Colors.white,
                                  )
                                : null,
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
                                        displayName,
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
                                    if (isBusiness) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kPakGreen,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'BUSINESS',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (isBusiness && tagline.isNotEmpty)
                                  Text(
                                    tagline,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontStyle: FontStyle.italic,
                                    ),
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
            return const EmptyState(
              icon: Icons.favorite_border,
              title: 'No favorites yet',
              subtitle: 'Tap the heart on any ad to save it here.',
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

/// Lets a signed-in user mark their account as a business (shows a BUSINESS
/// badge on their ads) and set a business name.
class _BusinessAccountTile extends StatefulWidget {
  const _BusinessAccountTile();

  @override
  State<_BusinessAccountTile> createState() => _BusinessAccountTileState();
}

class _BusinessAccountTileState extends State<_BusinessAccountTile> {
  bool isBusiness = false;
  bool loaded = false;
  bool saving = false;
  final nameController = TextEditingController();
  final taglineController = TextEditingController();
  final ImagePicker picker = ImagePicker();
  String? logoUrl;
  bool uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickLogo() async {
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => uploadingLogo = true);
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('business_logos')
          .child('$uid.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => uploadingLogo = false);
    }
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final d = doc.data();
    if (!mounted) return;
    setState(() {
      isBusiness = d?['isBusiness'] == true;
      nameController.text = d?['businessName']?.toString() ?? '';
      taglineController.text = d?['tagline']?.toString() ?? '';
      logoUrl = d?['logoUrl']?.toString();
      loaded = true;
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => saving = true);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'isBusiness': isBusiness,
      'businessName': nameController.text.trim(),
      'tagline': taglineController.text.trim(),
      'logoUrl': logoUrl ?? '',
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Business profile saved')),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    taglineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Sell as a business'),
              subtitle: const Text('Shows a BUSINESS badge on your ads'),
              value: isBusiness,
              activeThumbColor: kPakGreen,
              onChanged: loaded ? (v) => setState(() => isBusiness = v) : null,
            ),
            if (isBusiness) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: kPakGreen.withValues(alpha: 0.12),
                      backgroundImage:
                          (logoUrl != null && logoUrl!.isNotEmpty)
                          ? NetworkImage(logoUrl!)
                          : null,
                      child: (logoUrl == null || logoUrl!.isEmpty)
                          ? const Icon(Icons.storefront, color: kPakGreen)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: uploadingLogo ? null : _pickLogo,
                      icon: uploadingLogo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload),
                      label: Text(uploadingLogo ? 'Uploading…' : 'Upload logo'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Business name'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: taglineController,
                  decoration: const InputDecoration(
                    labelText: 'Tagline (e.g. "Best deals on phones")',
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (loaded && !saving) ? _save : null,
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ),
            if (isBusiness) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      showBusinessAdSheet(context, nameController.text.trim()),
                  icon: const Icon(Icons.campaign, color: kGold),
                  label: const Text('Advertise my business'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BannerAdScreen()),
                  ),
                  icon: const Icon(Icons.view_carousel, color: kGold),
                  label: const Text('Buy a home banner'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kPakGreen, Color(0xFF0B6E3D)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 50, color: kPakGreen),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.email ?? 'Guest user',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
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
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
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
                        style: TextStyle(color: Colors.amberAccent),
                      ),
                    ],
                  ],
                ),
              ),
            if (!(user?.isAnonymous ?? true)) ...[
              const SizedBox(height: 16),
              const _BusinessAccountTile(),
            ],
            if (isAdminUser()) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                ),
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Admin Panel'),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersScreen()),
              ),
              icon: const Icon(Icons.receipt_long),
              label: const Text('My Orders'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OffersScreen()),
              ),
              icon: const Icon(Icons.local_offer),
              label: const Text('Offers'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SavedSearchesScreen()),
              ),
              icon: const Icon(Icons.bookmark),
              label: const Text('Saved Searches'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final url = Uri.parse(
                  'mailto:support@pakbazar.pk?subject=PakBazar Feedback',
                );
                await launchUrl(url, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.help_outline),
              label: const Text('Help & Feedback'),
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
// Make an offer (price negotiation)
// ---------------------------------------------------------------------------

Future<void> createOffer(Listing listing, double amount) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await FirebaseFirestore.instance.collection('offers').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'listingImage':
        listing.galleryImages.isEmpty ? '' : listing.galleryImages.first,
    'askingPrice': parsePrice(listing.price),
    'offerAmount': amount,
    'sellerId': listing.userId,
    'sellerName': listing.sellerName,
    'buyerId': user.uid,
    'buyerName': user.email ?? 'Buyer',
    'status': 'pending',
    'createdAt': Timestamp.now(),
  });
}

Future<void> showOfferSheet(BuildContext context, Listing listing) async {
  final controller = TextEditingController();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Make an offer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Asking price: ${formatPrice(listing.price)}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Your offer (Rs)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final amt = double.tryParse(
                      controller.text.replaceAll(RegExp(r'[^0-9.]'), ''),
                    );
                    if (amt == null || amt <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid amount')),
                      );
                      return;
                    }
                    await createOffer(listing, amt);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Offer sent! Track it in Profile → Offers.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Send offer'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Business advertising
// ---------------------------------------------------------------------------

const List<PromoPackage> businessAdPackages = [
  PromoPackage('Featured Business · 30 days', 30, 3000),
  PromoPackage('Featured Business · 90 days', 90, 8000),
];

/// Creates a pending "featured business" advertising order. Admin approval
/// sets the user's featuredBusiness flag, surfacing them on the home rail.
Future<void> createBusinessPromotion(
  PromoPackage pkg,
  String businessName,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await FirebaseFirestore.instance.collection('promotions').add({
    'type': 'business',
    'userId': user.uid,
    'sellerId': user.uid,
    'businessName': businessName,
    'sellerName': user.email ?? '',
    'listingTitle': businessName.isEmpty ? 'Business' : businessName,
    'package': pkg.name,
    'days': pkg.days,
    'price': pkg.price,
    'status': 'pending',
    'createdAt': Timestamp.now(),
  });
}

Future<void> showBusinessAdSheet(
  BuildContext context,
  String businessName,
) async {
  await showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Advertise your business',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Get a Featured Business spot on the home screen to reach more '
                'buyers across Pakistan.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            for (final p in businessAdPackages)
              ListTile(
                leading: const Icon(Icons.storefront, color: kGold),
                title: Text(p.name),
                trailing: Text(
                  formatPrice(p.price.toString()),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTap: () async {
                  await createBusinessPromotion(p, businessName);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Request sent — your business will be Featured once '
                          'payment is approved.',
                        ),
                      ),
                    );
                  }
                },
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Approved by admin after payment. Automated checkout coming soon.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Orders (direct buy/sell)
// ---------------------------------------------------------------------------

/// Lets a business upload a home-screen banner ad and request a slot.
class BannerAdScreen extends StatefulWidget {
  const BannerAdScreen({super.key});

  @override
  State<BannerAdScreen> createState() => _BannerAdScreenState();
}

class _BannerAdScreenState extends State<BannerAdScreen> {
  final picker = ImagePicker();
  final titleController = TextEditingController();
  final subtitleController = TextEditingController();
  String? imageUrl;
  bool uploading = false;
  bool submitting = false;
  PromoPackage? selected;

  static const bannerPackages = [
    PromoPackage('Home banner · 7 days', 7, 2000),
    PromoPackage('Home banner · 30 days', 30, 6000),
  ];

  @override
  void dispose() {
    titleController.dispose();
    subtitleController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => uploading = true);
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('banners')
          .child('ad_${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (imageUrl == null || selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a banner image and pick a package')),
      );
      return;
    }
    setState(() => submitting = true);
    await FirebaseFirestore.instance.collection('promotions').add({
      'type': 'banner',
      'sellerId': user.uid,
      'userId': user.uid,
      'imageUrl': imageUrl,
      'bannerTitle': titleController.text.trim(),
      'bannerSubtitle': subtitleController.text.trim(),
      'listingTitle': 'Home banner: ${titleController.text.trim()}',
      'sellerName': user.email ?? '',
      'package': selected!.name,
      'days': selected!.days,
      'price': selected!.price,
      'status': 'pending',
      'createdAt': Timestamp.now(),
    });
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Banner request sent — it goes live once approved.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buy a Home Banner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Promote your business with a banner on the home screen.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                AspectRatio(
                  aspectRatio: 16 / 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                      image: imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: imageUrl == null
                        ? const Center(
                            child: Text('Banner preview (≈ 1000×360)'),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: uploading ? null : _pickAndUpload,
                  icon: uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image),
                  label: Text(
                    uploading
                        ? 'Uploading…'
                        : (imageUrl == null
                              ? 'Upload banner image'
                              : 'Change image'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Headline (e.g. "Eid Sale at Ali Mobiles")',
                  ),
                ),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Subtitle (optional)',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choose a package',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                RadioGroup<PromoPackage>(
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  child: Column(
                    children: [
                      for (final p in bannerPackages)
                        RadioListTile<PromoPackage>(
                          value: p,
                          title: Text(p.name),
                          secondary: Text(
                            formatPrice(p.price.toString()),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: submitting ? null : _submit,
                  child: Text(submitting ? 'Sending…' : 'Submit request'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Approved by admin after payment. Automated checkout coming soon.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Orders'),
          bottom: const TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Buying'), Tab(text: 'Selling')],
          ),
        ),
        body: const TabBarView(
          children: [_OrdersList(asSeller: false), _OrdersList(asSeller: true)],
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  final bool asSeller;
  const _OrdersList({required this.asSeller});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const EmptyState(icon: Icons.receipt_long, title: 'Please log in');
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where(asSeller ? 'sellerId' : 'buyerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
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
        if (docs.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long,
            title: 'No orders yet',
            subtitle: asSeller
                ? 'Orders placed on your ads will appear here.'
                : 'Items you buy will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status']?.toString() ?? 'pending_payment';
            final img = d['listingImage']?.toString() ?? '';
            final amount = (d['amount'] as num?)?.toDouble() ?? 0;
            final payout = (d['sellerPayout'] as num?)?.toDouble() ?? 0;
            final (label, color) = switch (status) {
              'completed' => ('Completed', Colors.green),
              'cancelled' => ('Cancelled', Colors.grey),
              _ => ('Pending payment', Colors.orange),
            };
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: img.isEmpty
                              ? Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image),
                                )
                              : Image.network(
                                  img,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 56,
                                    height: 56,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.image),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d['listingTitle']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                asSeller
                                    ? '${d['buyerName'] ?? 'Buyer'}'
                                    : '${d['sellerName'] ?? 'Seller'}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                asSeller
                                    ? 'You receive ${formatPrice(payout.toStringAsFixed(0))} (after 2% fee)'
                                    : formatPrice(amount.toStringAsFixed(0)),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kPakGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (status == 'pending_payment') ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (asSeller)
                            ElevatedButton(
                              onPressed: () async {
                                await docs[i].reference.update({
                                  'status': 'completed',
                                  'completedAt': Timestamp.now(),
                                });
                                final lid = d['listingId']?.toString() ?? '';
                                if (lid.isNotEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('listings')
                                      .doc(lid)
                                      .update({'isSold': true});
                                }
                              },
                              child: const Text('Mark completed'),
                            )
                          else
                            TextButton(
                              onPressed: () => docs[i].reference.update({
                                'status': 'cancelled',
                              }),
                              child: const Text('Cancel'),
                            ),
                        ],
                      ),
                    ],
                    if (status == 'completed' && !asSeller) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => showReviewDialog(
                            context,
                            d['sellerId']?.toString() ?? '',
                          ),
                          icon: const Icon(Icons.star, size: 18),
                          label: const Text('Rate seller'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Offers (price negotiation)
// ---------------------------------------------------------------------------

/// Creates an order from an accepted/countered offer (called by the buyer, so
/// buyerId == auth.uid as the rules require).
Future<void> _orderFromOffer(
  DocumentReference ref,
  Map<String, dynamic> offer,
  double amount,
) async {
  final commission = amount * commissionRate;
  await FirebaseFirestore.instance.collection('orders').add({
    'listingId': offer['listingId'] ?? '',
    'listingTitle': offer['listingTitle'] ?? '',
    'listingImage': offer['listingImage'] ?? '',
    'sellerId': offer['sellerId'] ?? '',
    'sellerName': offer['sellerName'] ?? '',
    'buyerId': offer['buyerId'] ?? '',
    'buyerName': offer['buyerName'] ?? '',
    'amount': amount,
    'commission': commission,
    'sellerPayout': amount - commission,
    'status': 'pending_payment',
    'createdAt': Timestamp.now(),
    'fromOffer': true,
  });
  await ref.update({'status': 'ordered', 'agreedAmount': amount});
}

Future<void> _counterDialog(BuildContext context, DocumentReference ref) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Counter offer'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Your price (Rs)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final amt = double.tryParse(
              controller.text.replaceAll(RegExp(r'[^0-9.]'), ''),
            );
            if (amt == null || amt <= 0) return;
            await ref.update({'status': 'countered', 'counterAmount': amt});
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Send'),
        ),
      ],
    ),
  );
}

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Offers'),
          bottom: const TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Received'), Tab(text: 'Sent')],
          ),
        ),
        body: const TabBarView(
          children: [_OffersList(asSeller: true), _OffersList(asSeller: false)],
        ),
      ),
    );
  }
}

class _OffersList extends StatelessWidget {
  final bool asSeller;
  const _OffersList({required this.asSeller});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const EmptyState(icon: Icons.local_offer, title: 'Please log in');
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('offers')
          .where(asSeller ? 'sellerId' : 'buyerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
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
        if (docs.isEmpty) {
          return EmptyState(
            icon: Icons.local_offer,
            title: 'No offers yet',
            subtitle: asSeller
                ? 'Offers buyers make on your ads appear here.'
                : 'Offers you make will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final ref = docs[i].reference;
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status']?.toString() ?? 'pending';
            final asking = (d['askingPrice'] as num?)?.toDouble() ?? 0;
            final offer = (d['offerAmount'] as num?)?.toDouble() ?? 0;
            final counter = (d['counterAmount'] as num?)?.toDouble();
            final (label, color) = switch (status) {
              'accepted' => ('Accepted', Colors.green),
              'ordered' => ('Deal agreed', Colors.green),
              'countered' => ('Countered', Colors.blue),
              'declined' => ('Declined', Colors.grey),
              'cancelled' => ('Cancelled', Colors.grey),
              _ => ('Pending', Colors.orange),
            };
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d['listingTitle']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Asking ${formatPrice(asking.toStringAsFixed(0))}  ·  '
                      'Offer ${formatPrice(offer.toStringAsFixed(0))}',
                    ),
                    if (counter != null)
                      Text(
                        'Counter: ${formatPrice(counter.toStringAsFixed(0))}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 8),
                    _actions(context, ref, d, status, offer, counter),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _actions(
    BuildContext context,
    DocumentReference ref,
    Map<String, dynamic> d,
    String status,
    double offer,
    double? counter,
  ) {
    final buttons = <Widget>[];
    if (asSeller && status == 'pending') {
      buttons.addAll([
        TextButton(
          onPressed: () => ref.update({'status': 'declined'}),
          child: const Text('Decline'),
        ),
        TextButton(
          onPressed: () => _counterDialog(context, ref),
          child: const Text('Counter'),
        ),
        ElevatedButton(
          onPressed: () =>
              ref.update({'status': 'accepted', 'agreedAmount': offer}),
          child: const Text('Accept'),
        ),
      ]);
    } else if (!asSeller && status == 'pending') {
      buttons.add(
        TextButton(
          onPressed: () => ref.update({'status': 'cancelled'}),
          child: const Text('Cancel'),
        ),
      );
    } else if (!asSeller && status == 'accepted') {
      buttons.add(
        ElevatedButton(
          onPressed: () => _orderFromOffer(ref, d, offer),
          child: Text('Buy at ${formatPrice(offer.toStringAsFixed(0))}'),
        ),
      );
    } else if (!asSeller && status == 'countered' && counter != null) {
      buttons.addAll([
        TextButton(
          onPressed: () => ref.update({'status': 'declined'}),
          child: const Text('Decline'),
        ),
        ElevatedButton(
          onPressed: () => _orderFromOffer(ref, d, counter),
          child: Text('Accept ${formatPrice(counter.toStringAsFixed(0))}'),
        ),
      ]);
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons);
  }
}

// ---------------------------------------------------------------------------
// Admin panel
// ---------------------------------------------------------------------------

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Panel'),
          bottom: const TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            isScrollable: true,
            tabs: [
              Tab(text: 'Reports'),
              Tab(text: 'Promotions'),
              Tab(text: 'Orders'),
              Tab(text: 'All Listings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AdminReportsTab(),
            _AdminPromotionsTab(),
            _AdminOrdersTab(),
            _AdminListingsTab(),
          ],
        ),
      ),
    );
  }
}

Future<void> _openListingById(BuildContext context, String id) async {
  final doc = await FirebaseFirestore.instance
      .collection('listings')
      .doc(id)
      .get();
  if (!context.mounted) return;
  if (!doc.exists) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That ad no longer exists.')),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AdDetailsScreen(listing: Listing.fromDoc(doc)),
    ),
  );
}

class _AdminReportsTab extends StatelessWidget {
  const _AdminReportsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('reports').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
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
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.verified_user,
            title: 'No reports',
            subtitle: 'Reported ads will appear here for review.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final listingId = d['listingId']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['listingTitle']?.toString() ?? '(untitled ad)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reason: ${d['reason'] ?? '—'}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    Text(
                      timeAgo(d['createdAt'] as Timestamp?),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _openListingById(context, listingId),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Open'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              docs[i].reference.delete(),
                          child: const Text('Dismiss'),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () async {
                            if (listingId.isNotEmpty) {
                              await FirebaseFirestore.instance
                                  .collection('listings')
                                  .doc(listingId)
                                  .delete();
                            }
                            await docs[i].reference.delete();
                          },
                          child: const Text('Delete ad'),
                        ),
                      ],
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
}

class _AdminPromotionsTab extends StatelessWidget {
  const _AdminPromotionsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('promotions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final am = a.data() as Map;
            final bm = b.data() as Map;
            final ap = am['status'] == 'pending' ? 0 : 1;
            final bp = bm['status'] == 'pending' ? 0 : 1;
            if (ap != bp) return ap - bp;
            final at =
                (am['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bt =
                (bm['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.campaign,
            title: 'No promotion orders',
            subtitle: 'Seller promotion requests appear here for approval.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status']?.toString() ?? 'pending';
            final pending = status == 'pending';
            final listingId = d['listingId']?.toString() ?? '';
            final days = (d['days'] as num?)?.toInt() ?? 7;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['listingTitle']?.toString() ?? '(untitled ad)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('${d['package']} · ${formatPrice('${d['price']}')}'),
                    Text(
                      'Seller: ${d['sellerName'] ?? ''}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      'Status: $status',
                      style: TextStyle(
                        color: pending
                            ? Colors.orange
                            : (status == 'active' ? Colors.green : Colors.red),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (pending) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _openListingById(context, listingId),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () =>
                                docs[i].reference.update({'status': 'rejected'}),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () async {
                              final until = Timestamp.fromDate(
                                DateTime.now().add(Duration(days: days)),
                              );
                              if (d['type'] == 'business') {
                                final bizUid = d['userId']?.toString() ?? '';
                                if (bizUid.isNotEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(bizUid)
                                      .set({
                                        'featuredBusiness': true,
                                        'featuredBusinessUntil': until,
                                      }, SetOptions(merge: true));
                                }
                              } else if (d['type'] == 'banner') {
                                await FirebaseFirestore.instance
                                    .collection('banners')
                                    .add({
                                      'imageUrl': d['imageUrl'] ?? '',
                                      'title': d['bannerTitle'] ?? '',
                                      'subtitle': d['bannerSubtitle'] ?? '',
                                      'sellerId': d['sellerId'] ?? '',
                                      'category': '',
                                      'order': 99,
                                      'active': true,
                                      'createdAt': Timestamp.now(),
                                      'expiresAt': until,
                                    });
                              } else if (listingId.isNotEmpty) {
                                await FirebaseFirestore.instance
                                    .collection('listings')
                                    .doc(listingId)
                                    .update({
                                      'isFeatured': true,
                                      'featuredUntil': until,
                                    });
                              }
                              await docs[i].reference.update({
                                'status': 'active',
                                'approvedAt': Timestamp.now(),
                              });
                            },
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminOrdersTab extends StatelessWidget {
  const _AdminOrdersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
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
        double revenue = 0;
        int completed = 0;
        for (final d in docs) {
          final m = d.data() as Map;
          if (m['status'] == 'completed') {
            revenue += (m['commission'] as num?)?.toDouble() ?? 0;
            completed++;
          }
        }
        return Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              color: kPakGreen,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('${docs.length}', 'Orders'),
                    _stat('$completed', 'Completed'),
                    _stat(
                      formatPrice(revenue.toStringAsFixed(0)),
                      'Commission',
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long,
                      title: 'No orders yet',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              d['listingTitle']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${d['buyerName']} → ${d['sellerName']}\n'
                              '${formatPrice('${d['amount']}')} · '
                              'fee ${formatPrice('${d['commission']}')} · '
                              '${d['status']}',
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

class _AdminListingsTab extends StatelessWidget {
  const _AdminListingsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No listings',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final l = Listing.fromDoc(docs[i]);
            final imgs = l.galleryImages;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: imgs.isEmpty
                    ? const Icon(Icons.image, size: 36)
                    : Image.network(
                        imgs.first,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.image),
                      ),
                title: Text(
                  l.title.isEmpty ? '(untitled)' : l.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${formatPrice(l.price)} · ${l.sellerName}'
                  '${l.isFeatured ? ' · ★' : ''}${l.isSold ? ' · SOLD' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdDetailsScreen(listing: l),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Toggle Featured',
                      icon: Icon(
                        l.isFeatured ? Icons.star : Icons.star_border,
                        color: kGold,
                      ),
                      onPressed: () => docs[i].reference.update({
                        'isFeatured': !l.isFeatured,
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => docs[i].reference.delete(),
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
}

// ---------------------------------------------------------------------------
// Notification center
// ---------------------------------------------------------------------------

IconData _notificationIcon(String type) {
  switch (type) {
    case 'chat':
      return Icons.chat_bubble_outline;
    case 'order':
      return Icons.receipt_long;
    case 'offer':
      return Icons.local_offer;
    case 'savedSearch':
      return Icons.search;
    default:
      return Icons.notifications;
  }
}

/// Bell with an unread badge for the home app bar.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final open = IconButton(
      icon: const Icon(Icons.notifications_none, color: Colors.white),
      tooltip: 'Notifications',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
    );
    if (uid == null) return open;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          offset: const Offset(-4, 4),
          child: open,
        );
      },
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final col = uid == null
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('notifications');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (col != null)
            TextButton(
              onPressed: () async {
                final unread = await col
                    .where('read', isEqualTo: false)
                    .get();
                final batch = FirebaseFirestore.instance.batch();
                for (final d in unread.docs) {
                  batch.update(d.reference, {'read': true});
                }
                await batch.commit();
              },
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: col == null
          ? const EmptyState(
              icon: Icons.notifications,
              title: 'Please log in',
            )
          : StreamBuilder<QuerySnapshot>(
              stream: col
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.notifications_none,
                    title: 'No notifications yet',
                    subtitle: 'Messages, offers and orders will show up here.',
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final read = d['read'] == true;
                    final type = d['type']?.toString() ?? '';
                    return ListTile(
                      tileColor: read ? null : kPakGreen.withValues(alpha: 0.06),
                      leading: CircleAvatar(
                        backgroundColor: kPakGreen.withValues(alpha: 0.12),
                        child: Icon(_notificationIcon(type), color: kPakGreen),
                      ),
                      title: Text(
                        d['title']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: read
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(d['body']?.toString() ?? ''),
                      trailing: Text(
                        timeAgo(d['createdAt'] as Timestamp?),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      onTap: read
                          ? null
                          : () => docs[i].reference.update({'read': true}),
                    );
                  },
                );
              },
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
            return const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No chats yet',
              subtitle: 'Message a seller from any ad to start a conversation.',
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
