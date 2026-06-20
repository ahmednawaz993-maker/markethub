part of '../main.dart';

// Buy / offer / promote / wallet flows and bottom sheets.

class PromoPackage {
  final String name;
  final int days;
  final int price;
  const PromoPackage(this.name, this.days, this.price);
}

const List<PromoPackage> promoPackages = [
  PromoPackage('Featured · 7 days', 7, 500),
  PromoPackage('Featured · 15 days', 15, 900),
  PromoPackage('Featured · 30 days', 30, 1500),
];

/// Bottom sheet to choose a promotion package for a listing.
Future<void> showPromoteSheet(BuildContext context, Listing listing) async {
  await showModalBottomSheet(
    context: context,
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Promote your ad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Get more views with a FEATURED badge and top placement.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            for (final p in promoPackages)
              ListTile(
                leading: const Icon(Icons.star, color: kGold),
                title: Text(p.name),
                trailing: Text(
                  formatPrice(p.price.toString()),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await payFromWallet(
                    context,
                    type: 'feature',
                    refId: listing.id,
                    amount: p.price,
                    days: p.days,
                  );
                },
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Paid instantly from your PakBazar Wallet. Top up in '
                'Profile → Wallet.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
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
              const Text(
                'Online payment is coming soon. Placing an order notifies the '
                'seller so you can arrange a safe handover. Track it in '
                'Profile → My Orders.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  await createOrder(listing);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Order placed! See it in Profile → My Orders.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Place order'),
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
// Business advertising
// ---------------------------------------------------------------------------

const List<PromoPackage> businessAdPackages = [
  PromoPackage('Featured Business · 30 days', 30, 3000),
  PromoPackage('Featured Business · 90 days', 90, 8000),
];

Future<void> showBusinessAdSheet(
  BuildContext context,
  String businessName,
) async {
  await showModalBottomSheet(
    context: context,
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Advertise your business',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Get a Featured Business spot on the home screen to reach more '
                'buyers across Pakistan.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            for (final p in businessAdPackages)
              ListTile(
                leading: const Icon(Icons.storefront, color: kGold),
                title: Text(p.name),
                trailing: Text(
                  formatPrice(p.price.toString()),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await payFromWallet(
                    context,
                    type: 'featuredBusiness',
                    amount: p.price,
                    days: p.days,
                  );
                },
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Paid instantly from your PakBazar Wallet (Profile → Wallet).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    },
  );
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
                'Choose an amount. Pay via bank transfer / JazzCash and an admin '
                'credits your wallet. Instant card/wallet top-up coming soon.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
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
