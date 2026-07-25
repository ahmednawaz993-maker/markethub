part of '../main.dart';

// ---------------------------------------------------------------------------
// Buyer-initiated refund requests (admin-controlled).
//
// A buyer whose payment is still HELD by PakBazar (status in_escrow) can ask
// for their money back at any stage — a general remedy alongside the more
// specific Cancellation (pre-shipment) and Return (post-delivery) flows. Unlike
// those, a refund request is decided by ADMIN ONLY: the seller is notified but
// does not approve/reject. On approval a Cloud Function reuses the audited
// escrow-refund path (escrowActions → onEscrowAction), which credits the
// buyer's wallet. Admin may issue a full or partial refund. To avoid stacking,
// the buyer sees the refund action only when no cancellation/return/refund is
// already pending on the order. Mirrors the cancellation/return systems.
// ---------------------------------------------------------------------------

const List<({String code, String label})> kRefundReasons = [
  (code: 'item_not_received', label: "Item not received"),
  (code: 'item_defective', label: 'Item defective or damaged'),
  (code: 'not_as_described', label: 'Not as described'),
  (code: 'wrong_item', label: 'Wrong item received'),
  (code: 'changed_mind', label: 'Changed my mind'),
  (code: 'other', label: 'Other'),
];

String refundReasonLabel(String code) {
  for (final r in kRefundReasons) {
    if (r.code == code) return r.label;
  }
  return code.isEmpty ? 'Not specified' : code;
}

/// What the buyer can do about a refund right now.
enum RefundUi {
  /// Payment is held in escrow → buyer may request an (admin-reviewed) refund.
  request,

  /// Not eligible (unpaid, already settled/released, terminal, or another
  /// cancellation/return/refund is already pending on this order).
  none,
}

/// Decides the buyer refund option for [o]. Refunds are only meaningful while
/// the money is still held by the platform, and never stack on top of an
/// already-pending cancellation / return / refund.
RefundUi refundUiFor(Map<String, dynamic> o) {
  final status = o['status']?.toString() ?? '';
  final amount = (o['amount'] as num?)?.toDouble() ?? 0;
  final cancelPending =
      o['cancellationRequestStatus']?.toString() == 'pending' ||
      o['cancellationRequested'] == true;
  final returnPending =
      o['returnRequestStatus']?.toString() == 'pending' ||
      o['returnRequested'] == true;
  final refundPending =
      o['refundRequestStatus']?.toString() == 'pending' ||
      o['refundRequested'] == true;
  if (cancelPending || returnPending || refundPending) return RefundUi.none;
  if (status == 'in_escrow' && amount > 0) return RefundUi.request;
  return RefundUi.none;
}

// --- Client write helpers ---------------------------------------------------

/// Files a refund request under orders/{id}/refundRequests. A Cloud Function
/// (onRefundRequestCreated) validates it, flags the order and alerts the admin;
/// admin then approves (issuing the escrow refund) or rejects.
Future<void> createRefundRequest(
  String orderId,
  Map<String, dynamic> order,
  String reasonCode,
  String details,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('refundRequests')
      .add({
        'orderId': orderId,
        'buyerId': uid,
        'sellerId': order['sellerId']?.toString() ?? '',
        'reasonCode': reasonCode,
        'reasonDetails': details.trim(),
        'requestStatus': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'requestedBy': uid,
        'reviewedAt': null,
        'reviewedBy': null,
        'adminDecision': '',
        'reviewNote': '',
        'refundRequired': true,
        'refundStatus': 'pending',
        'orderStatusAtRequest': orderStatusOf(order),
        'paymentStatusAtRequest': order['status']?.toString() ?? '',
      });
}

/// Buyer withdraws their own still-pending refund request.
Future<void> withdrawRefundRequest(String orderId, String requestId) async {
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('refundRequests')
      .doc(requestId)
      .update({'requestStatus': 'withdrawn'});
}

/// Admin approves/rejects a pending refund request. On approval the
/// onRefundRequestDecision Cloud Function issues the (full or partial) escrow
/// refund. A null/zero [refundAmount] on approval means "refund the full
/// held amount".
Future<void> decideRefundRequest(
  String orderId,
  String requestId, {
  required bool approve,
  num? refundAmount,
  String note = '',
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final data = <String, dynamic>{
    'requestStatus': approve ? 'approved' : 'rejected',
    'reviewedAt': Timestamp.now(),
    'reviewedBy': uid,
    'decidedByRole': 'admin',
    'adminDecision': approve ? 'approved' : 'rejected',
  };
  if (note.trim().isNotEmpty) data['reviewNote'] = note.trim();
  if (approve && refundAmount != null && refundAmount > 0) {
    data['refundAmount'] = refundAmount;
  }
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('refundRequests')
      .doc(requestId)
      .update(data);
}

/// Live stream of the still-pending refund requests for an order. Single-field
/// filter — no composite index required (the admin cross-order queue uses one).
Stream<QuerySnapshot<Map<String, dynamic>>> pendingRefundRequests(
  String orderId,
) => FirebaseFirestore.instance
    .collection('orders')
    .doc(orderId)
    .collection('refundRequests')
    .where('requestStatus', isEqualTo: 'pending')
    .snapshots();

// ---------------------------------------------------------------------------
// UI — one insertion point per order card: RefundSection.
// ---------------------------------------------------------------------------

/// Refund controls for one order card. Buyer: request / pending (withdrawable) /
/// declined notice. Seller: a passive "under review" notice while a request is
/// pending (sellers do not decide refunds — admin does).
class RefundSection extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final bool asSeller;
  const RefundSection({
    super.key,
    required this.orderId,
    required this.data,
    required this.asSeller,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pendingRefundRequests(orderId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final hasPending = docs.isNotEmpty;

        if (asSeller) {
          if (!hasPending) return const SizedBox.shrink();
          return _cancelBanner(
            icon: Icons.hourglass_top,
            color: Colors.deepPurple,
            text: 'Buyer requested a refund — under PakBazar review.',
          );
        }

        // Buyer side.
        if (hasPending) {
          return _BuyerRefundPendingCard(
            orderId: orderId,
            requestId: docs.first.id,
            request: docs.first.data(),
          );
        }
        final reqStatus = data['refundRequestStatus']?.toString() ?? '';
        if (reqStatus == 'rejected') {
          final note = data['refundDecisionNote']?.toString() ?? '';
          return _cancelBanner(
            icon: Icons.info_outline,
            color: Colors.orange,
            text: note.isEmpty
                ? 'Your refund request was declined.'
                : 'Refund request declined: $note',
          );
        }
        if (reqStatus == 'approved') {
          return _cancelBanner(
            icon: Icons.account_balance_wallet,
            color: Colors.green,
            text: 'Refund approved — credited to your PakBazar wallet.',
          );
        }
        return _BuyerRefundAction(orderId: orderId, data: data);
      },
    );
  }
}

class _BuyerRefundAction extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _BuyerRefundAction({required this.orderId, required this.data});

  @override
  Widget build(BuildContext context) {
    if (refundUiFor(data) == RefundUi.none) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => showRefundSheet(context, orderId, data),
        icon: const Icon(Icons.currency_exchange, size: 16),
        label: const Text('Request refund'),
        style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
      ),
    );
  }
}

class _BuyerRefundPendingCard extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _BuyerRefundPendingCard({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = refundReasonLabel(request['reasonCode']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hourglass_top,
                  size: 16,
                  color: Colors.deepPurple,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Refund requested — under review',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Reason: $reason. PakBazar is reviewing your request.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await withdrawRefundRequest(orderId, requestId);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Refund request withdrawn.'),
                      ),
                    );
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Could not withdraw. Please try again.'),
                      ),
                    );
                  }
                },
                child: const Text('Withdraw request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: buyer picks a reason and submits a refund request.
Future<void> showRefundSheet(
  BuildContext context,
  String orderId,
  Map<String, dynamic> data,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var reasonCode = kRefundReasons.first.code;
  final detailsCtl = TextEditingController();
  var submitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Request a refund',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your payment is held by PakBazar. If PakBazar approves, it '
                  'is refunded to your wallet (in full or in part).',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Why are you requesting a refund?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in kRefundReasons)
                      ChoiceChip(
                        label: Text(r.label),
                        selected: reasonCode == r.code,
                        onSelected: (_) => setSheet(() => reasonCode = r.code),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailsCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Add details (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          setSheet(() => submitting = true);
                          try {
                            await createRefundRequest(
                              orderId,
                              data,
                              reasonCode,
                              detailsCtl.text,
                            );
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
                                'Your refund request has been sent for review.',
                              ),
                            ),
                          );
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Submit request'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  detailsCtl.dispose();
}
