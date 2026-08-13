part of '../main.dart';

// Lightweight localization: an English / Urdu string table plus a reactive
// locale. PakBazarApp listens to [appLocale] so switching language rebuilds the
// whole app and flips it between LTR (English) and RTL (Urdu). Strings are
// looked up with tr('key'); anything not yet translated falls back to English,
// so the app stays fully usable while Urdu coverage grows over time.

const Locale kEnglish = Locale('en');
const Locale kUrdu = Locale('ur');

/// Current app locale; defaults to English until a saved choice is loaded.
final ValueNotifier<Locale> appLocale = ValueNotifier<Locale>(kEnglish);

const String _localePrefKey = 'app_locale';

/// True when the app is currently showing Urdu (right-to-left).
bool get isUrdu => appLocale.value.languageCode == 'ur';

/// Loads the saved language choice at startup (call before runApp).
Future<void> loadSavedLocale() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_localePrefKey) == 'ur') appLocale.value = kUrdu;
  } catch (_) {}
}

/// Switches language and persists the choice.
Future<void> setLocale(Locale locale) async {
  appLocale.value = locale;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localePrefKey, locale.languageCode);
  } catch (_) {}
}

/// Translates [key] to the current language.
///
/// Falls back to the entry's English text, then to [fallback], and only then
/// to the key itself. Passing the English wording as [fallback] at the call
/// site means an unregistered key renders as readable English instead of
/// printing `profile.help` on screen — the previous last-resort behaviour,
/// whose failure is silent because a key looks like a label until someone
/// actually reads it.
String tr(String key, [String? fallback]) {
  final lang = appLocale.value.languageCode;
  final entry = _kStrings[key];
  if (entry == null) return fallback ?? key;
  return entry[lang] ?? entry['en'] ?? fallback ?? key;
}

/// Every registered translation key. Exposed so tests can assert the table's
/// integrity — a key missing its Urdu entry silently shows English to Urdu
/// users, which is indistinguishable from an untranslated screen.
Iterable<String> get translationKeys => _kStrings.keys;

const Map<String, Map<String, String>> _kStrings = {
  // Bottom navigation + sell button
  'nav.home': {'en': 'Home', 'ur': 'ہوم'},
  'nav.favorites': {'en': 'Favorites', 'ur': 'پسندیدہ'},
  'nav.chats': {'en': 'Chats', 'ur': 'پیغامات'},
  'nav.menu': {'en': 'Menu', 'ur': 'مینو'},
  'nav.myAds': {'en': 'My Ads', 'ur': 'میرے اشتہار'},
  'nav.profile': {'en': 'Profile', 'ur': 'پروفائل'},
  'nav.sell': {'en': 'SELL', 'ur': 'بیچیں'},

  // Settings
  'settings.language': {'en': 'Language', 'ur': 'زبان'},

  // Profile actions
  'profile.orders': {'en': 'My Orders', 'ur': 'میرے آرڈرز'},
  'profile.offers': {'en': 'Offers', 'ur': 'پیشکشیں'},
  'profile.wallet': {'en': 'PakBazar Wallet', 'ur': 'پاک بازار والیٹ'},
  'profile.verify': {'en': 'Verify Identity', 'ur': 'شناخت کی تصدیق'},
  'profile.drafts': {'en': 'Drafts', 'ur': 'مسودے'},
  'profile.savedSearches': {'en': 'Saved Searches', 'ur': 'محفوظ تلاش'},
  'profile.following': {'en': 'Following', 'ur': 'فالو کیے گئے'},
  'profile.help': {'en': 'Help & Feedback', 'ur': 'مدد اور رائے'},
  'profile.about': {'en': 'About PakBazar', 'ur': 'پاک بازار کے بارے میں'},
  'profile.logout': {'en': 'Logout', 'ur': 'لاگ آؤٹ'},
  'profile.adminPanel': {'en': 'Admin Panel', 'ur': 'ایڈمن پینل'},

  // ---- Common actions --------------------------------------------------
  'action.save': {'en': 'Save', 'ur': 'محفوظ کریں'},
  'action.cancel': {'en': 'Cancel', 'ur': 'منسوخ کریں'},
  'action.close': {'en': 'Close', 'ur': 'بند کریں'},
  'action.delete': {'en': 'Delete', 'ur': 'حذف کریں'},
  'action.edit': {'en': 'Edit', 'ur': 'ترمیم کریں'},
  'action.share': {'en': 'Share', 'ur': 'شیئر کریں'},
  'action.retry': {'en': 'Try again', 'ur': 'دوبارہ کوشش کریں'},
  'action.apply': {'en': 'Apply', 'ur': 'لاگو کریں'},
  'action.reset': {'en': 'Reset', 'ur': 'ری سیٹ کریں'},
  'action.confirm': {'en': 'Confirm', 'ur': 'تصدیق کریں'},
  'action.search': {'en': 'Search', 'ur': 'تلاش کریں'},
  'action.filters': {'en': 'Filters', 'ur': 'فلٹرز'},
  'action.postAd': {'en': 'Post an ad', 'ur': 'اشتہار لگائیں'},

  // ---- Shared states ---------------------------------------------------
  'state.error': {'en': 'Something went wrong', 'ur': 'کچھ غلط ہو گیا'},
  'state.noResults': {'en': 'No listings found', 'ur': 'کوئی اشتہار نہیں ملا'},
  'state.noResultsHint': {
    'en': 'Try a different search or adjust your filters.',
    'ur': 'مختلف تلاش آزمائیں یا فلٹرز تبدیل کریں۔',
  },
  'state.seenEverything': {
    'en': 'You have seen everything',
    'ur': 'آپ سب کچھ دیکھ چکے ہیں',
  },
  'state.loadMoreFailed': {
    'en': 'Could not load more ads.',
    'ur': 'مزید اشتہارات لوڈ نہیں ہو سکے۔',
  },

  // ---- Home ------------------------------------------------------------
  'home.searchHint': {
    'en': 'Search title, brand, category or city',
    'ur': 'عنوان، برانڈ، زمرہ یا شہر تلاش کریں',
  },
  'home.recommended': {
    'en': 'Recommended for you',
    'ur': 'آپ کے لیے تجویز کردہ',
  },
  'home.featured': {'en': 'Featured on PakBazar', 'ur': 'پاک بازار پر نمایاں'},
  'home.topDeals': {'en': 'Top deals', 'ur': 'بہترین پیشکشیں'},
  'home.noAds': {'en': 'No ads yet', 'ur': 'ابھی کوئی اشتہار نہیں'},

  // ---- Listing / ad details --------------------------------------------
  'ad.buyNow': {'en': 'Buy Now', 'ur': 'ابھی خریدیں'},
  'ad.addToCart': {'en': 'Add to cart', 'ur': 'ٹوکری میں شامل کریں'},
  'ad.makeOffer': {'en': 'Make an offer', 'ur': 'پیشکش کریں'},
  'ad.chat': {'en': 'Chat', 'ur': 'گفتگو'},
  'ad.call': {'en': 'Call', 'ur': 'کال کریں'},
  'ad.whatsapp': {'en': 'WhatsApp', 'ur': 'واٹس ایپ'},
  'ad.description': {'en': 'Description', 'ur': 'تفصیل'},
  'ad.specifications': {'en': 'Specifications', 'ur': 'خصوصیات'},
  'ad.condition': {'en': 'Condition', 'ur': 'حالت'},
  'ad.negotiable': {'en': 'Negotiable', 'ur': 'قابلِ گفت و شنید'},
  'ad.sold': {'en': 'Sold', 'ur': 'فروخت ہو گیا'},
  'ad.reportAd': {'en': 'Report ad', 'ur': 'اشتہار کی شکایت کریں'},
  'ad.unavailable': {
    'en': 'This ad is no longer available',
    'ur': 'یہ اشتہار اب دستیاب نہیں',
  },

  // ---- Checkout / orders -----------------------------------------------
  'checkout.title': {'en': 'Checkout', 'ur': 'چیک آؤٹ'},
  'checkout.placeOrder': {'en': 'Place order', 'ur': 'آرڈر دیں'},
  'checkout.deliveryAddress': {
    'en': 'Delivery address',
    'ur': 'ڈیلیوری کا پتہ',
  },
  'checkout.total': {'en': 'Total', 'ur': 'کل'},
  'checkout.deliveryFee': {'en': 'Delivery fee', 'ur': 'ڈیلیوری فیس'},
  'checkout.freeDelivery': {'en': 'Free delivery', 'ur': 'مفت ڈیلیوری'},
  'checkout.protected': {
    'en': 'Your money is held by PakBazar until you confirm delivery.',
    'ur': 'آپ کی رقم پاک بازار کے پاس محفوظ رہتی ہے جب تک آپ ڈیلیوری کی تصدیق نہ کر دیں۔',
  },
  'order.confirmReceipt': {
    'en': 'Confirm receipt',
    'ur': 'وصولی کی تصدیق کریں',
  },

  // ---- Auth ------------------------------------------------------------
  'auth.pleaseLogin': {'en': 'Please log in', 'ur': 'براہِ کرم لاگ اِن کریں'},

  // ---- Cart / favorites / chats ----------------------------------------
  'cart.title': {'en': 'Cart', 'ur': 'ٹوکری'},
  'cart.empty': {'en': 'Your cart is empty', 'ur': 'آپ کی ٹوکری خالی ہے'},
  'favorites.empty': {'en': 'No favorites yet', 'ur': 'ابھی کوئی پسندیدہ نہیں'},
  'chats.empty': {'en': 'No conversations yet', 'ur': 'ابھی کوئی گفتگو نہیں'},
};

/// Language selector shown on the profile screen. Rebuilds reactively so the
/// chips reflect the active language.
class LanguageTile extends StatelessWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        final ur = locale.languageCode == 'ur';
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.language, color: kPakGreen),
                    const SizedBox(width: 8),
                    Text(
                      tr('settings.language'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('English'),
                      selected: !ur,
                      onSelected: (_) => setLocale(kEnglish),
                    ),
                    ChoiceChip(
                      label: const Text('اردو'),
                      selected: ur,
                      onSelected: (_) => setLocale(kUrdu),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
