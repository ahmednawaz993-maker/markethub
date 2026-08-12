part of '../main.dart';

// ---------------------------------------------------------------------------
// Multi-seller shopping cart (Phase 1).
//
// A buyer can add products from many sellers into ONE cart. This is additive:
// the existing single-listing "Buy Now" flow (openCheckout) is untouched.
//
// Storage:
//   • Signed-in buyer → users/{uid}/cart/{listingId} (one doc per line item;
//     the listingId is the doc id so re-adding a product increments quantity
//     instead of duplicating). Auto-persists across logout/login.
//   • Guest (logged-out) → a JSON list in SharedPreferences. On the next login
//     it is merged into the account cart (mergeGuestCartIntoAccount) and cleared.
//
// Stock is seller-controlled and boolean (a listing is purchasable only while
// status == 'in_stock'); there is no numeric inventory, so "validate stock"
// means the listing must be available + buyable when added.
// ---------------------------------------------------------------------------

const String _guestCartKey = 'guest_cart_v1';

/// Live item count of the GUEST cart (drives the badge while logged out). The
/// signed-in badge streams Firestore directly instead.
final ValueNotifier<int> guestCartCount = ValueNotifier<int>(0);

/// The signed-in buyer's cart collection, or null when logged out.
CollectionReference<Map<String, dynamic>>? _cartCol() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('cart');
}

/// One line item in the cart. Field shape is identical in Firestore and in the
/// guest (SharedPreferences) store, so [toMap]/[fromMap] serve both.
class CartItem {
  final String listingId;
  final String title;
  final String imageUrl;
  final String price; // unit price, same string form as Listing.price
  final String sellerId;
  final String sellerName;
  final String deliveryFee;
  final bool codAvailable;
  int quantity;
  final int addedAtMs;

  CartItem({
    required this.listingId,
    required this.title,
    required this.imageUrl,
    required this.price,
    required this.sellerId,
    required this.sellerName,
    this.deliveryFee = '',
    this.codAvailable = false,
    this.quantity = 1,
    this.addedAtMs = 0,
  });

  double get unitPrice => parsePrice(price).toDouble();
  double get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toMap() => {
    'listingId': listingId,
    'title': title,
    'imageUrl': imageUrl,
    'price': price,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'deliveryFee': deliveryFee,
    'codAvailable': codAvailable,
    'quantity': quantity,
    'addedAtMs': addedAtMs,
  };

  factory CartItem.fromMap(Map<String, dynamic> m) => CartItem(
    listingId: m['listingId']?.toString() ?? '',
    title: m['title']?.toString() ?? '',
    imageUrl: m['imageUrl']?.toString() ?? '',
    price: m['price']?.toString() ?? '0',
    sellerId: m['sellerId']?.toString() ?? '',
    sellerName: m['sellerName']?.toString() ?? 'Seller',
    deliveryFee: m['deliveryFee']?.toString() ?? '',
    codAvailable: m['codAvailable'] == true,
    quantity: (m['quantity'] as num?)?.toInt() ?? 1,
    addedAtMs: (m['addedAtMs'] as num?)?.toInt() ?? 0,
  );

  factory CartItem.fromListing(Listing l, {int quantity = 1}) => CartItem(
    listingId: l.id,
    title: l.title,
    imageUrl: l.imageUrl.isNotEmpty
        ? l.imageUrl
        : (l.images.isNotEmpty ? l.images.first : ''),
    price: l.price,
    sellerId: l.userId,
    sellerName: l.sellerName,
    deliveryFee: l.deliveryFee,
    codAvailable: l.codAvailable,
    quantity: quantity,
    addedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}

// --- Pure helpers (unit-tested) --------------------------------------------

/// Items sharing one seller, with the seller's subtotal.
class SellerGroup {
  final String sellerId;
  final String sellerName;
  final List<CartItem> items;
  SellerGroup(this.sellerId, this.sellerName, this.items);

  double get subtotal => items.fold(0.0, (a, i) => a + i.lineTotal);
  int get count => items.fold(0, (a, i) => a + i.quantity);
}

/// Groups cart items by seller, preserving first-seen order.
List<SellerGroup> groupBySeller(List<CartItem> items) {
  final order = <String>[];
  final byId = <String, List<CartItem>>{};
  final names = <String, String>{};
  for (final i in items) {
    if (!byId.containsKey(i.sellerId)) {
      byId[i.sellerId] = [];
      order.add(i.sellerId);
    }
    byId[i.sellerId]!.add(i);
    names[i.sellerId] = i.sellerName;
  }
  return [
    for (final id in order) SellerGroup(id, names[id] ?? 'Seller', byId[id]!),
  ];
}

/// Grand total of all line items (item prices only; delivery is computed at
/// checkout in a later phase).
double cartTotal(List<CartItem> items) =>
    items.fold(0.0, (a, i) => a + i.lineTotal);

/// Total number of units across the cart (drives the badge).
int cartUnitCount(List<CartItem> items) =>
    items.fold(0, (a, i) => a + i.quantity);

// ---------------------------------------------------------------------------
// Master order model (Phase 9).
//
// A `masterOrders/{id}` document is the buyer's single multi-seller checkout
// intent. The onMasterOrderCreated Cloud Function fans it out into one
// `orders/{id}` sub-order per seller (each an ordinary order, so all
// fulfillment / escrow / payout logic is reused) and then stamps the master
// with the order number, seller/package counts and — as packages progress —
// aggregate delivery counts (Phase 7). This typed view makes that Firestore
// mapping explicit and testable; it is read-only (the function owns writes).
// ---------------------------------------------------------------------------

/// Payment lifecycle of a master order, mirrored from `paymentStatus`.
/// unpaid → review (proof submitted) → held (all sub-orders in escrow).
enum MasterPayState { unpaid, review, held, unknown }

class MasterOrder {
  final String id;
  final String orderNumber;
  final String buyerId;
  final String buyerName;
  final double itemsTotal;
  final String paymentMethod; // 'cod' | 'escrow'
  final String paymentStatus; // 'unpaid' | 'review' | 'held' | ''
  final String status; // 'pending' | 'placed' | 'in_escrow' | 'failed' | ...
  final List<String> sellerOrderIds;
  final int sellerCount;
  final int packageCount;
  final int deliveredCount;
  final int activeCount;
  final bool allDelivered;
  final int createdAtMs;

  const MasterOrder({
    required this.id,
    this.orderNumber = '',
    this.buyerId = '',
    this.buyerName = '',
    this.itemsTotal = 0,
    this.paymentMethod = '',
    this.paymentStatus = '',
    this.status = '',
    this.sellerOrderIds = const [],
    this.sellerCount = 0,
    this.packageCount = 0,
    this.deliveredCount = 0,
    this.activeCount = 0,
    this.allDelivered = false,
    this.createdAtMs = 0,
  });

  factory MasterOrder.fromMap(String id, Map<String, dynamic> m) {
    final ids =
        (m['sellerOrderIds'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return MasterOrder(
      id: id,
      orderNumber: m['orderNumber']?.toString() ?? '',
      buyerId: m['buyerId']?.toString() ?? '',
      buyerName: m['buyerName']?.toString() ?? '',
      itemsTotal: (m['itemsTotal'] as num?)?.toDouble() ?? 0,
      paymentMethod: m['paymentMethod']?.toString() ?? '',
      paymentStatus: m['paymentStatus']?.toString() ?? '',
      status: m['status']?.toString() ?? '',
      sellerOrderIds: ids,
      // packageCount (Phase 7) is authoritative once written; before that we
      // fall back to sellerCount, then to the fan-out id list length.
      sellerCount: (m['sellerCount'] as num?)?.toInt() ?? ids.length,
      packageCount:
          (m['packageCount'] as num?)?.toInt() ??
          (m['sellerCount'] as num?)?.toInt() ??
          ids.length,
      deliveredCount: (m['deliveredCount'] as num?)?.toInt() ?? 0,
      activeCount: (m['activeCount'] as num?)?.toInt() ?? 0,
      allDelivered: m['allDelivered'] == true,
      createdAtMs: (m['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
    );
  }

  /// Convenience for a Firestore document snapshot.
  factory MasterOrder.fromDoc(DocumentSnapshot doc) => MasterOrder.fromMap(
    doc.id,
    (doc.data() as Map<String, dynamic>?) ?? const {},
  );

  bool get isCod => paymentMethod == 'cod';
  bool get isMultiPackage => packageCount > 1;
  bool get isFailed => status == 'failed';
  bool get isPaid => paymentStatus == 'held';

  MasterPayState get payState => switch (paymentStatus) {
    'unpaid' => MasterPayState.unpaid,
    'review' => MasterPayState.review,
    'held' => MasterPayState.held,
    _ => MasterPayState.unknown,
  };

  /// Short progress label, e.g. "1/3 delivered" → "All delivered".
  String get progressLabel => allDelivered
      ? 'All delivered'
      : '$deliveredCount/$packageCount delivered';

  /// One-line payment descriptor for admin/buyer summaries.
  String get paymentLabel {
    if (isCod) return 'COD';
    return switch (payState) {
      MasterPayState.held => 'Online · held',
      MasterPayState.review => 'Online · under review',
      MasterPayState.unpaid => 'Online · unpaid',
      MasterPayState.unknown => 'Online',
    };
  }
}

/// A green info strip used when a cart/checkout spans multiple sellers.
Widget _multiSellerBanner(String text) => Container(
  margin: const EdgeInsets.only(bottom: 10),
  padding: const EdgeInsets.all(10),
  // Opaque light surface (not a translucent tint) so the text is readable over
  // the navy gradient rather than dark-on-navy.
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: kPakGreen.withValues(alpha: 0.30)),
  ),
  child: Row(
    children: [
      const Icon(Icons.local_shipping_outlined, size: 16, color: kPakGreen),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
        ),
      ),
    ],
  ),
);

// --- Guest (SharedPreferences) store ---------------------------------------

Future<List<CartItem>> _guestLoad() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList(_guestCartKey) ?? const [];
  final out = <CartItem>[];
  for (final s in raw) {
    try {
      out.add(CartItem.fromMap(jsonDecode(s) as Map<String, dynamic>));
    } catch (_) {}
  }
  return out;
}

Future<void> _guestSave(List<CartItem> items) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    _guestCartKey,
    items.map((i) => jsonEncode(i.toMap())).toList(),
  );
  guestCartCount.value = cartUnitCount(items);
}

/// Loads the guest cart count once at startup so the badge is correct before
/// the cart screen is opened.
Future<void> loadGuestCartCount() async {
  if (FirebaseAuth.instance.currentUser != null) return;
  guestCartCount.value = cartUnitCount(await _guestLoad());
}

// --- Mutations (route to Firestore when signed in, else guest store) --------

/// Adds [l] to the cart (or increments its quantity). Validates availability
/// first. Returns true when added, false when the listing can't be bought.
Future<bool> addListingToCart(Listing l, {int qty = 1}) async {
  if (!(l.isAvailableForSale && isBuyable(l))) return false;
  final item = CartItem.fromListing(l, quantity: qty);
  final col = _cartCol();
  if (col != null) {
    final ref = col.doc(l.id);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final existing = snap.exists
          ? (snap.data()?['quantity'] as num?)?.toInt() ?? 0
          : 0;
      final map = item.toMap();
      map['quantity'] = existing + qty;
      // Keep the original addedAt so ordering stays stable on re-add.
      if (snap.exists && snap.data()?['addedAtMs'] != null) {
        map['addedAtMs'] = snap.data()!['addedAtMs'];
      }
      tx.set(ref, map);
    });
  } else {
    final items = await _guestLoad();
    final idx = items.indexWhere((i) => i.listingId == l.id);
    if (idx >= 0) {
      items[idx].quantity += qty;
    } else {
      items.add(item);
    }
    await _guestSave(items);
  }
  return true;
}

/// Sets the quantity for a line item (removes it when [qty] < 1).
Future<void> updateCartQty(String listingId, int qty) async {
  if (qty < 1) return removeFromCart(listingId);
  // Clamp to a sane upper bound (stock is boolean, not numeric) so a stuck
  // stepper can't create an absurd line total.
  final n = qty > 99 ? 99 : qty;
  final col = _cartCol();
  if (col != null) {
    try {
      await col.doc(listingId).update({'quantity': n});
    } on FirebaseException catch (e) {
      // The line was removed in another session/tab between render and tap —
      // updating a missing doc throws not-found; ignore it rather than crash.
      if (e.code != 'not-found') rethrow;
    }
  } else {
    final items = await _guestLoad();
    final i = items.indexWhere((e) => e.listingId == listingId);
    if (i >= 0) {
      items[i].quantity = qty;
      await _guestSave(items);
    }
  }
}

Future<void> removeFromCart(String listingId) async {
  final col = _cartCol();
  if (col != null) {
    await col.doc(listingId).delete();
  } else {
    final items = await _guestLoad()
      ..removeWhere((e) => e.listingId == listingId);
    await _guestSave(items);
  }
}

Future<void> clearCart() async {
  final col = _cartCol();
  if (col != null) {
    final snap = await col.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  } else {
    await _guestSave(<CartItem>[]);
  }
}

/// On login, folds any guest cart into the account cart (summing quantities for
/// products already present), then clears the guest store. Safe no-op when
/// logged out or the guest cart is empty.
Future<void> mergeGuestCartIntoAccount() async {
  final col = _cartCol();
  if (col == null) return;
  final items = await _guestLoad();
  if (items.isEmpty) return;
  for (final it in items) {
    final ref = col.doc(it.listingId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final existing = snap.exists
          ? (snap.data()?['quantity'] as num?)?.toInt() ?? 0
          : 0;
      final map = it.toMap();
      map['quantity'] = existing + it.quantity;
      if (snap.exists && snap.data()?['addedAtMs'] != null) {
        map['addedAtMs'] = snap.data()!['addedAtMs'];
      }
      tx.set(ref, map);
    });
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_guestCartKey);
  guestCartCount.value = 0;
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------

/// App-bar cart icon with a live item-count badge. Streams Firestore when
/// signed in; watches [guestCartCount] when logged out.
class CartBell extends StatelessWidget {
  const CartBell({super.key});

  @override
  Widget build(BuildContext context) {
    final open = IconButton(
      icon: const Icon(Icons.shopping_cart_outlined),
      tooltip: 'Cart',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CartScreen()),
      ),
    );
    Widget badge(int count) => Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      offset: const Offset(-4, 4),
      child: open,
    );

    final col = _cartCol();
    if (col == null) {
      return ValueListenableBuilder<int>(
        valueListenable: guestCartCount,
        builder: (_, n, _) => badge(n),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final items =
            snap.data?.docs.map((d) => CartItem.fromMap(d.data())).toList() ??
            const <CartItem>[];
        return badge(cartUnitCount(items));
      },
    );
  }
}

/// The cart screen: line items grouped by seller with per-seller subtotals,
/// quantity steppers, remove, and a grand total.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<CartItem> _items = [];
  bool _loading = true;

  bool get _signedIn => _cartCol() != null;

  @override
  void initState() {
    super.initState();
    final col = _cartCol();
    if (col != null) {
      _sub = col.orderBy('addedAtMs').snapshots().listen((snap) {
        if (!mounted) return;
        setState(() {
          _items = snap.docs.map((d) => CartItem.fromMap(d.data())).toList();
          _loading = false;
        });
      });
    } else {
      _guestLoad().then((items) {
        if (!mounted) return;
        setState(() {
          _items = items;
          _loading = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reloadGuest() async {
    final items = await _guestLoad();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _setQty(CartItem it, int q) async {
    await updateCartQty(it.listingId, q);
    if (!_signedIn) await _reloadGuest();
  }

  Future<void> _remove(CartItem it) async {
    await removeFromCart(it.listingId);
    if (!_signedIn) await _reloadGuest();
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupBySeller(_items);
    final total = cartTotal(_items);
    return Scaffold(
      appBar: AppBar(
        title: Text('Cart (${cartUnitCount(_items)})'),
        actions: [
          if (_items.isNotEmpty)
            TextButton(onPressed: _confirmClear, child: const Text('Clear')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const EmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Your cart is empty',
              subtitle: 'Add products and they will show up here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.lg,
              ),
              children: [
                if (groups.length > 1)
                  _multiSellerBanner(
                    'Items from ${groups.length} sellers. They ship as '
                    'separate packages.',
                  ),
                for (final g in groups) _sellerGroupCard(g),
              ],
            ),
      bottomNavigationBar: _items.isEmpty ? null : _totalBar(total),
    );
  }

  Widget _sellerGroupCard(SellerGroup g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, size: 16, color: kPakGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    g.sellerName.isEmpty ? 'Seller' : g.sellerName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(),
            for (final it in g.items) _lineItem(it),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Seller subtotal: ${formatPrice(g.subtotal.toStringAsFixed(0))}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineItem(CartItem it) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadius.rSm,
            child: SizedBox(
              width: 52,
              height: 52,
              child: AppNetworkImage(url: it.imageUrl, iconSize: 20),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPrice(it.unitPrice.toStringAsFixed(0)),
                  style: const TextStyle(color: kPakGreen),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _qtyButton(
                      Icons.remove,
                      () => _setQty(it, it.quantity - 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '${it.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    _qtyButton(Icons.add, () => _setQty(it, it.quantity + 1)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      tooltip: 'Remove',
                      onPressed: () => _remove(it),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16),
    ),
  );

  Widget _totalBar(double total) {
    // Fixed bar above the system inset, so Checkout is always reachable.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Cart total',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      formatPrice(total.toStringAsFixed(0)),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kPakGreen,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => openCartCheckout(context, _items),
                icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                label: const Text('Checkout'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('This removes all items from your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await clearCart();
    if (!_signedIn) await _reloadGuest();
  }
}

// ---------------------------------------------------------------------------
// Multi-seller checkout (Phase 3)
// ---------------------------------------------------------------------------

/// Writes a multi-seller checkout intent (masterOrders/{id}). A Cloud Function
/// (onMasterOrderCreated) validates each listing, splits the cart into one
/// per-seller order (orders/{id}) with a unique number, and notifies sellers.
/// The cart is cleared once the intent is safely written. Returns the master id.
Future<String> placeCartOrder({
  required List<CartItem> items,
  required DeliveryAddress address,
  required String paymentMethod, // 'cod' | 'escrow'
  String notes = '',
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw CheckoutException('Please log in to place an order.');
  if (items.isEmpty) throw CheckoutException('Your cart is empty.');
  if (!address.isComplete) {
    throw CheckoutException(
      'Please provide a complete delivery address first.',
    );
  }
  final fs = FirebaseFirestore.instance;
  final masterRef = fs.collection('masterOrders').doc();
  try {
    await masterRef.set({
      'buyerId': user.uid,
      'buyerName': address.fullName.trim(),
      'buyerPhone': normalizePakMobile(address.phone),
      'deliveryAddress': address.snapshotMap(),
      'items': [
        for (final i in items)
          {
            'listingId': i.listingId,
            'sellerId': i.sellerId,
            'sellerName': i.sellerName,
            'title': i.title,
            'quantity': i.quantity,
          },
      ],
      'sellerCount': groupBySeller(items).length,
      'itemsTotal': cartTotal(items),
      'paymentMethod': paymentMethod == 'cod' ? 'cod' : 'escrow',
      'notes': notes.trim(),
      'status': 'pending',
      'createdAt': Timestamp.now(),
    });
  } catch (e) {
    throw CheckoutException(_friendlyOrderError(e));
  }
  await clearCart();
  return masterRef.id;
}

/// Gates on ID verification, then opens the multi-seller checkout screen.
Future<void> openCartCheckout(
  BuildContext context,
  List<CartItem> items,
) async {
  if (items.isEmpty) return;
  if (!await ensureVerified(context)) return;
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CartCheckoutScreen(items: items)),
  );
}

/// Multi-seller checkout: delivery address + per-seller item groups + payment
/// method + notes + Place Order. Reuses the existing address book (Phase 2).
class CartCheckoutScreen extends StatefulWidget {
  final List<CartItem> items;
  const CartCheckoutScreen({super.key, required this.items});

  @override
  State<CartCheckoutScreen> createState() => _CartCheckoutScreenState();
}

class _CartCheckoutScreenState extends State<CartCheckoutScreen> {
  DeliveryAddress? _address;
  bool _loadingAddress = true;
  bool _submitting = false;
  String _payment = 'escrow';
  final _notes = TextEditingController();

  bool get _allCod => widget.items.every((i) => i.codAvailable);

  @override
  void initState() {
    super.initState();
    loadDefaultAddress().then((a) {
      if (!mounted) return;
      setState(() {
        _address = a;
        _loadingAddress = false;
      });
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool get _canPlace =>
      !_submitting &&
      !_loadingAddress &&
      _address != null &&
      _address!.isComplete &&
      widget.items.isNotEmpty &&
      FirebaseAuth.instance.currentUser != null;

  Future<void> _changeAddress() async {
    final picked = await Navigator.push<DeliveryAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddressBookScreen(selectMode: true),
      ),
    );
    if (picked != null && mounted) setState(() => _address = picked);
  }

  Future<void> _place() async {
    if (!_canPlace) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final itemCount = widget.items.fold<int>(0, (a, i) => a + i.quantity);
    // Item total only — per-seller delivery is computed server-side.
    final cartValue = cartTotal(widget.items);
    trackBeginCheckout(
      value: cartValue,
      itemCount: itemCount,
      paymentMethod: _payment,
    );
    try {
      final masterId = await placeCartOrder(
        items: widget.items,
        address: _address!,
        paymentMethod: _payment,
        notes: _notes.text,
      );
      trackPurchase(
        orderId: masterId,
        value: cartValue,
        paymentMethod: _payment,
        itemCount: itemCount,
      );
    } on CheckoutException catch (e) {
      if (mounted) setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not place the order. Please try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    // Cart is cleared; go to the buyer's orders where the sub-orders appear.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OrdersScreen()),
      (r) => r.isFirst,
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Your order has been submitted to the seller(s).'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupBySeller(widget.items);
    final total = cartTotal(widget.items);
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        children: [
          _addressCard(),
          if (groups.length > 1)
            _multiSellerBanner(
              'Your order will arrive in multiple packages because products '
              'are shipped from different sellers.',
            ),
          for (final g in groups) _sellerGroupCard(g),
          _paymentCard(),
          _notesCard(),
          const SizedBox(height: 8),
          Text(
            'Item total: ${formatPrice(total.toStringAsFixed(0))}',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          Text(
            'A delivery fee (if any) is added per seller and shown on each '
            'order.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderSoft)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Items',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        formatPrice(total.toStringAsFixed(0)),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: kPakGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _canPlace ? _place : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock, size: 18),
                  label: const Text('Place Order'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addressCard() {
    final a = _address;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, size: 18, color: kPakGreen),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Delivery address',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: _submitting ? null : _changeAddress,
                  child: Text(a == null ? 'Add' : 'Change'),
                ),
              ],
            ),
            if (_loadingAddress)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (a == null)
              Text(
                'Please add a complete delivery address before placing your '
                'order.',
                style: TextStyle(color: AppColors.error, fontSize: 13),
              )
            else ...[
              Text(
                '${a.fullName} · ${a.phone}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                [
                  a.houseOrBuilding,
                  a.streetAddress,
                  a.area,
                  a.city,
                  a.province,
                ].where((s) => s.trim().isNotEmpty).join(', '),
                style: const TextStyle(fontSize: 13),
              ),
              if (a.deliveryInstructions.trim().isNotEmpty)
                Text(
                  'Note: ${a.deliveryInstructions}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sellerGroupCard(SellerGroup g) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront, size: 16, color: kPakGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  g.sellerName.isEmpty ? 'Seller' : g.sellerName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(),
          for (final it in g.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${it.title}  ×${it.quantity}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(formatPrice(it.lineTotal.toStringAsFixed(0))),
                ],
              ),
            ),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Subtotal: ${formatPrice(g.subtotal.toStringAsFixed(0))}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _paymentCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment method',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          RadioGroup<String>(
            groupValue: _payment,
            onChanged: (v) {
              if (_submitting || v == null) return;
              setState(() => _payment = v);
            },
            child: Column(
              children: [
                const RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'escrow',
                  activeColor: kPakGreen,
                  title: Text('Pay online (held by PakBazar)'),
                  subtitle: Text(
                    'Held safely until you confirm delivery from each seller.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (_allCod)
                  const RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'cod',
                    activeColor: kPakGreen,
                    title: Text('Cash on Delivery'),
                    subtitle: Text(
                      'Pay cash to each seller when your package arrives.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          if (!_allCod)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Cash on Delivery is unavailable because some items don\'t '
                'offer it.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _notesCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _notes,
        maxLines: 2,
        enabled: !_submitting,
        decoration: const InputDecoration(
          labelText: 'Order notes (optional)',
          border: OutlineInputBorder(),
        ),
      ),
    ),
  );
}

/// Reusable "Add to cart" button used on product screens. Shows feedback and,
/// for guests, a hint that the cart will be saved when they sign in.
class AddToCartButton extends StatefulWidget {
  final Listing listing;
  final bool compact;
  const AddToCartButton({
    super.key,
    required this.listing,
    this.compact = false,
  });

  @override
  State<AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<AddToCartButton> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await addListingToCart(widget.listing);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Added to cart.' : 'This item is not available to buy.',
        ),
        action: ok
            ? SnackBarAction(
                label: 'View cart',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return IconButton(
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_shopping_cart, size: 20),
        tooltip: 'Add to cart',
        onPressed: _busy ? null : _add,
      );
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : _add,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_shopping_cart),
      label: const Text('Add to Cart'),
    );
  }
}
