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

/// Platform commission taken on each successful on-platform deal.
const double commissionRate = 0.02; // 2%

/// Creates a buy order for a listing. Commission (2%) is recorded so the
/// platform can take its cut once gateway payments go live (Phase 2).
Future<void> createOrder(Listing listing) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final amount = parsePrice(listing.price);
  final commission = amount * commissionRate;
  await FirebaseFirestore.instance.collection('orders').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'listingImage':
        listing.galleryImages.isEmpty ? '' : listing.galleryImages.first,
    'sellerId': listing.userId,
    'sellerName': listing.sellerName,
    'buyerId': user.uid,
    'buyerName': user.email ?? 'Buyer',
    'amount': amount,
    'commission': commission,
    'sellerPayout': amount - commission,
    'status': 'pending_payment',
    'createdAt': Timestamp.now(),
  });
}

/// Places a Cash-on-Delivery order: no online payment and no platform escrow —
/// the buyer pays cash on handover. No commission is taken on COD.
Future<void> createCodOrder(Listing listing) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final amount = parsePrice(listing.price);
  await FirebaseFirestore.instance.collection('orders').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'listingImage':
        listing.galleryImages.isEmpty ? '' : listing.galleryImages.first,
    'sellerId': listing.userId,
    'sellerName': listing.sellerName,
    'buyerId': user.uid,
    'buyerName': user.email ?? 'Buyer',
    'amount': amount,
    'commission': 0,
    'sellerPayout': amount,
    'paymentMethod': 'cod',
    'status': 'cod_pending',
    'createdAt': Timestamp.now(),
  });
}

/// Confirmation sheet for "Buy now".
Future<void> showBuyNowSheet(BuildContext context, Listing listing) async {
  if (!await ensureVerified(context)) return;
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Confirm purchase',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(listing.title)),
                  Text(
                    priceLabel(listing),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'You pay',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    priceLabel(listing),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kPakGreen,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                listing.codAvailable
                    ? 'Pay online (held in escrow until you confirm receipt) or '
                          'choose Cash on Delivery. Track it in Profile → My '
                          'Orders.'
                    : 'Your payment is held safely in escrow until you confirm '
                          'you received the item. Track it in Profile → My '
                          'Orders.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              if (listing.codAvailable) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    await createCodOrder(listing);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'COD order placed — pay cash on delivery. See '
                            'Profile → My Orders.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('Cash on Delivery'),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton(
                onPressed: () async {
                  await createOrder(listing);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Order placed! Pay it from Profile → My Orders.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Pay online (escrow)'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Premium Pakistan-flag theme palette
// ---------------------------------------------------------------------------

Future<void> createOffer(Listing listing, double amount) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await FirebaseFirestore.instance.collection('offers').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'listingImage':
        listing.galleryImages.isEmpty ? '' : listing.galleryImages.first,
    'askingPrice': parsePrice(listing.price),
    'offerAmount': amount,
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
      return Padding(
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
                  onPressed: () async {
                    final amt = double.tryParse(
                      controller.text.replaceAll(RegExp(r'[^0-9.]'), ''),
                    );
                    if (amt == null || amt <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid amount')),
                      );
                      return;
                    }
                    await createOffer(listing, amt);
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
      const SnackBar(
        content: Text('Purchase requested — activating shortly…'),
      ),
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
