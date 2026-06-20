part of '../main.dart';

// Orders.

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Orders'),
          bottom: const TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Buying'), Tab(text: 'Selling')],
          ),
        ),
        body: const TabBarView(
          children: [_OrdersList(asSeller: false), _OrdersList(asSeller: true)],
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  final bool asSeller;
  const _OrdersList({required this.asSeller});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const EmptyState(icon: Icons.receipt_long, title: 'Please log in');
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where(asSeller ? 'sellerId' : 'buyerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long,
            title: 'No orders yet',
            subtitle: asSeller
                ? 'Orders placed on your ads will appear here.'
                : 'Items you buy will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status']?.toString() ?? 'pending_payment';
            final img = d['listingImage']?.toString() ?? '';
            final amount = (d['amount'] as num?)?.toDouble() ?? 0;
            final payout = (d['sellerPayout'] as num?)?.toDouble() ?? 0;
            final buyerConfirmed = d['buyerConfirmed'] == true;
            final (label, color) = switch (status) {
              'completed' => ('Completed', Colors.green),
              'cancelled' => ('Cancelled', Colors.grey),
              _ => ('Pending payment', Colors.orange),
            };
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: img.isEmpty
                              ? Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image),
                                )
                              : Image.network(
                                  img,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 56,
                                    height: 56,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.image),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d['listingTitle']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                asSeller
                                    ? '${d['buyerName'] ?? 'Buyer'}'
                                    : '${d['sellerName'] ?? 'Seller'}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                asSeller
                                    ? 'You receive ${formatPrice(payout.toStringAsFixed(0))} (after 2% fee)'
                                    : formatPrice(amount.toStringAsFixed(0)),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kPakGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (status == 'pending_payment') ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (asSeller)
                            ElevatedButton(
                              onPressed: () async {
                                await docs[i].reference.update({
                                  'status': 'completed',
                                  'completedAt': Timestamp.now(),
                                });
                                final lid = d['listingId']?.toString() ?? '';
                                if (lid.isNotEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('listings')
                                      .doc(lid)
                                      .update({'isSold': true});
                                }
                              },
                              child: const Text('Mark completed'),
                            )
                          else
                            TextButton(
                              onPressed: () => docs[i].reference.update({
                                'status': 'cancelled',
                              }),
                              child: const Text('Cancel'),
                            ),
                        ],
                      ),
                    ],
                    if (status == 'completed' && buyerConfirmed) ...[
                      const SizedBox(height: 6),
                      const Row(
                        children: [
                          Icon(Icons.verified, size: 16, color: kPakGreen),
                          SizedBox(width: 4),
                          Text(
                            'Receipt confirmed by buyer',
                            style: TextStyle(
                              fontSize: 12,
                              color: kPakGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (status == 'completed' && !asSeller) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!buyerConfirmed)
                            TextButton.icon(
                              onPressed: () => docs[i].reference.update({
                                'buyerConfirmed': true,
                                'buyerConfirmedAt': Timestamp.now(),
                              }),
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: const Text('Confirm received'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => showReviewDialog(
                              context,
                              d['sellerId']?.toString() ?? '',
                            ),
                            icon: const Icon(Icons.star, size: 18),
                            label: const Text('Rate seller'),
                          ),
                        ],
                      ),
                    ],
                    if (status == 'completed' && asSeller) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => showReviewDialog(
                            context,
                            d['buyerId']?.toString() ?? '',
                          ),
                          icon: const Icon(Icons.star, size: 18),
                          label: const Text('Rate buyer'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Offers (price negotiation)
// ---------------------------------------------------------------------------

/// Creates an order from an accepted/countered offer (called by the buyer, so
/// buyerId == auth.uid as the rules require).
Future<void> _orderFromOffer(
  DocumentReference ref,
  Map<String, dynamic> offer,
  double amount,
) async {
  final commission = amount * commissionRate;
  final orderRef = FirebaseFirestore.instance.collection('orders').doc();
  // Atomic: re-read the offer and only create the order if it hasn't already
  // been ordered, so a double-tap / race can't produce duplicate orders.
  await FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final status = (snap.data() as Map<String, dynamic>?)?['status'];
    if (status == 'ordered') return;
    tx.set(orderRef, {
      'listingId': offer['listingId'] ?? '',
      'listingTitle': offer['listingTitle'] ?? '',
      'listingImage': offer['listingImage'] ?? '',
      'sellerId': offer['sellerId'] ?? '',
      'sellerName': offer['sellerName'] ?? '',
      'buyerId': offer['buyerId'] ?? '',
      'buyerName': offer['buyerName'] ?? '',
      'amount': amount,
      'commission': commission,
      'sellerPayout': amount - commission,
      'status': 'pending_payment',
      'createdAt': Timestamp.now(),
      'fromOffer': true,
    });
    tx.update(ref, {'status': 'ordered', 'agreedAmount': amount});
  });
}
