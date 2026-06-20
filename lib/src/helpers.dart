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

bool isAdminUser() =>
    adminEmails.contains(FirebaseAuth.instance.currentUser?.email);

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
  if (isAdminUser()) return true;
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
