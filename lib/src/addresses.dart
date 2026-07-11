part of '../main.dart';

// Buyer delivery addresses: model, Pakistani-mobile validation, and Firestore
// CRUD under users/{uid}/addresses/{addressId}. The checkout flow attaches a
// full snapshot of the chosen address onto each order (see placeListingOrder),
// so editing a saved address later never rewrites past orders.

/// Pakistan's provinces / federal territories, for the address form dropdown.
const List<String> pakProvinces = [
  'Punjab',
  'Sindh',
  'Khyber Pakhtunkhwa',
  'Balochistan',
  'Islamabad Capital Territory',
  'Gilgit-Baltistan',
  'Azad Kashmir',
];

/// Suggested labels for a saved address.
const List<String> addressLabels = ['Home', 'Office', 'Other'];

/// True if [raw] is a valid Pakistani mobile number in any common format
/// (03XXXXXXXXX, +923XXXXXXXXX, 00923XXXXXXXXX, or a bare 3XXXXXXXXX). Reuses
/// [normalizePhoneForWhatsApp] to reduce to international digits, then checks it
/// is country code 92 + a mobile subscriber number starting with 3 (12 digits).
bool isValidPakMobile(String raw) {
  final n = normalizePhoneForWhatsApp(raw); // e.g. '923001234567'
  return n.length == 12 && n.startsWith('923');
}

/// Normalizes a Pakistani mobile into one consistent stored format,
/// '+923XXXXXXXXX' (E.164). Returns '' when [raw] is not a valid mobile.
String normalizePakMobile(String raw) {
  if (!isValidPakMobile(raw)) return '';
  return '+${normalizePhoneForWhatsApp(raw)}';
}

/// A buyer's saved delivery address.
class DeliveryAddress {
  final String id;
  String label;
  String fullName;
  String phone;
  String province;
  String city;
  String area;
  String streetAddress;
  String houseOrBuilding;
  String landmark;
  String postalCode;
  String deliveryInstructions;
  bool isDefault;
  Timestamp? createdAt;
  Timestamp? updatedAt;

  DeliveryAddress({
    this.id = '',
    this.label = 'Home',
    this.fullName = '',
    this.phone = '',
    this.province = '',
    this.city = '',
    this.area = '',
    this.streetAddress = '',
    this.houseOrBuilding = '',
    this.landmark = '',
    this.postalCode = '',
    this.deliveryInstructions = '',
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  /// The fields that MUST be present before an order can be placed. Optional
  /// fields (landmark, postalCode, deliveryInstructions) are excluded.
  bool get isComplete =>
      fullName.trim().isNotEmpty &&
      isValidPakMobile(phone) &&
      province.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      area.trim().isNotEmpty &&
      streetAddress.trim().isNotEmpty &&
      houseOrBuilding.trim().isNotEmpty;

  /// One-line address summary for list / checkout display.
  String get shortSummary => [
    houseOrBuilding,
    streetAddress,
    area,
    city,
    province,
  ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');

  DeliveryAddress copy() => DeliveryAddress(
    id: id,
    label: label,
    fullName: fullName,
    phone: phone,
    province: province,
    city: city,
    area: area,
    streetAddress: streetAddress,
    houseOrBuilding: houseOrBuilding,
    landmark: landmark,
    postalCode: postalCode,
    deliveryInstructions: deliveryInstructions,
    isDefault: isDefault,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory DeliveryAddress.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return DeliveryAddress(
      id: doc.id,
      label: d['label']?.toString() ?? 'Home',
      fullName: d['fullName']?.toString() ?? '',
      phone: d['phone']?.toString() ?? '',
      province: d['province']?.toString() ?? '',
      city: d['city']?.toString() ?? '',
      area: d['area']?.toString() ?? '',
      streetAddress: d['streetAddress']?.toString() ?? '',
      houseOrBuilding: d['houseOrBuilding']?.toString() ?? '',
      landmark: d['landmark']?.toString() ?? '',
      postalCode: d['postalCode']?.toString() ?? '',
      deliveryInstructions: d['deliveryInstructions']?.toString() ?? '',
      isDefault: d['isDefault'] == true,
      createdAt: d['createdAt'] is Timestamp
          ? d['createdAt'] as Timestamp
          : null,
      updatedAt: d['updatedAt'] is Timestamp
          ? d['updatedAt'] as Timestamp
          : null,
    );
  }

  /// Document map for the addresses subcollection. Phone is stored normalized.
  /// `isDefault` and timestamps are written by the CRUD helpers, not here.
  Map<String, dynamic> toMap() => {
    'label': label.trim().isEmpty ? 'Home' : label.trim(),
    'fullName': fullName.trim(),
    'phone': normalizePakMobile(phone),
    'province': province.trim(),
    'city': city.trim(),
    'area': area.trim(),
    'streetAddress': streetAddress.trim(),
    'houseOrBuilding': houseOrBuilding.trim(),
    'landmark': landmark.trim(),
    'postalCode': postalCode.trim(),
    'deliveryInstructions': deliveryInstructions.trim(),
  };

  /// The immutable snapshot embedded in an order document. Excludes isDefault /
  /// timestamps so the order keeps the address exactly as it was at purchase.
  Map<String, dynamic> snapshotMap() => {
    'label': label.trim(),
    'fullName': fullName.trim(),
    'phone': normalizePakMobile(phone),
    'province': province.trim(),
    'city': city.trim(),
    'area': area.trim(),
    'streetAddress': streetAddress.trim(),
    'houseOrBuilding': houseOrBuilding.trim(),
    'landmark': landmark.trim(),
    'postalCode': postalCode.trim(),
    'deliveryInstructions': deliveryInstructions.trim(),
  };
}

/// Addresses subcollection for a given user.
CollectionReference<Map<String, dynamic>> _addressCol(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('addresses');

/// Orders a list of addresses: the default first, then newest created first.
void _sortAddresses(List<DeliveryAddress> list) {
  list.sort((a, b) {
    if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
    return bt.compareTo(at);
  });
}

/// Live stream of the signed-in buyer's saved addresses (default first).
Stream<List<DeliveryAddress>> addressStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const <DeliveryAddress>[]);
  return _addressCol(uid).snapshots().map((snap) {
    final list = snap.docs.map(DeliveryAddress.fromDoc).toList();
    _sortAddresses(list);
    return list;
  });
}

/// Loads the buyer's default address (or the most recent) for checkout
/// pre-selection. Returns null when none are saved.
Future<DeliveryAddress?> loadDefaultAddress() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final snap = await _addressCol(uid).get();
  if (snap.docs.isEmpty) return null;
  final list = snap.docs.map(DeliveryAddress.fromDoc).toList();
  _sortAddresses(list);
  return list.first;
}

/// Creates a new address, returning its id. The first address (or one the user
/// explicitly marks default) becomes the default; any previous default is
/// cleared in the same batch so exactly one default exists.
Future<String> saveNewAddress(DeliveryAddress a) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return '';
  final col = _addressCol(uid);
  final existing = await col.get();
  final makeDefault = a.isDefault || existing.docs.isEmpty;
  final batch = FirebaseFirestore.instance.batch();
  if (makeDefault) {
    for (final d in existing.docs) {
      if (d.data()['isDefault'] == true) {
        batch.update(d.reference, {'isDefault': false});
      }
    }
  }
  final ref = col.doc();
  batch.set(ref, {
    ...a.toMap(),
    'isDefault': makeDefault,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return ref.id;
}

/// Updates an existing address. If it is set default, clears the flag on the
/// others so exactly one default remains.
Future<void> updateExistingAddress(DeliveryAddress a) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || a.id.isEmpty) return;
  final col = _addressCol(uid);
  final batch = FirebaseFirestore.instance.batch();
  if (a.isDefault) {
    final existing = await col.get();
    for (final d in existing.docs) {
      if (d.id != a.id && d.data()['isDefault'] == true) {
        batch.update(d.reference, {'isDefault': false});
      }
    }
  }
  batch.set(col.doc(a.id), {
    ...a.toMap(),
    'isDefault': a.isDefault,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  await batch.commit();
}

/// Deletes an address. If it was the default and others remain, the most recent
/// remaining address is promoted to default.
Future<void> deleteAddress(DeliveryAddress a) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || a.id.isEmpty) return;
  final col = _addressCol(uid);
  await col.doc(a.id).delete();
  if (a.isDefault) {
    final rest = await col.get();
    if (rest.docs.isNotEmpty) {
      final list = rest.docs.map(DeliveryAddress.fromDoc).toList();
      _sortAddresses(list);
      await col.doc(list.first.id).set({
        'isDefault': true,
      }, SetOptions(merge: true));
    }
  }
}

/// Marks one address as the default and clears the flag on every other.
Future<void> setDefaultAddress(String addressId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final col = _addressCol(uid);
  final existing = await col.get();
  final batch = FirebaseFirestore.instance.batch();
  for (final d in existing.docs) {
    final isTarget = d.id == addressId;
    if ((d.data()['isDefault'] == true) != isTarget) {
      batch.update(d.reference, {'isDefault': isTarget});
    }
  }
  await batch.commit();
}
