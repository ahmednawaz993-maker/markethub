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
  final col = _cartCol();
  if (col != null) {
    await col.doc(listingId).update({'quantity': qty});
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
      icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
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
            TextButton(
              onPressed: _confirmClear,
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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

  Widget _multiSellerBanner(String text) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: kPakGreen.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.local_shipping_outlined, size: 16, color: kPakGreen),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

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
            borderRadius: BorderRadius.circular(8),
            child: it.imageUrl.isEmpty
                ? Container(
                    width: 52,
                    height: 52,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.image),
                  )
                : Image.network(
                    it.imageUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 52,
                      height: 52,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.image),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Cart total',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Multi-seller checkout arrives in the next update.',
                  ),
                ),
              ),
              icon: const Icon(Icons.shopping_cart_checkout, size: 18),
              label: const Text('Checkout'),
            ),
          ],
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
