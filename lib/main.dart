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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Implementation is split across part files under lib/src/ (see below).
part 'src/i18n.dart';
part 'src/helpers.dart';
part 'src/theme.dart';
part 'src/models.dart';
part 'src/catalog.dart';
part 'src/push.dart';
part 'src/commerce.dart';
part 'src/widgets.dart';
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
part 'src/screen_offers.dart';
part 'src/screen_admin.dart';
part 'src/screen_notifications.dart';
part 'src/screen_chat.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await loadSavedLocale();

  runApp(const PakBazarApp());
}
