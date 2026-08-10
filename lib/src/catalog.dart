part of '../main.dart';

// Categories, cities, conditions and related lookup data.

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
  // Additional towns (de-duplicated; sorted at display time).
  'Havelian',
  'Dina',
  'Sarai Alamgir',
  'Jauharabad',
  'Quaidabad',
  'Kundian',
  'Khewra',
  'Sohawa',
  'Kunjah',
  'Chawinda',
  'Zafarwal',
  'Eminabad',
  'Ferozewala',
  'Shahkot',
  'Safdarabad',
  'Tulamba',
  'Abdul Hakim',
  'Hassan Abdal',
  'Hazro',
  'Fateh Jang',
  'Pindi Gheb',
  'Daultala',
  'Mandra',
  'Jhawarian',
  'Kot Radha Kishan',
  'Phool Nagar',
  'Sammundri',
  'Tibba Sultanpur',
  'Qadirpur Ran',
  'Ahmadpur Sial',
  '18-Hazari',
  'Takht Bhai',
  'Landi Kotal',
  'Jamrud',
  'Drosh',
  'Chakdara',
  'Dargai',
  'Topi',
  'Besham',
  'Khar',
  'Alpuri',
  'Wana',
  'Miran Shah',
  'Sadda',
  'Thall',
  'Pezu',
  'Uthal',
  'Bhit Shah',
  'Tando Jam',
  'Matli',
  'Golarchi',
  'Nagarparkar',
  'Diplo',
  'Chachro',
  'Qambar',
  'Warah',
  'Naudero',
  'Bakrani',
  'Kot Ghulam Muhammad',
  'Jhuddo',
  'Tando Jan Muhammad',
  'Sui',
  'Dhadar',
  'Duki',
  'Harnai',
  'Sanjawi',
  'Uch Sharif',
  'Naran',
  'Kaghan',
  'Kalam',
  'Bahrain',
  'Madyan',
  'Nathia Gali',
  'Shogran',
  'Saidu Sharif',
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

/// Optional spec fields shown when posting/editing in a category (e.g. car year
/// & mileage, property bedrooms & area).
///
/// Reads the live, admin-managed catalog. Falls back to the built-in defaults
/// only for a category that is not in the catalog at all — a category whose
/// fields the admin has deliberately emptied must stay empty, so an empty list
/// on a KNOWN category is respected rather than re-defaulted.
List<String> attributeFieldsFor(String category) {
  for (final c in appCategories) {
    if (c.title == category) return c.attributes;
  }
  return _defaultAttributeFields(category);
}

List<String> _defaultAttributeFields(String category) {
  switch (category) {
    case 'Motors':
      return const ['Make / Brand', 'Year', 'KM driven', 'Color'];
    case 'Properties':
      return const ['Bedrooms', 'Bathrooms', 'Area (sq ft / marla)'];
    case 'Mobiles & Tablets':
    case 'Electronics':
      return const ['Brand', 'Model', 'Color'];
    case 'Men Essentials':
    case 'Women Essentials':
    case 'Kids Essentials':
      return const ['Brand', 'Size', 'Color'];
    case 'Home & Furniture':
      return const ['Material', 'Color'];
    case 'Crockery':
      return const ['Brand', 'Material', 'Color'];
    case 'Commute & Rides':
      return const [
        'Route (From → To)',
        'Timing',
        'Seats available',
        'Monthly fare',
        'Per-trip fare',
      ];
    case 'Garments':
      return const ['Brand', 'Size', 'Fabric', 'Color'];
    default:
      return const [];
  }
}

/// Professional, fixed colour palette used for product colour selection
/// (Daraz-style swatches). The colour NAME is what gets stored in a listing's
/// `Color` attribute and what buyers filter by.
const List<(String, Color)> kProductColors = [
  ('Black', Color(0xFF1C1C1C)),
  ('White', Color(0xFFFFFFFF)),
  ('Grey', Color(0xFF9E9E9E)),
  ('Silver', Color(0xFFCFD8DC)),
  ('Beige', Color(0xFFD7CCC8)),
  ('Brown', Color(0xFF6D4C41)),
  ('Red', Color(0xFFD32F2F)),
  ('Maroon', Color(0xFF7B1E1E)),
  ('Pink', Color(0xFFEC407A)),
  ('Orange', Color(0xFFF57C00)),
  ('Yellow', Color(0xFFFBC02D)),
  ('Gold', Color(0xFFC9A227)),
  ('Green', Color(0xFF2E7D32)),
  ('Olive', Color(0xFF808000)),
  ('Teal', Color(0xFF00897B)),
  ('Sky Blue', Color(0xFF4FC3F7)),
  ('Blue', Color(0xFF1976D2)),
  ('Navy', Color(0xFF173A6B)),
  ('Purple', Color(0xFF7B1FA2)),
  ('Multicolour', Color(0xFF607D8B)),
];

/// Icons an admin may pick for a category.
///
/// A fixed, const registry rather than free-form input for two reasons: an
/// arbitrary string cannot become an [IconData] at runtime without defeating
/// `--tree-shake-icons` (release builds strip every glyph not referenced as a
/// const), and it keeps the category strip visually coherent. Every icon used by
/// [kDefaultCategories] MUST appear here or it will not survive a save/reload
/// round trip — see [iconNameFor].
const Map<String, IconData> kCategoryIcons = {
  'apps': Icons.apps,
  'storefront': Icons.storefront,
  'grain': Icons.grain,
  'medication': Icons.medication,
  'devices': Icons.devices,
  'phone_android': Icons.phone_android,
  'directions_car': Icons.directions_car,
  'commute': Icons.commute,
  'home': Icons.home,
  'chair': Icons.chair,
  'checkroom': Icons.checkroom,
  'man': Icons.man,
  'woman': Icons.woman,
  'child_care': Icons.child_care,
  'pets': Icons.pets,
  'sports_soccer': Icons.sports_soccer,
  'work': Icons.work,
  'business_center': Icons.business_center,
  'handyman': Icons.handyman,
  'groups': Icons.groups,
  'dinner_dining': Icons.dinner_dining,
  // Spare choices for categories the admin adds later.
  'category': Icons.category,
  'shopping_bag': Icons.shopping_bag,
  'local_florist': Icons.local_florist,
  'menu_book': Icons.menu_book,
  'toys': Icons.toys,
  'watch': Icons.watch,
  'diamond': Icons.diamond,
  'build': Icons.build,
  'agriculture': Icons.agriculture,
  'flight': Icons.flight,
  'celebration': Icons.celebration,
  'health_and_safety': Icons.health_and_safety,
  'school': Icons.school,
  'computer': Icons.computer,
  'kitchen': Icons.kitchen,
  'spa': Icons.spa,
  'music_note': Icons.music_note,
  'camera_alt': Icons.camera_alt,
};

/// Reverse lookup for [kCategoryIcons], so a built-in category defined with a
/// raw `Icons.x` still serialises to a stable name. Falls back to 'category'.
String iconNameFor(IconData icon) {
  for (final e in kCategoryIcons.entries) {
    if (e.value.codePoint == icon.codePoint) return e.key;
  }
  return 'category';
}

class MarketplaceCategory {
  final String title;
  final IconData icon;
  final List<String> subcategories;

  /// Whole category is advertise-only — no Buy Now / checkout, buyers contact
  /// the seller instead.
  final bool advertiseOnly;

  /// Subcategories that are advertise-only even though the rest of the category
  /// can be bought online (e.g. Cars within Motors).
  final Set<String> advertiseOnlySubs;

  /// Hidden categories stay valid for existing listings but are not offered
  /// anywhere new. Lets an admin retire a category without orphaning its ads.
  final bool hidden;

  /// Extra spec fields shown when posting or editing in this category, e.g.
  /// ['Make / Brand', 'Year', 'KM driven'] for Motors. Empty means none.
  ///
  /// A listing stores its answers in an `attributes` map KEYED BY THESE LABELS,
  /// so renaming one orphans the values already saved under the old label. The
  /// ad still shows and sells fine; the field just reads blank.
  final List<String> attributes;

  /// Accent colour for the category card, as an ARGB int (null = auto-assign
  /// from the shared palette). Stored as an int because Firestore has no colour
  /// type and an int survives a JSON round trip exactly.
  final int? colorValue;

  const MarketplaceCategory({
    required this.title,
    required this.icon,
    required this.subcategories,
    this.advertiseOnly = false,
    this.advertiseOnlySubs = const {},
    this.hidden = false,
    this.attributes = const [],
    this.colorValue,
  });

  /// The card accent, or null to let the caller fall back to the palette.
  Color? get color => colorValue == null ? null : Color(colorValue!);

  Map<String, dynamic> toMap() => {
    'title': title,
    'icon': iconNameFor(icon),
    'subcategories': subcategories,
    'advertiseOnly': advertiseOnly,
    'advertiseOnlySubs': advertiseOnlySubs.toList(),
    'hidden': hidden,
    'attributes': attributes,
    'colorValue': colorValue,
  };

  /// Tolerant on purpose: this parses admin-authored data, and one malformed
  /// field must not take the whole catalog down. Anything unreadable falls back
  /// to a sane default rather than throwing.
  factory MarketplaceCategory.fromMap(Map<String, dynamic> m) {
    return MarketplaceCategory(
      title: (m['title'] ?? '').toString(),
      icon: kCategoryIcons[(m['icon'] ?? '').toString()] ?? Icons.category,
      subcategories: ((m['subcategories'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      advertiseOnly: m['advertiseOnly'] == true,
      advertiseOnlySubs: ((m['advertiseOnlySubs'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet(),
      hidden: m['hidden'] == true,
      attributes: ((m['attributes'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      colorValue: m['colorValue'] is num
          ? (m['colorValue'] as num).toInt()
          : null,
    );
  }

  /// `clearColor` exists because a null [colorValue] argument cannot mean "reset
  /// to auto" and "leave unchanged" at the same time.
  MarketplaceCategory copyWith({
    String? title,
    IconData? icon,
    List<String>? subcategories,
    bool? advertiseOnly,
    Set<String>? advertiseOnlySubs,
    bool? hidden,
    List<String>? attributes,
    int? colorValue,
    bool clearColor = false,
  }) {
    return MarketplaceCategory(
      title: title ?? this.title,
      icon: icon ?? this.icon,
      subcategories: subcategories ?? this.subcategories,
      advertiseOnly: advertiseOnly ?? this.advertiseOnly,
      advertiseOnlySubs: advertiseOnlySubs ?? this.advertiseOnlySubs,
      hidden: hidden ?? this.hidden,
      attributes: attributes ?? this.attributes,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
    );
  }
}

/// The catalog the app actually renders. Starts as the built-in defaults and is
/// replaced at startup by whatever the admin has saved in `config/categories`
/// (see loadCategories()). Mutable because the admin panel edits it live.
List<MarketplaceCategory> appCategories = defaultCatalog();

/// Built-in catalog. Two jobs: the seed the admin panel writes to Firestore on
/// first use, and the fallback whenever the stored catalog is missing,
/// unreadable or empty — the app must never render zero categories.
const List<MarketplaceCategory> kDefaultCategories = [
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
    title: 'Dry Fruits',
    icon: Icons.grain,
    subcategories: [
      'Almonds',
      'Cashews',
      'Walnuts',
      'Pistachios',
      'Raisins',
      'Dates',
      'Dried Apricots',
      'Figs',
      'Peanuts',
      'Seeds',
      'Mixed Dry Fruits',
      'Gift Packs',
    ],
  ),
  MarketplaceCategory(
    title: 'Supplements',
    icon: Icons.medication,
    subcategories: [
      'Protein & Whey',
      'Mass Gainers',
      'Pre-Workout',
      'Vitamins',
      'Minerals',
      'Fish Oil & Omega',
      'Amino Acids & BCAA',
      'Herbal Supplements',
      'Immunity Boosters',
      'Weight Management',
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
    title: 'Commute & Rides',
    icon: Icons.commute,
    subcategories: [
      'Carpool',
      'Daily Pick & Drop',
      'School / College Van',
      'Office Transport',
      'Bike Ride',
      'Rent a Car with Driver',
      'Driver Services',
      'Intercity Shared Ride',
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
    title: 'Crockery',
    icon: Icons.dinner_dining,
    subcategories: [
      'Dinner Sets',
      'Plates & Bowls',
      'Cups & Mugs',
      'Tea & Coffee Sets',
      'Glassware',
      'Serving Dishes',
      'Cutlery',
      'Melamine',
      'Ceramic & China',
      'Kitchen Storage',
    ],
  ),
  MarketplaceCategory(
    title: 'Garments',
    icon: Icons.checkroom,
    subcategories: [
      'Men\'s Wear',
      'Women\'s Wear',
      'Kids\' Wear',
      'Unstitched Fabric',
      'Stitched Suits',
      'Bridal & Formal',
      'Winter Wear',
      'Footwear',
      'Undergarments',
      'Wholesale / Lots',
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

/// Whole categories that are advertise-only by default — no online Buy Now /
/// checkout. Buyers contact the seller (call/WhatsApp/chat) and deal in person.
/// Seed values only: once the catalog is stored, the flag lives on the category
/// itself and the admin owns it.
const Set<String> _defaultAdvertiseOnlyCategories = {
  'Properties',
  'Jobs',
  'Services',
  'Community',
  'Commute & Rides',
};

/// Big-ticket / non-shippable subcategories (e.g. within Motors) that are
/// advertise-only even though the rest of their category can be bought online.
/// Small, shippable items like Auto Parts / Car Accessories stay buyable.
/// Seed values only — see above.
const Set<String> _defaultAdvertiseOnlySubcategories = {
  'Cars',
  'Motorcycles',
  'Boats',
  'Heavy Vehicles',
  'Car Rental',
};

/// Default accent colour per category, so the grid reads as colourful rather
/// than uniform. Seed values only: once stored, the colour lives on the category
/// and the admin owns it. Anything without one cycles through [kCategoryPalette].
const Map<String, int> _defaultCategoryColors = {
  'Food & Grocery': 0xFFF4511E, // deep orange
  'Dry Fruits': 0xFFF9A825, // golden amber
  'Supplements': 0xFF2E7D32, // vitamin green
  'Motors': 0xFF1E88E5, // blue
  'Commute & Rides': 0xFF00897B, // teal
  'Properties': 0xFF43A047, // green
  'Mobiles & Tablets': 0xFF3949AB, // indigo
  'Electronics': 0xFF00ACC1, // cyan
  'Home & Furniture': 0xFF8D6E63, // brown
  'Crockery': 0xFFFB8C00, // amber
  'Garments': 0xFFD81B60, // pink
  'Men Essentials': 0xFF546E7A, // blue grey
  'Women Essentials': 0xFF8E24AA, // purple
  'Kids Essentials': 0xFF039BE5, // light blue
  'Jobs': 0xFF5E35B1, // deep purple
  'Services': 0xFFE53935, // red
  'Pets': 0xFF7CB342, // light green
  'Sports & Hobbies': 0xFFC0CA33, // lime
  'Business & Industrial': 0xFF6D4C41, // dark brown
  'Community': 0xFF00838F, // dark cyan
};

/// Fallback accents for categories with no colour set, and the swatches the
/// admin colour picker offers.
const List<Color> kCategoryPalette = [
  Color(0xFFF4511E),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFF00897B),
  Color(0xFFFB8C00),
  Color(0xFFD81B60),
  Color(0xFF3949AB),
  Color(0xFFF9A825),
  Color(0xFF2E7D32),
  Color(0xFF00ACC1),
  Color(0xFF8D6E63),
  Color(0xFF546E7A),
  Color(0xFF039BE5),
  Color(0xFF5E35B1),
  Color(0xFFE53935),
  Color(0xFF7CB342),
  Color(0xFFC0CA33),
  Color(0xFF6D4C41),
  Color(0xFF00838F),
];

/// The accent for a category card: the admin's colour if set, else a stable
/// slot from the shared palette so new categories still look deliberate.
Color categoryAccent(String title, int index) {
  for (final c in appCategories) {
    if (c.title == title && c.color != null) return c.color!;
  }
  return kCategoryPalette[index % kCategoryPalette.length];
}

/// The built-in catalog with the advertise-only, attribute and colour seeds
/// folded onto each category, so a stored catalog and a fallback catalog have
/// exactly the same shape.
List<MarketplaceCategory> defaultCatalog() => [
  for (final c in kDefaultCategories)
    c.copyWith(
      advertiseOnly: _defaultAdvertiseOnlyCategories.contains(c.title),
      advertiseOnlySubs: c.subcategories
          .where(_defaultAdvertiseOnlySubcategories.contains)
          .toSet(),
      attributes: _defaultAttributeFields(c.title),
      colorValue: _defaultCategoryColors[c.title],
    ),
];

/// Derived views over the live catalog, so callers that ask "is this
/// advertise-only?" keep working unchanged whether the catalog came from
/// Firestore or the built-in defaults.
Set<String> get advertiseOnlyCategories => {
  for (final c in appCategories)
    if (c.advertiseOnly) c.title,
};

Set<String> get advertiseOnlySubcategories => {
  for (final c in appCategories) ...c.advertiseOnlySubs,
};

/// Whether a listing supports the online Buy Now / order checkout.
MarketplaceCategory categoryByTitle(String title) {
  return appCategories.firstWhere(
    (category) => category.title == title,
    orElse: () => appCategories.first,
  );
}

/// Categories offered when posting or browsing. Excludes retired ones; existing
/// listings in a hidden category still resolve via [categoryByTitle].
List<MarketplaceCategory> get visibleCategories =>
    appCategories.where((c) => !c.hidden).toList();

/// Options for a category dropdown: the pickable categories, minus the synthetic
/// 'All' bucket, plus [current] even if it is hidden or has since been deleted.
///
/// That last part is not cosmetic — a DropdownButton whose value is absent from
/// its items throws. Editing an old ad whose category was hidden or renamed away
/// would otherwise crash the edit form instead of just letting the seller
/// re-file it.
List<MarketplaceCategory> categoryChoices(String? current) {
  final out = visibleCategories.where((c) => c.title != 'All').toList();
  if (current != null &&
      current.isNotEmpty &&
      !out.any((c) => c.title == current)) {
    out.insert(
      0,
      appCategories.firstWhere(
        (c) => c.title == current,
        orElse: () => MarketplaceCategory(
          title: current,
          icon: Icons.category,
          subcategories: const [],
        ),
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Web Push (VAPID) public key from Firebase Console → Cloud Messaging →
/// "Web configuration" → Web Push certificates. Leave empty to disable web
/// push until configured (the app still works fully without it).
