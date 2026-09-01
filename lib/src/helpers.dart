part of '../main.dart';

// Top-level helper functions and shared constants.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Currency shown across the app (Pakistani Rupee).
const String currencySymbol = 'Rs';

/// App version shown in the UI (About screen, support emails). Keep in sync
/// with the `version:` line in pubspec.yaml — that one feeds the Play
/// versionName/versionCode, this one is what users see inside the app.
const String kAppVersion = '1.0.88';

/// Version name and build number as reported by the platform, so they cannot
/// drift from what was actually installed.
///
/// kAppVersion above is a hand-maintained fallback, and it HAS drifted before —
/// it sat at 1.0.34 while five releases shipped, so every support email carried
/// the wrong version. Prefer these at runtime.
String appVersionName = kAppVersion;
int appBuildNumber = 0;

/// Reads the installed version. Local call, no network.
Future<void> loadPackageInfo() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.trim().isNotEmpty) appVersionName = info.version.trim();
    appBuildNumber = int.tryParse(info.buildNumber.trim()) ?? 0;
  } catch (_) {
    // Leave the compiled-in fallback, and a build number of 0, which the
    // version gate treats as "unknown" and therefore never blocks on.
  }
}

// ---------------------------------------------------------------------------
// Image upload pipeline
// ---------------------------------------------------------------------------

/// JPEG quality applied to every picked image before upload. 72 is visually
/// indistinguishable at the sizes we display and cuts a typical phone photo
/// from several MB to a few hundred KB.
const int kUploadImageQuality = 72;

/// Longest edge we ever upload. Well above the largest size the app renders,
/// so full-screen gallery view stays sharp.
const double kUploadImageMaxWidth = 1600;

/// Maximum photos per listing — matches the cap promised in the posting UI.
const int kMaxListingImages = 8;

// ---------------------------------------------------------------------------
// Private contact details
// ---------------------------------------------------------------------------

/// Document holding a user's contact PII: `users/{uid}/private/contact`.
///
/// The parent user document is readable by every signed-in user (seller pages
/// need the name and rating, and the Stores rails run list queries over the
/// collection), and Firestore rules cannot filter fields on read. So email,
/// phone, address and captured GPS live here instead.
DocumentReference<Map<String, dynamic>> privateContactRef(String uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('contact');
}

/// Reads a user's contact details.
///
/// Falls back to the legacy fields on the public user document so the app keeps
/// working for accounts the server-side backfill has not migrated yet. Once
/// migrateUserContactPii has swept everyone, the fallback simply stops
/// matching anything.
Future<Map<String, dynamic>> loadPrivateContact(String uid) async {
  // Merge FIELD BY FIELD rather than picking one document. A signup writes
  // only email + phone to the private doc, so returning it wholesale as soon
  // as it is non-empty would hide a legacy `address` still living on the
  // public document.
  final merged = <String, dynamic>{};

  try {
    final pub = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final d = pub.data();
    if (d != null) {
      for (final k in const ['email', 'phone', 'address']) {
        final v = d[k];
        if (v != null && v.toString().isNotEmpty) merged[k] = v;
      }
    }
  } catch (_) {
    // Legacy copy is optional.
  }

  try {
    final priv = await privateContactRef(uid).get();
    final d = priv.data();
    if (d != null) {
      // Private wins wherever it has a value.
      d.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) merged[k] = v;
      });
    }
  } catch (_) {
    // Owner-only read; fall back to whatever the public doc had.
  }

  return merged;
}

/// Batch-loads contact details for several users at once — for the admin
/// screens, which list users and need to identify them by email.
///
/// Staff with 'users'/'verifyId' may read these (see the rules on
/// users/{uid}/private). One read per user, issued in bounded-size waves
/// rather than 300 at once, and the caller is expected to cache the result
/// for the lifetime of the list rather than re-fetching per row build.
Future<Map<String, Map<String, dynamic>>> loadPrivateContacts(
  Iterable<String> uids,
) async {
  final ids = uids.where((u) => u.isNotEmpty).toSet().toList();
  final out = <String, Map<String, dynamic>>{};
  const waveSize = 30;
  for (var i = 0; i < ids.length; i += waveSize) {
    final end = (i + waveSize) > ids.length ? ids.length : i + waveSize;
    final wave = ids.sublist(i, end);
    final results = await Future.wait(
      wave.map((uid) async {
        try {
          final snap = await privateContactRef(uid).get();
          return MapEntry(uid, snap.data() ?? const <String, dynamic>{});
        } catch (_) {
          return MapEntry(uid, const <String, dynamic>{});
        }
      }),
    );
    out.addEntries(results);
  }
  return out;
}

/// Writes contact details to the private subcollection.
Future<void> savePrivateContact(
  String uid,
  Map<String, dynamic> values,
) async {
  await privateContactRef(uid).set(values, SetOptions(merge: true));
}

/// Public web URL for a single listing, used when sharing an ad.
///
/// The web build does not route on this path yet, so it currently lands on the
/// site and the id is carried for attribution and for when deep links ship.
/// Sharing the bare site root gave the recipient no way to reach the item.
String listingShareUrl(String listingId) {
  final id = listingId.trim();
  return id.isEmpty
      ? 'https://pakbazar24.com'
      : 'https://pakbazar24.com/ad/$id';
}

/// Metadata for uploaded images.
///
/// The `cacheControl` header is the important part: Firebase Storage defaults
/// to `private, max-age=0`, so without this every image is re-downloaded on
/// every app start over mobile data. Object paths are timestamp-unique, so
/// treating them as immutable is safe.
SettableMetadata imageUploadMetadata({String contentType = 'image/jpeg'}) {
  return SettableMetadata(
    contentType: contentType,
    cacheControl: 'public, max-age=31536000, immutable',
  );
}

/// Formats a price string with thousands separators, e.g. "4250000" ->
/// "Rs 4,250,000". Non-numeric values (e.g. "Negotiable") are shown as-is.
String formatPrice(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
  final value = double.tryParse(cleaned);
  if (value == null || cleaned.isEmpty) {
    return raw.trim().isEmpty
        ? currencySymbol
        : '$currencySymbol ${raw.trim()}';
  }
  // Round the whole value in one operation so the fraction carries into the
  // integer part correctly (e.g. 100.999 -> 101.00, not 100.00).
  final fixed = value.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final digits = fixed.substring(0, dot);
  final frac = fixed.substring(dot); // includes leading '.'
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  var out = buf.toString();
  if (frac != '.00') {
    out += frac;
  }
  return '$currencySymbol $out';
}

/// True if [email] looks like a valid address. Permissive on purpose — this is
/// a client-side sanity check; Firebase Auth does the authoritative validation.
bool isValidEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

/// Emails granted admin access (also enforced in Firestore rules via the
/// auth token email). Add more to expand the admin team.
const List<String> adminEmails = ['ahmednawaz993@gmail.com'];

/// Inbox that receives support requests and suggestions (the admin). Used by
/// the Help & Suggestions sheet, which both stores the message in Firestore
/// (shown in Admin Panel → Feedback) and emails it here directly.
const String supportEmail = 'ahmednawaz993@gmail.com';

/// Platform-wide featuring on/off, controlled by the admin (config/featuring).
/// When false, the home Featured rails (ads + businesses) are hidden. Loaded
/// at startup and flipped live by the admin Featured tab.
final ValueNotifier<bool> featuringEnabled = ValueNotifier<bool>(true);

Future<void> loadFeaturingFlag() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('featuring')
        .get();
    featuringEnabled.value = doc.data()?['enabled'] != false;
  } catch (_) {}
}

/// Bumped whenever the admin-managed catalog changes, so category-driven UI
/// rebuilds without every screen holding its own subscription. Widgets that
/// render categories wrap in a ValueListenableBuilder on this.
final ValueNotifier<int> categoriesVersion = ValueNotifier<int>(0);

/// Firestore doc holding the whole catalog. One doc, not a collection: the
/// catalog is small, always read in full, and an ordered array is what makes
/// admin reordering trivial and atomic.
DocumentReference<Map<String, dynamic>> get categoriesDoc =>
    FirebaseFirestore.instance.collection('config').doc('categories');

/// Applies a stored catalog, ignoring anything unusable.
///
/// An empty or unparseable list leaves [appCategories] on the built-in defaults
/// rather than blanking the app — a bad admin save must never leave users with
/// no categories to browse or post into.
bool applyStoredCategories(Map<String, dynamic>? data) {
  final raw = data?['items'];
  if (raw is! List || raw.isEmpty) return false;
  final parsed = <MarketplaceCategory>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final c = MarketplaceCategory.fromMap(Map<String, dynamic>.from(e));
    if (c.title.isEmpty) continue;
    parsed.add(c);
  }
  if (parsed.isEmpty) return false;
  appCategories = parsed;
  categoriesVersion.value++;
  return true;
}

/// Loads the admin-managed catalog at startup, then keeps listening so an edit
/// in the admin panel reaches every open app without a restart.
Future<void> loadCategories() async {
  try {
    final doc = await categoriesDoc.get();
    applyStoredCategories(doc.data());
  } catch (_) {
    // Offline or denied — the built-in defaults are already in place.
  }
  // Fire-and-forget: startup must not block on the stream.
  try {
    categoriesDoc.snapshots().listen(
      (snap) => applyStoredCategories(snap.data()),
      onError: (_) {},
    );
  } catch (_) {}
}

/// Whether ID / face verification is REQUIRED before a user can post, buy,
/// make offers, or chat. Controlled by the admin (config/verification) and
/// loaded at startup. Defaults OFF — the admin turns it on from the Verify ID
/// tab when needed. Mirrored in firestore.rules (isVerifiedUser).
final ValueNotifier<bool> verificationRequired = ValueNotifier<bool>(false);

Future<void> loadVerificationFlag() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('verification')
        .get();
    verificationRequired.value = doc.data()?['required'] == true;
  } catch (_) {}
}

/// Whether paid monetization features — the wallet (top-ups/withdrawals) and
/// paid banner-ad promotions — are shown. Kept OFF for the Play Store launch:
/// selling in-app promotions for money loaded outside Google Play Billing
/// violates Play's Payments policy. Do NOT enable this until those purchases go
/// through Google Play Billing (or are otherwise compliant); flipping it on
/// after review to slip the feature past Google is itself a policy breach.
/// Controlled by config/monetization (enabled: true), loaded at startup.
final ValueNotifier<bool> monetizationEnabled = ValueNotifier<bool>(false);

Future<void> loadMonetizationFlag() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('monetization')
        .get();
    monetizationEnabled.value = doc.data()?['enabled'] == true;
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Lucky Draw campaign (14 Aug 2026 — 5 winners × PKR 100,000).
//
// The promo banner + Invite screen entry points show only while the campaign
// is active: BEFORE the draw date AND the config kill-switch is on. The date
// check is authoritative, so the banner AUTO-REMOVES itself on 14 Aug 2026 with
// no app update or admin action needed.
// ---------------------------------------------------------------------------

/// The moment the lucky draw closes. On/after this instant the banner and every
/// Invite entry point disappear automatically. (UTC so it's device-clock
/// -timezone independent.)
final DateTime kLuckyDrawEndsAt = DateTime.utc(2026, 8, 14);

/// Public Play Store listing — the link shared from the Invite screen.
const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.pakbazar24.app';

/// The link put in front of friends when a user shares the app.
const String kAppShareLink = kPlayStoreUrl;

/// Admin kill-switch (config/luckyDraw.enabled) to end the campaign early
/// without shipping an update. Defaults ON; the date check ends it regardless.
final ValueNotifier<bool> luckyDrawEnabled = ValueNotifier<bool>(true);

Future<void> loadLuckyDrawFlag() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('luckyDraw')
        .get();
    luckyDrawEnabled.value = doc.data()?['enabled'] != false;
  } catch (_) {}
}

/// Pure date/flag gate — testable without touching the device clock.
bool luckyDrawActiveAt(DateTime now) =>
    luckyDrawEnabled.value && now.toUtc().isBefore(kLuckyDrawEndsAt);

/// Whether the lucky-draw banner + Invite entry points should show right now.
bool luckyDrawActive() => luckyDrawActiveAt(DateTime.now());

/// Loads the set of admin-suspended (platform-blocked) users so their listings
/// can be hidden from everyone's feeds and search results. Refreshed at startup.
Future<void> loadPlatformBlockedUsers() async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('blocked', isEqualTo: true)
        .limit(1000)
        .get();
    platformBlockedUserIds
      ..clear()
      ..addAll(snap.docs.map((d) => d.id));
  } catch (_) {}
}

/// Auto-saves a user's location onto their profile from normal app activity —
/// the city they browse, or the GPS attached to an ad they post — so admins can
/// see where buyers and sellers are. Merges only the fields provided; never
/// overwrites an existing value with null/empty.
Future<void> saveUserLocation({String? city, double? lat, double? lng}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final data = <String, dynamic>{};
  if (city != null && city.trim().isNotEmpty && city != 'All Pakistan') {
    data['city'] = city.trim();
  }
  if (lat != null && lng != null) {
    data['lat'] = lat;
    data['lng'] = lng;
  }
  if (data.isEmpty) return;
  data['locationUpdatedAt'] = Timestamp.now();
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(data, SetOptions(merge: true));
  } catch (_) {}
}

bool isAdminUser() => adminEmails.contains(
  FirebaseAuth.instance.currentUser?.email?.toLowerCase(),
);

/// Demo / review accounts that bypass ID verification so Google Play reviewers
/// (and demos) can use post/buy/offer/chat immediately, without waiting for
/// admin approval. Keep in sync with isDemo() in firestore.rules.
const List<String> demoEmails = ['demo@pakbazar24.com'];

bool isDemoUser() => demoEmails.contains(
  FirebaseAuth.instance.currentUser?.email?.toLowerCase(),
);

/// The super admin (full access). Staff are everyone else granted permissions.
bool isSuperAdmin() => isAdminUser();

/// Grantable admin areas: (permission code, display label). Drives both the
/// admin-panel tabs a staff member sees and the staff permission checkboxes.
/// Keep the codes in sync with the `can('...')` checks in firestore.rules.
const List<(String, String)> kAdminAreas = [
  ('activity', 'Activity'),
  ('approvals', 'Approvals'),
  ('verifyId', 'Verify ID'),
  ('businessVerify', 'Business'),
  ('payments', 'Payments'),
  ('escrow', 'Escrow'),
  ('featured', 'Featured'),
  ('feedback', 'Feedback'),
  ('support', 'Customer Care'),
  ('users', 'Users'),
  ('reports', 'Reports'),
  ('topups', 'Top-ups'),
  ('paymentAccount', 'Payment a/c'),
  ('withdrawals', 'Withdrawals'),
  ('promotions', 'Promotions'),
  ('orders', 'Orders'),
  ('offers', 'Offers'),
  ('purchases', 'Purchases'),
  ('listings', 'Listings'),
  ('chats', 'Chats'),
  ('appeals', 'Appeals'),
  ('deletions', 'Deletions'),
  ('broadcasts', 'Notify'),
  ('categories', 'Categories'),
];

/// Permission codes granted to the current staff member (empty for the super
/// admin, who bypasses these checks, and for non-staff users). Loaded at
/// startup by [loadStaffPermissions].
final Set<String> staffPermissions = <String>{};

/// Bumped every time [loadStaffPermissions] finishes. Widgets that gate on
/// [canOpenAdminPanel] / [hasAdminPerm] listen to this so they rebuild when the
/// grants land — reading the plain [staffPermissions] set from `build()` left
/// the Staff Panel button missing until some unrelated rebuild happened to run.
final ValueNotifier<int> staffPermissionsVersion = ValueNotifier<int>(0);

/// Loads the signed-in user's staff permissions from `staff/{email}`. The super
/// admin needs no entry. Safe to call repeatedly.
///
/// The set is swapped in only once the read succeeds. Clearing it up-front (as
/// this used to) opened a window on every call where an active staff member
/// looked like they had no permissions at all — the Staff Panel button vanished
/// from the Menu and the panel itself could paint "No access" — and a transient
/// network error left them locked out for the rest of the session.
Future<void> loadStaffPermissions() async {
  final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
  if (email == null || isSuperAdmin()) {
    staffPermissions.clear();
    staffPermissionsVersion.value++;
    return;
  }
  final Set<String> next;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('staff')
        .doc(email)
        .get();
    final d = doc.data();
    next = <String>{};
    if (d != null && d['active'] != false) {
      final perms = (d['permissions'] as Map?) ?? const {};
      perms.forEach((k, v) {
        if (v == true) next.add(k.toString());
      });
    }
  } catch (_) {
    // Offline or a denied read: keep whatever we already had rather than
    // silently stripping access mid-session.
    return;
  }
  staffPermissions
    ..clear()
    ..addAll(next);
  staffPermissionsVersion.value++;
}

/// True if the user may act on the given admin area (super admin or granted).
bool hasAdminPerm(String code) =>
    isSuperAdmin() || staffPermissions.contains(code);

/// True if the user can open the admin panel at all (super admin or any staff
/// permission).
bool canOpenAdminPanel() => isSuperAdmin() || staffPermissions.isNotEmpty;

/// Price with an optional unit suffix, e.g. "Rs 250 / kg".
String priceLabel(Listing l) =>
    formatPrice(l.price) + (l.unit.isEmpty ? '' : ' / ${l.unit}');

/// What a profile document needs writing to it, given what is already there.
///
/// Pure, and separate from the Firestore call, because THIS is where the bugs
/// were and none of them were visible from the code that does the writing.
///
/// ensureUserDoc used to do one of two things: create the document if it was
/// missing, or — if it existed — sync nothing but the email-verified flag.
/// That is correct for somebody who signs up once and never changes, and wrong
/// for three cases that all now happen:
///
///  * A GUEST WHO SIGNS IN. Linking keeps the same uid, so the document
///    already exists and was skipped, and `isAnonymous` stayed true for ever.
///    Nothing currently READS that field — the app asks the auth object, which
///    is always right — so this one is wrong data rather than a broken gate,
///    and it is fixed because a field that lies is a trap for whoever reads it
///    next. Browsing without an account is now a button on the landing page,
///    so this path is the common one, not a corner.
///
///  * A NAME WE WERE GIVEN AND THREW AWAY. Google and Facebook hand back the
///    person's name and photo. Neither was ever stored, and both are read:
///    displayName decides the seller name on every ad they post, and photoUrl
///    is the avatar on the ad page. So somebody who signed in with Google
///    posted ads as the first half of their email address, with no picture.
///
///  * AN EMAIL WE NEVER RECORDED. The private contact row is written only when
///    the document is created. A guest has no email at creation time, so after
///    upgrading there was no address on file — the one the orders desk uses to
///    chase a delivery.
///
/// A name the user has typed themselves is never overwritten by the provider's
/// version: filling a blank is help, replacing a choice is not.
Map<String, dynamic> profileUpdates({
  required Map<String, dynamic>? existing,
  required bool isAnonymous,
  required bool emailVerified,
  String? displayName,
  String? photoUrl,
}) {
  if (existing == null) return const {};
  final out = <String, dynamic>{};

  if (existing['isAnonymous'] != isAnonymous) {
    out['isAnonymous'] = isAnonymous;
  }
  if (existing['verified'] != emailVerified) {
    out['verified'] = emailVerified;
  }
  final name = displayName?.trim() ?? '';
  final hasName = ((existing['displayName'] as String?)?.trim() ?? '').isNotEmpty;
  if (name.isNotEmpty && !hasName) {
    out['displayName'] = name;
  }
  final photo = photoUrl?.trim() ?? '';
  final hasPhoto = ((existing['photoUrl'] as String?)?.trim() ?? '').isNotEmpty;
  if (photo.isNotEmpty && !hasPhoto) {
    out['photoUrl'] = photo;
  }
  return out;
}

/// Privacy-friendly public name from a user's profile data:
/// display name > business name > email local-part > "User". Never the full
/// email address.
String friendlyName(Map<String, dynamic>? d, {String? email}) {
  final dn = (d?['displayName'] as String?)?.trim() ?? '';
  final bn = (d?['businessName'] as String?)?.trim() ?? '';
  if (dn.isNotEmpty) return dn;
  if (d?['isBusiness'] == true && bn.isNotEmpty) return bn;
  if (email != null && email.contains('@')) return email.split('@').first;
  return 'User';
}

/// Gates verified-only actions (posting, buying, offering, chatting). Returns
/// true if allowed; otherwise prompts the user to verify and returns false.
/// Admins bypass.
Future<bool> ensureVerified(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  if (isAdminUser() || isDemoUser()) return true;
  // Admin can switch verification off platform-wide.
  if (!verificationRequired.value) return true;
  bool verified = false;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    verified = doc.data()?['idVerified'] == true;
  } catch (_) {}
  if (verified) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.verified_user, color: kPakGreen, size: 44),
      title: const Text('Verify your identity'),
      content: const Text(
        'For everyone\'s safety, PakBazar requires identity verification before '
        'you can post ads, buy, make offers, or chat. It only takes a minute.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Verify now'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerificationScreen()),
    );
  }
  return false;
}

/// Paid promotion packages (seller pays to Feature an ad).
bool isBuyable(Listing l) =>
    !advertiseOnlyCategories.contains(l.category) &&
    !advertiseOnlySubcategories.contains(l.subcategory);

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

  final position = await Geolocator.getCurrentPosition();

  // Anti-fraud: reject mocked/spoofed locations from "Fake GPS" apps. On
  // Android, isMocked is set when the fix comes from a mock location provider
  // (a fake-GPS app selected in Developer options). iOS/web report false.
  if (position.isMocked) {
    throw 'Fake GPS detected. Please turn off any mock-location / Fake GPS app '
        'and disable "mock location" in Developer options to use PakBazar.';
  }

  return position;
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

Future<void> blockUser(String otherUid) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || otherUid.isEmpty || otherUid == uid) return;
  blockedUserIds.add(otherUid);
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('blocked')
      .doc(otherUid)
      .set({'blockedAt': Timestamp.now()});
}

Future<void> unblockUser(String otherUid) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  blockedUserIds.remove(otherUid);
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('blocked')
      .doc(otherUid)
      .delete();
}

// ---------------------------------------------------------------------------
// Trust & reviews + discovery helpers
// ---------------------------------------------------------------------------

/// Read-only star display. Pass [count] to also show "4.5 (12)".
Future<void> submitSellerReview({
  required String sellerId,
  required int rating,
  required String text,
}) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) return;

  final fs = FirebaseFirestore.instance;
  final reviewRef = fs
      .collection('users')
      .doc(sellerId)
      .collection('reviews')
      .doc(me.uid);

  // Write only the reviewer's own review doc (one per user, doc id == uid,
  // a validated 1-5 stars). The seller's aggregate ratingSum/ratingCount is
  // recomputed server-side by the onReviewWrite Cloud Function from this
  // subcollection — clients can no longer write those fields directly, so a
  // rating cannot be forged.
  await reviewRef.set({
    'reviewerId': me.uid,
    'reviewerName': me.email ?? 'User',
    'rating': rating,
    'text': text.trim(),
    'createdAt': Timestamp.now(),
  });
}

// ---------------------------------------------------------------------------
// Recent searches (Home "Recent Searches" section)
//
// Stored on the device with SharedPreferences, NOT in Firestore — this is a
// convenience shortcut, so it needs no schema, no rules and no extra reads.
// ---------------------------------------------------------------------------

/// One entry in the home "Recent Searches" rail.
class RecentSearch {
  final String query;
  final String category;
  final String city;

  /// Thumbnail of the first result at the time of the search (optional).
  final String imageUrl;

  const RecentSearch({
    required this.query,
    this.category = '',
    this.city = '',
    this.imageUrl = '',
  });

  /// Same search if the query + scope match (case-insensitively).
  String get key =>
      '${query.trim().toLowerCase()}|${category.toLowerCase()}|${city.toLowerCase()}';

  Map<String, dynamic> toMap() => {
    'q': query,
    'c': category,
    'city': city,
    'img': imageUrl,
  };

  static RecentSearch? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final q = raw['q']?.toString().trim() ?? '';
    if (q.isEmpty) return null;
    return RecentSearch(
      query: q,
      category: raw['c']?.toString() ?? '',
      city: raw['city']?.toString() ?? '',
      imageUrl: raw['img']?.toString() ?? '',
    );
  }
}

const String _recentSearchesPrefKey = 'recent_searches_v1';
const int _maxRecentSearches = 10;

/// The device's recent searches, newest first. Notifies listeners so the home
/// section refreshes without a manual reload.
final ValueNotifier<List<RecentSearch>> recentSearches =
    ValueNotifier<List<RecentSearch>>(const []);

/// Loads recent searches from disk into [recentSearches]. Safe to call twice.
Future<void> loadRecentSearches() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentSearchesPrefKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    recentSearches.value = decoded
        .map(RecentSearch.fromMap)
        .whereType<RecentSearch>()
        .take(_maxRecentSearches)
        .toList(growable: false);
  } catch (_) {
    // A corrupt entry must never break the home screen.
  }
}

Future<void> _persistRecentSearches() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentSearchesPrefKey,
      jsonEncode(recentSearches.value.map((s) => s.toMap()).toList()),
    );
  } catch (_) {}
}

/// Remembers a search the user just ran, de-duplicating and capping the list.
Future<void> addRecentSearch(RecentSearch search) async {
  if (search.query.trim().isEmpty) return;
  final next = [
    search,
    ...recentSearches.value.where((s) => s.key != search.key),
  ].take(_maxRecentSearches).toList(growable: false);
  recentSearches.value = next;
  await _persistRecentSearches();
}

/// Removes one remembered search (the × on its card).
Future<void> removeRecentSearch(RecentSearch search) async {
  recentSearches.value = recentSearches.value
      .where((s) => s.key != search.key)
      .toList(growable: false);
  await _persistRecentSearches();
}

/// Clears the whole list ("Clear" in the section header).
Future<void> clearRecentSearches() async {
  recentSearches.value = const [];
  await _persistRecentSearches();
}

/// Records that the current user viewed a listing (for the "Recently viewed"
/// rail on Home). Best-effort; failures are ignored.
Future<void> recordRecentlyViewed(Listing listing) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || listing.id.isEmpty) return;
  // The rail is drawn from the device, so update that FIRST and unconditionally
  // — it is what the user will actually see, and it must not wait on, or be
  // lost by, a network write.
  await cacheRecentlyViewed(listing);
  await userSession.refreshRecentlyViewed();
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('recentlyViewed')
        .doc(listing.id)
        .set({...listing.toMap(), 'viewedAt': Timestamp.now()});
  } catch (_) {
    // Non-critical.
  }
}

// ---------------------------------------------------------------------------
// Continue Browsing, on the device.
//
// The rail is a list of ads THIS user opened, on THIS phone, moments ago — so
// the phone already has every one of them and does not need to ask a database
// what it just did. It used to cost ten document reads on every launch and
// every resume, and before that a permanent listener.
//
// The Firestore copy is still written, because it is what carries the rail
// across to another device, and it is what the app falls back to on a fresh
// install. It is simply no longer the thing the rail is drawn from.
//
// Same reasoning as Recent Searches above, and the same storage.
// ---------------------------------------------------------------------------

const String _kRecentlyViewedKey = 'recently_viewed_v1';

/// How many the rail keeps. Matches the Firestore query it replaces.
const int kRecentlyViewedCap = 10;

/// A listing as JSON.
///
/// `toMap` is built for Firestore, so its timestamps are Firestore
/// [Timestamp] objects — which jsonEncode cannot encode, and which threw
/// straight into the catch below, storing nothing at all while looking like it
/// worked. Listing.fromMap already accepts milliseconds, so they go out that
/// way and come back in unchanged.
String _encodeListing(Listing l) => jsonEncode({
  'id': l.id,
  for (final e in l.toMap().entries)
    e.key: e.value is Timestamp
        ? (e.value as Timestamp).millisecondsSinceEpoch
        : e.value,
});

/// Remembers an ad locally, newest first.
Future<void> cacheRecentlyViewed(Listing listing) async {
  if (listing.id.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_kRecentlyViewedKey) ?? const [];
    final out = <String>[_encodeListing(listing)];
    for (final raw in existing) {
      if (out.length >= kRecentlyViewedCap) break;
      try {
        // Re-opening an ad moves it to the front rather than listing it twice.
        if (jsonDecode(raw)['id'] == listing.id) continue;
      } catch (_) {
        continue; // unreadable entry from an older format
      }
      out.add(raw);
    }
    await prefs.setStringList(_kRecentlyViewedKey, out);
  } catch (_) {
    // A convenience rail is never worth an error.
  }
}

/// The locally remembered ads, newest first.
Future<List<Listing>> loadCachedRecentlyViewed() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kRecentlyViewedKey) ?? const [];
    final out = <Listing>[];
    for (final entry in raw) {
      try {
        final map = (jsonDecode(entry) as Map).cast<String, dynamic>();
        final id = map['id']?.toString() ?? '';
        if (id.isNotEmpty) out.add(Listing.fromMap(id, map));
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Replaces the local list, used to seed it from Firestore on a new device.
Future<void> seedCachedRecentlyViewed(List<Listing> listings) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRecentlyViewedKey, [
      for (final l in listings.take(kRecentlyViewedCap)) _encodeListing(l),
    ]);
  } catch (_) {}
}

/// Forgets the list, so a shared phone does not show one person's browsing to
/// the next.
Future<void> clearCachedRecentlyViewed() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecentlyViewedKey);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// App root + auth
// ---------------------------------------------------------------------------
