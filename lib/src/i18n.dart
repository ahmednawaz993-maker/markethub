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

/// Translates [key] to the current language, falling back to English, then to
/// the key itself (so a missing key is visible rather than blank).
String tr(String key) {
  final lang = appLocale.value.languageCode;
  final entry = _kStrings[key];
  if (entry == null) return key;
  return entry[lang] ?? entry['en'] ?? key;
}

const Map<String, Map<String, String>> _kStrings = {
  // Bottom navigation + sell button
  'nav.home': {'en': 'Home', 'ur': 'ہوم'},
  'nav.chats': {'en': 'Chats', 'ur': 'پیغامات'},
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
