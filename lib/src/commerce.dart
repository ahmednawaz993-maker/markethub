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
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Feature your ad',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kPakGreen,
                      borderRadius: BorderRadius.circular(20),
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
              const Text(
                'Get a FEATURED badge and top placement — free for 3 months.',
                style: TextStyle(color: Colors.grey),
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
      if (data['isSold'] == true) {
        throw CheckoutException('This item has just been sold.');
      }
      if (isCod && data['codAvailable'] != true) {
        throw CheckoutException(
          'Cash on Delivery is not available for this item.',
        );
      }
      // Recompute from trusted current data, never the local cart copy.
      final current = Listing.fromDoc(snap);
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
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Make an offer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Asking price: ${formatPrice(listing.price)}',
                    style: const TextStyle(color: Colors.grey),
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
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Top up your wallet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Pay to the account below via bank transfer / JazzCash / '
                'EasyPaisa, then tap your amount to request credit. An admin '
                'confirms the payment and credits your wallet.',
                style: TextStyle(color: Colors.grey),
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
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kPakGreen.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
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
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
