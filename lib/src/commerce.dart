part of '../main.dart';

// Buy / offer / promote / wallet flows and bottom sheets.

class PromoPackage {
  final String name;
  final int days;
  final int price;
  const PromoPackage(this.name, this.days, this.price);
}

/// Bottom sheet to feature a listing — free for 3 months. Sets the FEATURED
/// badge + top placement; expireFeatured ends it after 90 days.
Future<void> showPromoteSheet(BuildContext context, Listing listing) async {
  final messenger = ScaffoldMessenger.of(context);
  await showModalBottomSheet(
    context: context,
    builder: (sheetCtx) {
      final active = listing.isCurrentlyFeatured;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      'Feature your ad',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kPakGreen,
                      borderRadius: AppRadius.rXl,
                    ),
                    child: const Text(
                      'FREE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Get a FEATURED badge and top placement — free for 3 months.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              if (active)
                const Text(
                  'This ad is already featured.',
                  style: TextStyle(
                    color: kPakGreen,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () async {
                    final until = Timestamp.fromDate(
                      DateTime.now().add(const Duration(days: 90)),
                    );
                    await FirebaseFirestore.instance
                        .collection('listings')
                        .doc(listing.id)
                        .update({'isFeatured': true, 'featuredUntil': until});
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Your ad is now featured — free for 3 months!',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.star),
                  label: const Text('Feature free for 3 months'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Free-launch period: the platform takes NO commission on any deal until this
/// date, after which the standard 2% resumes automatically — no app update
/// needed. Set for a 3-month free launch starting 2026-07-10.
/// IMPORTANT: keep this date in sync with FREE_UNTIL in functions/index.js,
/// which is the server-authoritative value used on escrow release.
final DateTime commissionFreeUntil = DateTime.utc(2026, 10, 10);

/// Platform commission taken on each successful on-platform deal: 0% during the
/// free-launch period, 2% afterwards.
double get commissionRate =>
    DateTime.now().toUtc().isBefore(commissionFreeUntil) ? 0.0 : 0.02;

/// Whether the platform is currently charging a commission (false while the
/// free-launch period is active). Drives seller-facing fee wording.
bool get commissionActive => commissionRate > 0;

/// The delivery fee a buyer pays on top of the product price, or 0 when the
/// seller doesn't offer delivery / left it blank (free delivery). Only applies
/// while `deliveryAvailable` is on. Kept in sync with the server recompute in
/// functions/index.js (notifyOnNewOrder).
double deliveryFeeOf(Listing l) =>
    l.deliveryAvailable ? parsePrice(l.deliveryFee) : 0;

/// Merchandise subtotal (in Rs) at or above which delivery is free.
/// IMPORTANT: mirror of FREE_DELIVERY_THRESHOLD in functions/index.js — the
/// Cloud Function re-applies this rule server-side (notifyOnNewOrder), so keep
/// the two values in sync. Defined once here; never hardcode 3000 elsewhere.
const double freeDeliveryThreshold = 3000;

/// Whether a given merchandise subtotal qualifies for free delivery. The
/// threshold is on the product subtotal only — before any delivery fee,
/// discount, or tax.
bool qualifiesForFreeDelivery(double subtotal) =>
    subtotal >= freeDeliveryThreshold;

/// The delivery fee actually charged to the buyer: Rs 0 when the subtotal
/// qualifies for free delivery, otherwise the seller's per-listing fee.
double effectiveDeliveryFee(Listing l, double subtotal) =>
    qualifiesForFreeDelivery(subtotal) ? 0 : deliveryFeeOf(l);

/// How much more (in Rs) the buyer must add to reach free delivery (>= 0).
double amountToFreeDelivery(double subtotal) {
  final remaining = freeDeliveryThreshold - subtotal;
  return remaining > 0 ? remaining : 0;
}

/// Raised during checkout with a short, user-friendly message (never a raw
/// Firebase exception). The checkout screen shows [message] to the buyer.
class CheckoutException implements Exception {
  final String message;
  CheckoutException(this.message);
  @override
  String toString() => message;
}

/// Turns an unexpected error into a friendly checkout message.
String _friendlyOrderError(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('permission-denied') || s.contains('permission denied')) {
    return 'You are not allowed to place this order. Please make sure your '
        'account is verified and try again.';
  }
  if (s.contains('unavailable') ||
      s.contains('network') ||
      s.contains('timeout') ||
      s.contains('deadline')) {
    return 'Network problem. Please check your connection and try again.';
  }
  return 'Could not place the order. Please try again.';
}

/// Creates a single-listing order after re-validating the listing against
/// current server data (still exists, not sold, current price) inside a
/// transaction, and embeds a snapshot of the buyer's [address].
///
/// Free delivery (subtotal >= [freeDeliveryThreshold]) is applied here AND
/// re-applied server-side in notifyOnNewOrder, so the stored fee is
/// authoritative regardless of the client. [paymentMethod] is 'cod' or
/// 'escrow'. Returns the new order id. Throws [CheckoutException] with a
/// user-friendly message on any failure.
Future<String> placeListingOrder({
  required Listing listing,
  required DeliveryAddress address,
  required String paymentMethod, // 'cod' | 'escrow'
  String notes = '',
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw CheckoutException('Please log in to place an order.');
  if (!address.isComplete) {
    throw CheckoutException(
      'Please provide a complete delivery address first.',
    );
  }
  final isCod = paymentMethod == 'cod';
  final fs = FirebaseFirestore.instance;
  final listingRef = fs.collection('listings').doc(listing.id);
  final orderRef = fs.collection('orders').doc();

  try {
    await fs.runTransaction((tx) async {
      final snap = await tx.get(listingRef);
      if (!snap.exists) {
        throw CheckoutException('This item is no longer available.');
      }
      final data = snap.data() as Map<String, dynamic>;
      // Recompute from trusted current data, never the local cart copy.
      final current = Listing.fromDoc(snap);
      // Only an in-stock listing can be bought; sold / out-of-stock / inactive
      // are re-checked here against the migrated server status (not the cart).
      if (!current.isAvailableForSale) {
        throw CheckoutException(
          current.status == 'sold'
              ? 'This item has just been sold.'
              : 'This item is not available for purchase right now.',
        );
      }
      if (isCod && data['codAvailable'] != true) {
        throw CheckoutException(
          'Cash on Delivery is not available for this item.',
        );
      }
      final itemSubtotal = parsePrice(current.price);
      if (itemSubtotal <= 0) {
        throw CheckoutException('This item cannot be purchased right now.');
      }
      final delivery = effectiveDeliveryFee(current, itemSubtotal);
      final amount = itemSubtotal + delivery;
      // Commission is taken on the product only, so the seller keeps the full
      // delivery fee; no commission on COD.
      final commission = isCod ? 0.0 : itemSubtotal * commissionRate;
      tx.set(orderRef, {
        'listingId': current.id,
        'listingTitle': current.title,
        'listingImage': current.galleryImages.isEmpty
            ? ''
            : current.galleryImages.first,
        'sellerId': current.userId,
        'sellerName': current.sellerName,
        'buyerId': user.uid,
        'buyerName': address.fullName.trim(),
        'buyerPhone': normalizePakMobile(address.phone),
        'itemSubtotal': itemSubtotal,
        'amount': amount,
        'deliveryFee': delivery,
        'discount': 0,
        'qualifiesForFreeDelivery': qualifiesForFreeDelivery(itemSubtotal),
        'freeDeliveryThreshold': freeDeliveryThreshold,
        'commission': commission,
        'sellerPayout': amount - commission,
        'deliveryAddress': address.snapshotMap(),
        'paymentMethod': isCod ? 'cod' : 'escrow',
        'notes': notes.trim(),
        'status': isCod ? 'cod_pending' : 'pending_payment',
        'createdAt': Timestamp.now(),
      });
    });
  } on CheckoutException {
    rethrow;
  } catch (e) {
    throw CheckoutException(_friendlyOrderError(e));
  }
  return orderRef.id;
}

/// Entry point from the "Buy now" button: gates on ID verification, then opens
/// the full checkout screen (address selection + summary + Place Order).
Future<void> openCheckout(BuildContext context, Listing listing) async {
  if (!await ensureVerified(context)) return;
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CheckoutScreen(listing: listing)),
  );
}

// ---------------------------------------------------------------------------
// Seller-controlled inventory
// ---------------------------------------------------------------------------

/// The four seller-controlled inventory states and their buyer-facing labels.
/// A listing is only purchasable while 'in_stock'. Nothing auto-marks a listing
/// sold — the seller alone changes this (see showInventorySheet).
const Map<String, String> kListingStatusLabels = {
  'in_stock': 'In stock',
  'out_of_stock': 'Out of stock',
  'sold': 'Sold',
  'inactive': 'Inactive',
};

/// Writes a new inventory [status] onto a listing, keeping the legacy `isSold`
/// bool in sync (true only for 'sold') so existing feed filters keep working.
/// A no-op for unknown status values.
Future<void> setListingStatus(String listingId, String status) async {
  if (!kListingStatusLabels.containsKey(status)) return;
  await FirebaseFirestore.instance.collection('listings').doc(listingId).update(
    {'status': status, 'isSold': status == 'sold'},
  );
}

/// Bottom sheet letting a seller set their listing's inventory status. The
/// significant changes (Sold / Inactive) ask for confirmation first. Does not
/// delete anything — reviews, orders, images and analytics are preserved.
Future<void> showInventorySheet(BuildContext context, Listing listing) async {
  final messenger = ScaffoldMessenger.of(context);

  ({IconData icon, Color color, String? confirm}) meta(String s) => switch (s) {
    'in_stock' => (icon: Icons.check_circle, color: kPakGreen, confirm: null),
    'out_of_stock' => (
      icon: Icons.remove_shopping_cart,
      color: Colors.orange,
      confirm: null,
    ),
    'sold' => (
      icon: Icons.sell,
      color: Colors.red,
      confirm:
          'Buyers will no longer be able to purchase this item. '
          'You can set it back to In stock anytime.',
    ),
    _ => (
      icon: Icons.visibility_off,
      color: Colors.blueGrey,
      confirm:
          'This hides the listing from buyers without deleting it. '
          'Reviews, orders, images and analytics are kept.',
    ),
  };

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      Future<void> apply(String status) async {
        final m = meta(status);
        if (m.confirm != null) {
          final ok = await showDialog<bool>(
            context: sheetCtx,
            builder: (dCtx) => AlertDialog(
              title: Text('Mark as ${kListingStatusLabels[status]}?'),
              content: Text(m.confirm!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dCtx, true),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
          if (ok != true) return;
        }
        try {
          await setListingStatus(listing.id, status);
        } catch (_) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not update status. Try again.'),
            ),
          );
          return;
        }
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Listing marked "${kListingStatusLabels[status]}".'),
          ),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Inventory status',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'You control availability. Placing, paying for, or delivering '
                  'an order never changes this automatically.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in kListingStatusLabels.entries)
                ListTile(
                  leading: Icon(
                    meta(entry.key).icon,
                    color: meta(entry.key).color,
                  ),
                  title: Text(entry.value),
                  trailing: listing.status == entry.key
                      ? const Icon(Icons.check, color: kPakGreen)
                      : null,
                  onTap: listing.status == entry.key
                      ? null
                      : () => apply(entry.key),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Order fulfillment: separate order-progress and payment-status models
// ---------------------------------------------------------------------------

// PakBazar keeps ORDER PROGRESS and MONEY STATUS in two independent fields
// (spec section 2). Older orders only carry the combined escrow `status`, so
// the helpers below DERIVE both from whatever a document has — new docs read
// their explicit orderStatus/paymentStatus; legacy docs are mapped on read.
//
// Wording rule: money that PakBazar is holding is described as "held by
// PakBazar / pending seller settlement / payout" — never "regulated escrow".

/// Canonical order-progress states (separate from the payment status).
const List<String> kOrderStatuses = [
  'pending',
  'accepted',
  'processing',
  'shipped',
  'delivered',
  'buyer_confirmed',
  'completed',
  'rejected',
  'cancelled',
  'returned',
  'disputed',
];

/// Buyer-facing label for an [orderStatus] value.
String orderStatusLabel(String s) => switch (s) {
  'pending' => 'Pending',
  'accepted' => 'Order accepted',
  'processing' => 'Ready to dispatch',
  'shipped' => 'Dispatched',
  // A buyer-confirmed order is what "Delivered" means in the tracking flow:
  // the seller dispatches, and the buyer confirming receipt marks it delivered.
  'delivered' => 'Delivered',
  'buyer_confirmed' => 'Delivered',
  'completed' => 'Completed',
  'rejected' => 'Rejected',
  'cancellation_requested' => 'Cancellation requested',
  'cancelled' => 'Cancelled',
  'return_requested' => 'Return requested',
  'returned' => 'Returned',
  'disputed' => 'Disputed',
  _ => 'Pending',
};

/// Buyer-facing label for a [paymentStatus] value (policy-compliant wording).
String paymentStatusLabel(String s) => switch (s) {
  'unpaid' => 'Unpaid',
  'payment_pending' => 'Payment pending',
  'paid_to_platform' => 'Paid to PakBazar',
  'held_by_platform' => 'Held by PakBazar',
  'release_pending' => 'Pending seller settlement',
  'released_to_seller' => 'Paid out to seller',
  'refunded' => 'Refunded',
  'partially_refunded' => 'Partially refunded',
  'disputed' => 'Disputed',
  'failed' => 'Payment failed',
  _ => '',
};

/// Derives the fulfillment status of an order map, tolerating legacy docs that
/// only carry the combined escrow `status` field.
String orderStatusOf(Map<String, dynamic> o) {
  final explicit = o['orderStatus']?.toString();
  if (explicit != null && kOrderStatuses.contains(explicit)) return explicit;
  final legacy = o['status']?.toString() ?? '';
  return switch (legacy) {
    'pending_payment' || 'payment_review' => 'pending',
    'cod_pending' => 'processing',
    'in_escrow' => o['buyerConfirmed'] == true ? 'buyer_confirmed' : 'accepted',
    'released' || 'completed' => 'completed',
    'refunded' || 'cancelled' => 'cancelled',
    _ => 'pending',
  };
}

/// Derives the money status of an order map, tolerating legacy docs.
String paymentStatusOf(Map<String, dynamic> o) {
  final explicit = o['paymentStatus']?.toString();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final legacy = o['status']?.toString() ?? '';
  return switch (legacy) {
    'pending_payment' => 'payment_pending',
    'payment_review' => 'paid_to_platform',
    'in_escrow' =>
      o['buyerConfirmed'] == true ? 'release_pending' : 'held_by_platform',
    'released' || 'completed' => 'released_to_seller',
    'refunded' => 'refunded',
    'cod_pending' => 'unpaid',
    _ => 'unpaid',
  };
}

/// The seller's next allowed fulfillment step for [orderStatus], or '' at the
/// end of the seller-controlled chain. The seller drives it up to 'shipped'
/// (Dispatched); after that the BUYER confirms receipt, which marks the order
/// delivered. Mirrors the transition guard enforced in firestore.rules.
String nextShippingStep(String orderStatus) => switch (orderStatus) {
  'pending' => 'accepted',
  'accepted' => 'processing',
  'processing' => 'shipped',
  _ => '',
};

/// Advances an order along the seller shipping flow. Money state is never
/// touched here (payout stays server-authoritative); only the fulfillment
/// fields change, which the Firestore rules validate as a legal transition.
/// Marking [toStatus] == 'shipped' requires a courier + tracking number.
Future<void> setOrderShipping(
  String orderId,
  String toStatus, {
  String courierName = '',
  String trackingNumber = '',
  String trackingUrl = '',
  String sellerNote = '',
}) async {
  final data = <String, dynamic>{
    'orderStatus': toStatus,
    'updatedAt': Timestamp.now(),
  };
  if (toStatus == 'shipped') {
    data['courierName'] = courierName.trim();
    data['trackingNumber'] = trackingNumber.trim();
    if (trackingUrl.trim().isNotEmpty) {
      data['trackingUrl'] = trackingUrl.trim();
    }
    data['shippedAt'] = Timestamp.now();
  }
  if (toStatus == 'delivered') data['deliveredAt'] = Timestamp.now();
  if (sellerNote.trim().isNotEmpty) data['sellerNote'] = sellerNote.trim();
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .update(data);
}

/// Buyer confirms they received and checked the order, marking it Delivered.
///
/// For an escrow (held-payment) order this sets the fulfillment fields only; a
/// Cloud Function (onOrderProgress) derives the money consequence (payment →
/// release_pending, opens the payout record) — the buyer app never releases
/// money. For a COD order there is no held payment (cash was collected on
/// delivery), so the order completes immediately; this is permitted by the
/// firestore rules' onlySafeOrderChange (cod_pending → completed).
Future<void> confirmOrderDelivery(String orderId, {bool isCod = false}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final data = <String, dynamic>{
    'orderStatus': isCod ? 'delivered' : 'buyer_confirmed',
    'buyerConfirmed': true,
    'buyerConfirmedAt': Timestamp.now(),
    'buyerConfirmedBy': uid,
  };
  if (isCod) {
    data['status'] = 'completed';
    data['completedAt'] = Timestamp.now();
  }
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .update(data);
}

// The old "Buy now" confirmation bottom sheet was replaced by the full
// CheckoutScreen (mandatory delivery address + free-delivery rule + payment
// method). See openCheckout / placeListingOrder above and screen_checkout.dart.

// ---------------------------------------------------------------------------
// Premium Pakistan-flag theme palette
// ---------------------------------------------------------------------------

Future<void> createOffer(Listing listing, double amount) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await FirebaseFirestore.instance.collection('offers').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'listingImage': listing.galleryImages.isEmpty
        ? ''
        : listing.galleryImages.first,
    'askingPrice': parsePrice(listing.price),
    'offerAmount': amount,
    'deliveryFee': deliveryFeeOf(listing),
    'sellerId': listing.userId,
    'sellerName': listing.sellerName,
    'buyerId': user.uid,
    'buyerName': user.email ?? 'Buyer',
    'status': 'pending',
    'createdAt': Timestamp.now(),
  });
}

Future<void> showOfferSheet(BuildContext context, Listing listing) async {
  if (!await ensureVerified(context)) return;
  if (!context.mounted) return;
  final controller = TextEditingController();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      var submitting = false;
      return StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Make an offer',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Asking price: ${formatPrice(listing.price)}',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Your offer (Rs)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final amt = double.tryParse(
                              controller.text.replaceAll(
                                RegExp(r'[^0-9.]'),
                                '',
                              ),
                            );
                            if (amt == null || amt <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Enter a valid amount'),
                                ),
                              );
                              return;
                            }
                            setSheetState(() => submitting = true);
                            try {
                              await createOffer(listing, amt);
                            } catch (_) {
                              if (context.mounted) {
                                setSheetState(() => submitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not send offer. Try again.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Offer sent! Track it in Profile → Offers.',
                                  ),
                                ),
                              );
                            }
                          },
                    child: const Text('Send offer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  controller.dispose();
}

// ---------------------------------------------------------------------------
// Orders (direct buy/sell)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Wallet / in-app purchases
// ---------------------------------------------------------------------------

const List<int> topupAmounts = [500, 1000, 2000, 5000, 10000];

/// Spends wallet balance on a feature. Pre-checks the balance for UX; the
/// processPurchase Cloud Function re-validates and applies the effect.
Future<bool> payFromWallet(
  BuildContext context, {
  required String type, // 'feature' | 'featuredBusiness' | 'banner'
  String? refId,
  required int amount,
  int days = 7,
  Map<String, dynamic> extra = const {},
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  final userSnap = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();
  final balance = (userSnap.data()?['walletBalance'] as num?)?.toInt() ?? 0;
  if (balance < amount) {
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insufficient balance'),
        content: Text(
          'This costs ${formatPrice('$amount')} but your wallet has '
          '${formatPrice('$balance')}. Top up to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Top up'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
    }
    return false;
  }
  await FirebaseFirestore.instance.collection('purchases').add({
    'userId': user.uid,
    'type': type,
    'refId': refId ?? '',
    'amount': amount,
    'days': days,
    'status': 'pending',
    'createdAt': Timestamp.now(),
    ...extra,
  });
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Purchase requested — activating shortly…')),
    );
  }
  return true;
}

Future<void> showTopupSheet(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Top up your wallet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Pay to the account below via bank transfer / JazzCash / '
                  'EasyPaisa, then tap your amount to request credit. An admin '
                  'confirms the payment and credits your wallet.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              const _PaymentAccountInfo(),
              const SizedBox(height: 8),
              for (final a in topupAmounts)
                ListTile(
                  leading: const Icon(
                    Icons.account_balance_wallet,
                    color: kPakGreen,
                  ),
                  title: Text(formatPrice('$a')),
                  trailing: const Icon(Icons.add_circle, color: kPakGreen),
                  onTap: () async {
                    await FirebaseFirestore.instance
                        .collection('walletTopups')
                        .add({
                          'userId': uid,
                          'userEmail':
                              FirebaseAuth.instance.currentUser?.email ?? '',
                          'amount': a,
                          'status': 'pending',
                          'createdAt': Timestamp.now(),
                        });
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Top-up requested — your wallet is credited once '
                            'payment is approved.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}

/// Shows the platform's receiving account (bank / JazzCash / EasyPaisa) on the
/// top-up sheet so a user knows where to send payment. Admin-editable via
/// Admin Panel → Payment a/c; stored at config/paymentAccount.
class _PaymentAccountInfo extends StatelessWidget {
  const _PaymentAccountInfo();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('config')
          .doc('paymentAccount')
          .get(),
      builder: (context, snap) {
        final d = snap.data?.data() as Map<String, dynamic>?;
        if (d == null) return const SizedBox.shrink();
        final rows = <Widget>[];
        void add(String label, String? value) {
          final v = (value ?? '').trim();
          if (v.isEmpty) return;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      v,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        add('Bank', d['bankName']?.toString());
        add('Account title', d['accountTitle']?.toString());
        add('Account no.', d['accountNumber']?.toString());
        add('IBAN', d['iban']?.toString());
        add('JazzCash', d['jazzCash']?.toString());
        add('EasyPaisa', d['easyPaisa']?.toString());
        final note = (d['note']?.toString() ?? '').trim();
        if (rows.isEmpty && note.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: kPakGreen.withValues(alpha: 0.06),
            borderRadius: AppRadius.rMd,
            border: Border.all(color: kPakGreen.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send payment to',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...rows,
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    note,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
