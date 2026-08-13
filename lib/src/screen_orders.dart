part of '../main.dart';

// Orders.

/// Buyer pays for an order using the in-app manual flow (no external gateway):
/// they transfer to the platform's receiving account, enter their transaction
/// reference as proof, and submit. The order moves to "payment under review";
/// an admin confirms it (onPaymentAction) and it then enters escrow.
/// Shared manual "I have paid" proof sheet for both single-order and master
/// (multi-seller) escrow payments. Guards against double submission (a second
/// tap during the network gap would create a duplicate payments doc), disables
/// the inputs while submitting, and shows a friendly error instead of the raw
/// exception. [buildPayment] returns the payments-doc body (it must carry either
/// orderId or masterOrderId + amount).
Future<void> _submitPaymentProofSheet(
  BuildContext context, {
  required double amount,
  required String description,
  required Map<String, dynamic> Function(String proofRef, String proofFrom)
  buildPayment,
}) async {
  if (FirebaseAuth.instance.currentUser == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final ref = TextEditingController();
  final from = TextEditingController();
  var submitting = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheet) {
          Future<void> submit() async {
            if (submitting) return;
            if (ref.text.trim().isEmpty) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Enter your transaction reference'),
                ),
              );
              return;
            }
            setSheet(() => submitting = true);
            try {
              await FirebaseFirestore.instance
                  .collection('payments')
                  .add(buildPayment(ref.text.trim(), from.text.trim()));
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Payment submitted — an admin will confirm it shortly.',
                  ),
                ),
              );
            } catch (_) {
              setSheet(() => submitting = false);
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not submit your payment. Please try again.',
                  ),
                ),
              );
            }
          }

          return Padding(
            padding: EdgeInsetsDirectional.only(
              start: 16,
              end: 16,
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
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const _PaymentAccountInfo(),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ref,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Transaction ID / reference',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: from,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Paid from (your account / number, optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: submitting ? null : submit,
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock),
                    label: Text(
                      submitting ? 'Submitting…' : 'I have paid — submit',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  ref.dispose();
  from.dispose();
}

Future<void> _payOrderEscrow(
  BuildContext context,
  String orderId,
  Map<String, dynamic> order,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final amount = (order['amount'] as num?)?.toDouble() ?? 0;
  await _submitPaymentProofSheet(
    context,
    amount: amount,
    description:
        'Transfer the amount to the account below, then enter your '
        'transaction reference. An admin confirms it and your payment is held '
        'safely in escrow until you confirm you received the item.',
    buildPayment: (proofRef, proofFrom) => {
      'orderId': orderId,
      'buyerId': uid,
      'buyerEmail': FirebaseAuth.instance.currentUser?.email ?? '',
      'sellerId': order['sellerId'] ?? '',
      'listingTitle': order['listingTitle'] ?? '',
      'amount': amount,
      'provider': 'manual',
      'status': 'initiated',
      'proofRef': proofRef,
      'proofFrom': proofFrom,
      'createdAt': Timestamp.now(),
    },
  );
}

/// Phase 6: a buyer pays ONCE for a whole multi-seller (master) order. The
/// payment doc carries the masterOrderId + the combined total; the Cloud
/// Function (onPaymentAction -> confirmMasterPaymentIntoEscrow) fans the
/// confirmed hold out to each seller's sub-order so every share is escrowed
/// independently. Mirrors _payOrderEscrow's manual-transfer + proof flow.
Future<void> _payMasterEscrow(
  BuildContext context,
  String masterId,
  String masterNumber,
  double amount,
  int packages,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await _submitPaymentProofSheet(
    context,
    amount: amount,
    description:
        'One payment covers all $packages packages'
        '${masterNumber.isEmpty ? '' : ' in order $masterNumber'}. '
        'Transfer the amount to the account below, then enter your transaction '
        'reference. Each seller is paid only after you confirm you received '
        'their package.',
    buildPayment: (proofRef, proofFrom) => {
      'masterOrderId': masterId,
      'buyerId': uid,
      'buyerEmail': FirebaseAuth.instance.currentUser?.email ?? '',
      'listingTitle': masterNumber.isEmpty
          ? 'Multi-seller order · $packages packages'
          : 'Order $masterNumber · $packages packages',
      'amount': amount,
      'provider': 'manual',
      'status': 'initiated',
      'proofRef': proofRef,
      'proofFrom': proofFrom,
      'createdAt': Timestamp.now(),
    },
  );
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
  var submitting = false;
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
                Text(
                  'Tell us what went wrong. Opening a dispute pauses any seller '
                  'payout until our team reviews it.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
                  onPressed: submitting
                      ? null
                      : () async {
                          if (reason.text.trim().isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Please describe the problem.'),
                              ),
                            );
                            return;
                          }
                          setSheet(() => submitting = true);
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
                            setSheet(() => submitting = false);
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not submit. Please try again.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Submitted — our team will review it.',
                              ),
                            ),
                          );
                        },
                  child: Text(submitting ? 'Submitting…' : 'Submit'),
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
  /// 0 = Buying (default), 1 = Selling. Lets the seller dashboard deep-link
  /// straight to the Selling tab.
  final int initialIndex;
  const OrdersScreen({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Orders'),
          bottom: const TabBar(
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
        if (snapshot.hasError) {
          return const EmptyState(
            icon: Icons.error_outline,
            title: 'Couldn’t load your orders',
            subtitle: 'Please check your connection and try again.',
          );
        }
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
        // Phase 5/6: for a buyer, group sub-orders by their master order so each
        // package card can announce it is one of several shipments (Phase 5) and
        // so a single "pay once" action covers the whole order (Phase 6). The
        // master total is the sum of every sub-order's amount; the leader is the
        // first sub-order of the group in the list (it hosts the pay action).
        final masterCounts = <String, int>{};
        final masterTotals = <String, double>{};
        final masterLeader = <String, int>{};
        final masterDelivered = <String, int>{};
        const kDoneStates = {'delivered', 'buyer_confirmed', 'completed'};
        if (!asSeller) {
          for (var idx = 0; idx < docs.length; idx++) {
            final dd = docs[idx].data() as Map<String, dynamic>;
            final m = dd['masterOrderId']?.toString() ?? '';
            if (m.isEmpty) continue;
            masterCounts[m] = (masterCounts[m] ?? 0) + 1;
            // Only still-payable packages count toward the "pay for all" total,
            // so a buyer is never asked to re-pay a package already in escrow.
            final st = dd['status']?.toString() ?? '';
            if (st == 'pending_payment' || st == 'payment_review') {
              masterTotals[m] =
                  (masterTotals[m] ?? 0) +
                  ((dd['amount'] as num?)?.toDouble() ?? 0);
            }
            masterLeader.putIfAbsent(m, () => idx);
            if (kDoneStates.contains(orderStatusOf(dd))) {
              masterDelivered[m] = (masterDelivered[m] ?? 0) + 1;
            }
          }
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.page,
            AppSpacing.navClearance,
          ),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final masterId = d['masterOrderId']?.toString() ?? '';
            final pkgCount = asSeller ? 1 : (masterCounts[masterId] ?? 1);
            final isMasterOrder = !asSeller && masterId.isNotEmpty;
            final isMasterLeader = isMasterOrder && masterLeader[masterId] == i;
            final masterTotal = masterTotals[masterId] ?? 0;
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
                    if (!asSeller && pkgCount > 1)
                      _MultiPackageBanner(
                        orderNumber: d['orderNumber']?.toString() ?? '',
                        packages: pkgCount,
                        delivered: masterDelivered[masterId] ?? 0,
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: AppRadius.rSm,
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: AppNetworkImage(url: img, iconSize: 22),
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
                                // Tap to copy: the number is what a user quotes
                                // to support, and retyping "PB-1042" off a phone
                                // screen into a chat is where mistakes happen.
                                _CopyableOrderNumber(
                                  number: d['orderNumber'].toString(),
                                ),
                              Text(
                                asSeller
                                    ? '${d['buyerName'] ?? 'Buyer'}'
                                    : '${d['sellerName'] ?? 'Seller'}',
                                style: TextStyle(
                                  color: AppColors.textMuted,
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
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
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
                    RefundSection(
                      orderId: docs[i].id,
                      data: d,
                      asSeller: asSeller,
                    ),
                    if (!asSeller &&
                        (status == 'in_escrow' ||
                            status == 'completed' ||
                            status == 'cod_pending'))
                      Align(
                        alignment: AlignmentDirectional.centerStart,
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
                      if (!asSeller && isMasterOrder)
                        // Phase 6: one payment covers every package in the
                        // master order. Only the first package hosts the button;
                        // the rest show a note so the buyer pays exactly once.
                        (isMasterLeader
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _payMasterEscrow(
                                      context,
                                      masterId,
                                      (d['orderNumber']?.toString() ?? '')
                                          .replaceAll(RegExp(r'-S\d+$'), ''),
                                      masterTotal,
                                      pkgCount,
                                    ),
                                    icon: const Icon(Icons.lock, size: 18),
                                    label: Text(
                                      'Pay ${formatPrice(masterTotal.toStringAsFixed(0))} '
                                      'for all $pkgCount packages',
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                'Paid together with the other packages in this '
                                'order — use the first package above to pay.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ))
                      else if (!asSeller)
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
                        Text(
                          'Waiting for the buyer to pay.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
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
                      // COD orders get the same Accepted → Ready to dispatch →
                      // Dispatched → Delivered tracking as escrow orders. The
                      // buyer confirming receipt completes the order (cash was
                      // collected on delivery — no escrow payout to release).
                      OrderFulfillmentPanel(
                        data: d,
                        orderId: docs[i].id,
                        asSeller: asSeller,
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
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (asSeller && status == 'released')
                            const Text(
                              'Paid to your wallet',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
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

/// The order's human-readable reference (PB-1042), tappable to copy. Every order
/// has one — assigned by notifyOnNewOrder for single/offer orders and by the
/// multi-seller fan-out (PB-1042-S1) for cart packages — so this is the handle a
/// buyer or seller quotes when asking about an order later.
class _CopyableOrderNumber extends StatelessWidget {
  final String number;
  const _CopyableOrderNumber({required this.number});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: number));
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied $number')),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              number,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 11, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Shows the delivery-address snapshot + price breakdown stored on an order.
/// Renders nothing for legacy orders created before delivery addresses existed.
// Phase 5: shown on each buyer sub-order that belongs to a multi-seller master
// order, telling the buyer the order arrives in several separate packages.
class _MultiPackageBanner extends StatelessWidget {
  final String orderNumber;
  final int packages;
  final int delivered;
  const _MultiPackageBanner({
    required this.orderNumber,
    required this.packages,
    this.delivered = 0,
  });

  @override
  Widget build(BuildContext context) {
    final master = orderNumber.replaceAll(RegExp(r'-S\d+$'), '');
    final allDone = delivered >= packages && packages > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.local_shipping_outlined,
            size: 18,
            color: Colors.deepPurple,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        master.isEmpty
                            ? 'Package $packages of a multi-seller order'
                            : 'Order $master · $packages packages',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.deepPurple,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      allDone
                          ? 'All delivered'
                          : '$delivered/$packages delivered',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: allDone ? kPakGreen : Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Your order will arrive in multiple packages because '
                  'products are being shipped from different sellers.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              Text(summary, style: const TextStyle(fontSize: 12)),
              if (line('landmark').isNotEmpty)
                Text(
                  'Landmark: ${line('landmark')}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              if (line('deliveryInstructions').isNotEmpty)
                Text(
                  'Instructions: ${line('deliveryInstructions')}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
            if (payMethod.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Payment: '
                '${payMethod == 'cod' ? 'Cash on Delivery' : 'Online (escrow)'}',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
            if (notes.isNotEmpty)
              Text(
                'Order notes: $notes',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
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
      // The server validates a negotiated order against the offer it came
      // from, so the order has to name it.
      'offerId': ref.id,
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
