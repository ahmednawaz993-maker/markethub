import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kReleaseMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        HapticFeedback,
        LogicalKeyboardKey,
        KeyEvent,
        KeyDownEvent,
        KeyRepeatEvent,
        SystemChrome,
        SystemUiOverlayStyle;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safe_device/safe_device.dart';

// Implementation is split across part files under lib/src/ (see below).
part 'src/i18n.dart';
part 'src/helpers.dart';
part 'src/observability.dart';
part 'src/pagination.dart';
part 'src/security.dart';
part 'src/theme.dart';
part 'src/design_system.dart';
part 'src/models.dart';
part 'src/catalog.dart';
part 'src/push.dart';
part 'src/commerce.dart';
part 'src/cancellation.dart';
part 'src/returns.dart';
part 'src/refunds.dart';
part 'src/screen_invite.dart';
part 'src/cart.dart';
part 'src/addresses.dart';
part 'src/review_prompt.dart';
part 'src/screen_notif_prefs.dart';
part 'src/screen_payout_accounts.dart';
part 'src/widgets.dart';
part 'src/presence.dart';
part 'src/app.dart';
part 'src/screen_auth.dart';
part 'src/screen_home.dart';
part 'src/screen_stores.dart';
part 'src/screen_browse.dart';
part 'src/screen_add_listing.dart';
part 'src/screen_my_ads.dart';
part 'src/screen_ad_details.dart';
part 'src/screen_reviews.dart';
part 'src/screen_seller_profile.dart';
part 'src/screen_favorites.dart';
part 'src/screen_profile.dart';
part 'src/screen_wallet.dart';
part 'src/screen_orders.dart';
part 'src/order_fulfillment.dart';
part 'src/screen_checkout.dart';
part 'src/screen_addresses.dart';
part 'src/screen_offers.dart';
part 'src/screen_admin.dart';
part 'src/screen_admin_categories.dart';
part 'src/screen_notifications.dart';
part 'src/screen_chat.dart';
part 'src/screen_support.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app now sits on a clean white marketplace surface, so the system bars
  // use DARK icons over a light background. (Screens with a dark hero, e.g. the
  // listing image carousel, override this locally.)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light, // iOS
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Color(0xFFEBEEF3),
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Immediately after Firebase.initializeApp and before anything else can
  // throw, so a crash during the remaining startup work is still reported.
  await initObservability();
  await loadSavedLocale();
  await loadSavedThemeMode();
  await loadFeaturingFlag();
  await loadVerificationFlag();
  await loadCategories();

  await loadMonetizationFlag();
  await loadLuckyDrawFlag();
  await loadRecentSearches();
  await recordAppSession();

  runApp(const PakBazarApp());
}
