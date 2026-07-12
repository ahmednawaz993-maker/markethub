part of '../main.dart';

// Orders.

/// Buyer pays for an order using the in-app manual flow (no external gateway):
/// they transfer to the platform's receiving account, enter their transaction
/// reference as proof, and submit. The order moves to "payment under review";
/// an admin confirms it (onPaymentAction) and it then enters escrow.
Future<void> _payOrderEscrow(
  BuildContext context,
  String orderId,
  Map<String, dynamic> order,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final amount = (order['amount'] as num?)?.toDouble() ?? 0;
  final messenger = ScaffoldMessenger.of(context);
  final ref = TextEditingController();
  final from = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pay & hold securely',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Amount: ${formatPrice(amount.toStringAsFixed(0))}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                'Transfer the amount to the account below, then enter your '
                'transaction reference. An admin confirms it and your payment '
                'is held safely in escrow until you confirm you received the '
                'item.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const _PaymentAccountInfo(),
              const SizedBox(height: 12),
              TextField(
                controller: ref,
                decoration: const InputDecoration(
                  labelText: 'Transaction ID / reference',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: from,
                decoration: const InputDecoration(
                  labelText: 'Paid from (your account / number, optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  if (ref.text.trim().isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Enter your transaction reference'),
                      ),
                    );
                    return;
                  }
                  try {
                    await FirebaseFirestore.instance
                        .collection('payments')
                        .add({
                          'orderId': orderId,
                          'buyerId': uid,
                          'buyerEmail':
                              FirebaseAuth.instance.currentUser?.email ?? '',
                          'sellerId': order['sellerId'] ?? '',
                          'listingTitle': order['listingTitle'] ?? '',
                          'amount': amount,
                          'provider': 'manual',
                          'status': 'initiated',
                          'proofRef': ref.text.trim(),
                          'proofFrom': from.text.trim(),
                          'createdAt': Timestamp.now(),
                        });
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Payment submitted — an admin will confirm it '
                          'shortly.',
                        ),
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.lock),
                label: const Text('I have paid — submit'),
              ),
            ],
          ),
        ),
      );
    },
  );
  ref.dispose();
  from.dispose();
}

/// Lets a buyer report a problem or open a formal dispute on their order. Both
/// create an `open` dispute which blocks the seller payout until an admin
/// resolves it (enforced server-side in onEscrowAction).
Future<void> showDisputeSheet(
  BuildContext context,
  String orderId,
  Map<String, dynamic> order,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final reason = TextEditingController();
  String type = 'problem';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Report a problem',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tell us what went wrong. Opening a dispute pauses any seller '
                  'payout until our team reviews it.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: type,
                  onChanged: (v) => setSheet(() => type = v ?? 'problem'),
                  child: const Column(
                    children: [
                      RadioListTile<String>(
                        value: 'problem',
                        title: Text('Report a problem'),
                        contentPadding: EdgeInsets.zero,
                        activeColor: kPakGreen,
                      ),
                      RadioListTile<String>(
                        value: 'dispute',
                        title: Text('Open a dispute'),
                        contentPadding: EdgeInsets.zero,
                        activeColor: kPakGreen,
                      ),
                    ],
                  ),
                ),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'What happened?',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    if (reason.text.trim().isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Please describe the problem.'),
                        ),
                      );
                      return;
                    }
                    try {
                      await FirebaseFirestore.instance
                          .collection('disputes')
                          .add({
                            'orderId': orderId,
                            'buyerId': uid,
                            'sellerId': order['sellerId'] ?? '',
                            'listingTitle': order['listingTitle'] ?? '',
                            'type': type,
                            'reason': reason.text.trim(),
                            'status': 'open',
                            'createdAt': Timestamp.now(),
                          });
                    } catch (_) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Could not submit. Please try again.'),
                        ),
                      );
                      return;
                    }
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Submitted — our team will review it.'),
                      ),
                    );
                  },
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  reason.dispose();
}

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
            tabs: [
              Tab(text: 'Buying'),
              Tab(text: 'Selling'),
            ],
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
            final (label, color) = switch (status) {
              'cod_pending' => ('Cash on Delivery', Colors.indigo),
              'payment_review' => ('Payment under review', Colors.orange),
              'in_escrow' => ('Paid · held by PakBazar', kPakGreen),
              'released' => ('Completed · paid out', Colors.green),
              'completed' => ('Completed', Colors.green),
              'refunded' => ('Refunded', Colors.blueGrey),
              'cancelled' => ('Cancelled', Colors.grey),
              _ => ('Awaiting payment', Colors.orange),
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
                              if ((d['orderNumber']?.toString() ?? '')
                                  .isNotEmpty)
                                Text(
                                  d['orderNumber'].toString(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
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
                                    ? 'You receive ${formatPrice(payout.toStringAsFixed(0))}${commissionActive ? ' (after 2% fee)' : ' (0% fee — free)'}'
                                    : formatPrice(amount.toStringAsFixed(0)),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kPakGreen,
                                ),
                              ),
                              if (d['items'] is List &&
                                  (d['items'] as List).isNotEmpty)
                                ...(d['items'] as List).take(4).map((it) {
                                  final m = (it as Map);
                                  return Text(
                                    '• ${m['title']} ×${m['quantity']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  );
                                }),
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
                    _OrderDeliveryPanel(data: d, asSeller: asSeller),
                    CancellationSection(
                      orderId: docs[i].id,
                      data: d,
                      asSeller: asSeller,
                    ),
                    ReturnSection(
                      orderId: docs[i].id,
                      data: d,
                      asSeller: asSeller,
                    ),
                    if (!asSeller &&
                        (status == 'in_escrow' ||
                            status == 'completed' ||
                            status == 'cod_pending'))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              showDisputeSheet(context, docs[i].id, d),
                          icon: const Icon(
                            Icons.report_problem_outlined,
                            size: 16,
                          ),
                          label: const Text('Report a problem'),
                        ),
                      ),
                    if (status == 'pending_payment') ...[
                      const SizedBox(height: 8),
                      if (!asSeller)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _payOrderEscrow(context, docs[i].id, d),
                              icon: const Icon(Icons.lock, size: 18),
                              label: const Text('Pay & hold securely'),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'Waiting for the buyer to pay.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                    if (status == 'cod_pending') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_shipping,
                              size: 16,
                              color: Colors.indigo,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                asSeller
                                    ? 'Cash on Delivery — deliver the item and '
                                          'collect the cash.'
                                    : 'Cash on Delivery — pay cash when the item '
                                          'is delivered.',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (asSeller)
                            ElevatedButton(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await docs[i].reference.update({
                                  'status': 'completed',
                                  'completedAt': Timestamp.now(),
                                });
                                // Seller controls inventory — delivering an
                                // order no longer auto-marks the listing sold.
                                // Offer a one-tap shortcut instead.
                                final lid = d['listingId']?.toString() ?? '';
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Order marked delivered.',
                                    ),
                                    action: lid.isEmpty
                                        ? null
                                        : SnackBarAction(
                                            label: 'Mark sold',
                                            onPressed: () =>
                                                setListingStatus(lid, 'sold'),
                                          ),
                                  ),
                                );
                              },
                              child: const Text('Mark delivered'),
                            ),
                        ],
                      ),
                    ],
                    if (status == 'payment_review') ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.hourglass_top,
                            size: 16,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              asSeller
                                  ? "Buyer's payment is under review."
                                  : 'Payment submitted — under review. It is '
                                        'held in escrow once an admin confirms '
                                        'it.',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (status == 'in_escrow') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kPakGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock, size: 16, color: kPakGreen),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                asSeller
                                    ? 'Payment is held by PakBazar and will be '
                                          'released after the buyer confirms '
                                          'delivery and the platform approves '
                                          'the payout.'
                                    : 'Your payment is held safely by PakBazar. '
                                          'Confirm delivery once you have '
                                          'received and checked the item.',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      OrderFulfillmentPanel(
                        data: d,
                        orderId: docs[i].id,
                        asSeller: asSeller,
                      ),
                    ],
                    if (status == 'released' || status == 'completed') ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (asSeller && status == 'released')
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text(
                                'Paid to your wallet',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => showReviewDialog(
                              context,
                              (asSeller ? d['buyerId'] : d['sellerId'])
                                      ?.toString() ??
                                  '',
                            ),
                            icon: const Icon(Icons.star, size: 18),
                            label: Text(
                              asSeller ? 'Rate buyer' : 'Rate seller',
                            ),
                          ),
                        ],
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

/// Shows the delivery-address snapshot + price breakdown stored on an order.
/// Renders nothing for legacy orders created before delivery addresses existed.
class _OrderDeliveryPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool asSeller;
  const _OrderDeliveryPanel({required this.data, required this.asSeller});

  @override
  Widget build(BuildContext context) {
    final addr = data['deliveryAddress'];
    final hasAddr =
        addr is Map &&
        (addr['fullName']?.toString().trim().isNotEmpty ?? false);
    final subtotal = (data['itemSubtotal'] as num?)?.toDouble();
    final delivery = (data['deliveryFee'] as num?)?.toDouble();
    final total = (data['amount'] as num?)?.toDouble();
    final notes = data['notes']?.toString().trim() ?? '';
    final payMethod = data['paymentMethod']?.toString() ?? '';
    if (!hasAddr && subtotal == null) return const SizedBox.shrink();

    String line(String k) =>
        addr is Map ? (addr[k]?.toString().trim() ?? '') : '';
    final summary = [
      line('houseOrBuilding'),
      line('streetAddress'),
      line('area'),
      line('city'),
      line('province'),
    ].where((e) => e.isNotEmpty).join(', ');
    final phone = line('phone').isNotEmpty
        ? line('phone')
        : (data['buyerPhone']?.toString() ?? '');

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtotal != null) ...[
              _kv('Subtotal', formatPrice(subtotal.toStringAsFixed(0))),
              _kv(
                'Delivery',
                (delivery ?? 0) == 0
                    ? 'FREE'
                    : formatPrice((delivery ?? 0).toStringAsFixed(0)),
                valueColor: (delivery ?? 0) == 0 ? kPakGreen : null,
              ),
              if (total != null)
                _kv('Total', formatPrice(total.toStringAsFixed(0)), bold: true),
            ],
            if (hasAddr) ...[
              const Divider(height: 14),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: kPakGreen),
                  const SizedBox(width: 4),
                  Text(
                    asSeller ? 'Deliver to buyer' : 'Your delivery address',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                line('fullName'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (phone.isNotEmpty)
                Text(
                  phone,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              Text(summary, style: const TextStyle(fontSize: 12)),
              if (line('landmark').isNotEmpty)
                Text(
                  'Landmark: ${line('landmark')}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              if (line('deliveryInstructions').isNotEmpty)
                Text(
                  'Instructions: ${line('deliveryInstructions')}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
            if (payMethod.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Payment: '
                '${payMethod == 'cod' ? 'Cash on Delivery' : 'Online (escrow)'}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            if (notes.isNotEmpty)
              Text(
                'Order notes: $notes',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false, Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              k,
              style: TextStyle(
                fontSize: bold ? 13 : 12,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            Text(
              v,
              style: TextStyle(
                fontSize: bold ? 13 : 12,
                fontWeight: bold || valueColor != null
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
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
  // `amount` is the negotiated product price. Delivery fee (carried on the
  // offer) is added on top for the buyer total; commission is on the product
  // only, so the seller keeps the full delivery fee. This order is created with
  // fromOffer:true, so the Cloud Function does NOT recompute it — the totals
  // here are authoritative.
  // Apply the free-delivery rule to the negotiated product price too, so an
  // accepted offer >= Rs freeDeliveryThreshold also ships free.
  final baseDelivery = (offer['deliveryFee'] as num?)?.toDouble() ?? 0;
  final delivery = qualifiesForFreeDelivery(amount) ? 0.0 : baseDelivery;
  final total = amount + delivery;
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
      'amount': total,
      'itemSubtotal': amount,
      'deliveryFee': delivery,
      'discount': 0,
      'qualifiesForFreeDelivery': qualifiesForFreeDelivery(amount),
      'freeDeliveryThreshold': freeDeliveryThreshold,
      'commission': commission,
      'sellerPayout': total - commission,
      'status': 'pending_payment',
      'createdAt': Timestamp.now(),
      'fromOffer': true,
    });
    tx.update(ref, {'status': 'ordered', 'agreedAmount': amount});
  });
}
