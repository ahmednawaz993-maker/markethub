part of '../main.dart';

// Top-level helper functions and shared constants.


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

bool isAdminUser() =>
    adminEmails.contains(FirebaseAuth.instance.currentUser?.email);

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
  ('approvals', 'Approvals'),
  ('verifyId', 'Verify ID'),
  ('payments', 'Payments'),
  ('escrow', 'Escrow'),
  ('featured', 'Featured'),
  ('feedback', 'Feedback'),
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
];

/// Permission codes granted to the current staff member (empty for the super
/// admin, who bypasses these checks, and for non-staff users). Loaded at
/// startup by [loadStaffPermissions].
final Set<String> staffPermissions = <String>{};

/// Loads the signed-in user's staff permissions from `staff/{email}`. The super
/// admin needs no entry. Safe to call repeatedly.
Future<void> loadStaffPermissions() async {
  staffPermissions.clear();
  final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
  if (email == null || isSuperAdmin()) return;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('staff')
        .doc(email)
        .get();
    final d = doc.data();
    if (d != null && d['active'] != false) {
      final perms = (d['permissions'] as Map?) ?? const {};
      perms.forEach((k, v) {
        if (v == true) staffPermissions.add(k.toString());
      });
    }
  } catch (_) {}
}

/// True if the user may act on the given admin area (super admin or granted).
bool hasAdminPerm(String code) =>
    isSuperAdmin() || staffPermissions.contains(code);

/// True if the user can open the admin panel at all (super admin or any staff
/// permission).
bool canOpenAdminPanel() =>
    isSuperAdmin() || staffPermissions.isNotEmpty;

/// Price with an optional unit suffix, e.g. "Rs 250 / kg".
String priceLabel(Listing l) =>
    formatPrice(l.price) + (l.unit.isEmpty ? '' : ' / ${l.unit}');

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

  return Geolocator.getCurrentPosition();
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
  final reviewRef =
      fs.collection('users').doc(sellerId).collection('reviews').doc(me.uid);

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
