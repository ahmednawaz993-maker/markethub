import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kReleaseMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        rootBundle,
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
import 'package:package_info_plus/package_info_plus.dart';

// Implementation is split across part files under lib/src/ (see below).
part 'src/i18n.dart';
part 'src/helpers.dart';
part 'src/observability.dart';
part 'src/pagination.dart';
part 'src/deep_links.dart';
part 'src/app_gate.dart';
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
part 'src/admin_orders.dart';
part 'src/admin_feedback.dart';
part 'src/prayer_times.dart';
part 'src/screen_islamic.dart';
part 'src/ludo_engine.dart';
part 'src/ludo_board.dart';
part 'src/ludo_dice.dart';
part 'src/screen_ludo.dart';
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

  // The Firestore database lives in nam5 (multi-region US), so every read from
  // Pakistan is a cross-continent round trip. The local cache is the only
  // lever that does not require migrating the database.
  //
  // Mobile enables persistence by default; WEB DOES NOT — which is why the
  // site refetched everything on every navigation. Setting it here, before any
  // Firestore call, turns repeat reads into local cache hits. Must run before
  // the first Firestore use or it throws.
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (_) {
    // Web persistence is unavailable with several tabs open on some browsers.
    // Losing the cache is a slowdown, never a failure, so carry on.
  }

  // Immediately after Firebase.initializeApp and before anything else can
  // throw, so a crash during the remaining startup work is still reported.
  await initObservability();

  // Only these two gate the first frame, and both are local SharedPreferences
  // reads costing well under a millisecond. They decide the language and theme
  // the very first pixel is painted in, so rendering before them would flash
  // the wrong one.
  await loadSavedLocale();
  await loadSavedThemeMode();

  runApp(const PakBazarApp());

  // Everything below used to run BEFORE runApp, as eleven sequential awaits —
  // five of them separate Firestore round trips to config/*. On a Pakistani
  // mobile connection that was seconds of blank screen before the app started
  // painting, and it was pure waste: every one of these has a safe default
  // already in place and feeds a ValueNotifier that rebuilds the UI when it
  // resolves. So they now run AFTER the first frame, and in parallel with each
  // other rather than one after another.
  //
  // Each already swallows its own errors; unawaited() documents that nothing
  // here is allowed to hold up the app.
  unawaited(
    Future.wait([
      // The gate needs the real build number, and this is a local platform
      // call rather than a network one.
      loadPackageInfo(),
      loadFeaturingFlag(),
      loadVerificationFlag(),
      loadCategories(),
      loadMonetizationFlag(),
      loadLuckyDrawFlag(),
      loadRecentSearches(),
      recordAppSession(),
    ]).catchError((_) => <void>[]),
  );

  // Live subscription, so flipping maintenance on reaches running apps in
  // seconds rather than at next launch — which is the entire point during a
  // database cutover.
  listenToAppGate();
}
