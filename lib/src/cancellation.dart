part of '../main.dart';

// ---------------------------------------------------------------------------
// Buyer order cancellation (spec sections 6–8, 11–13).
//
// PakBazar keeps ORDER PROGRESS (`orderStatus`) and MONEY STATE (the legacy
// escrow `status`) in two independent fields. Cancellation rules are keyed on
// BOTH so the buyer's options match reality:
//
//   • Unpaid order (status pending_payment / cod_pending)  → cancel instantly.
//   • Paid & held, seller has NOT accepted (in_escrow + orderStatus 'pending')
//                                                          → cancel + refund.
//   • Paid & accepted / preparing (accepted / processing)  → REQUEST only,
//                                                             seller/admin must
//                                                             approve.
//   • Shipped                                              → no self-service;
//                                                             contact support.
//   • Delivered / confirmed / released / already cancelled → nothing.
//
// A buyer never moves money and never force-cancels a paid order from the
// client: paid cancellations are written as a request document under
// orders/{id}/cancellationRequests and a Cloud Function performs the refund
// (reusing the audited escrow-refund path). Direct cancels of unpaid orders are
// still a client write, but the Firestore rules only permit them while the
// order is unpaid (onlySafeOrderChange).

/// Reason options a buyer can pick when cancelling / requesting cancellation.
const List<({String code, String label})> kCancelReasons = [
  (code: 'ordered_by_mistake', label: 'Ordered by mistake'),
  (code: 'incorrect_address', label: 'Incorrect address'),
  (code: 'change_products', label: 'Need to change products'),
  (code: 'payment_problem', label: 'Payment problem'),
  (code: 'seller_delay', label: 'Seller delay'),
  (code: 'other', label: 'Other'),
];

/// Human label for a stored cancellation reason code.
String cancelReasonLabel(String code) {
  for (final r in kCancelReasons) {
    if (r.code == code) return r.label;
  }
  return code.isEmpty ? 'Not specified' : code;
}

/// What the buyer is allowed to do about cancelling an order right now.
enum CancelUi {
  /// Order is unpaid — buyer cancels instantly (no money held).
  directCancel,

  /// Paid & held but not yet accepted — buyer can still cancel; PakBazar
  /// refunds the held payment to the buyer's wallet.
  cancelWithRefund,

  /// Seller has accepted / is preparing — buyer may only REQUEST cancellation,
  /// subject to seller/admin approval.
  requestApproval,

  /// Order has shipped — no self-service cancellation; contact support.
  supportOnly,

  /// Delivered / confirmed / released / already cancelled — no path.
  none,
}

/// Decides the buyer cancellation option for [o] from its live money + progress
/// state. Mirrors the server-side eligibility check in functions/index.js.
CancelUi cancelUiFor(Map<String, dynamic> o) {
  final status = o['status']?.toString() ?? '';
  // Terminal money states — nothing to cancel.
  if (status == 'released' ||
      status == 'completed' ||
      status == 'refunded' ||
      status == 'cancelled') {
    return CancelUi.none;
  }
  // Unpaid — instant cancel, no refund needed.
  if (status == 'pending_payment' || status == 'cod_pending') {
    return CancelUi.directCancel;
  }
  // Manual payment submitted, awaiting admin confirmation — unwind via review.
  if (status == 'payment_review') return CancelUi.requestApproval;
  // Paid & held by the platform: gate on the fulfillment stage. orderStatusOf
  // derives 'accepted' for legacy held orders with no explicit orderStatus, so
  // those safely fall into the request-only branch.
  if (status == 'in_escrow') {
    switch (orderStatusOf(o)) {
      case 'pending':
        return CancelUi.cancelWithRefund;
      case 'accepted':
      case 'processing':
        return CancelUi.requestApproval;
      case 'shipped':
        return CancelUi.supportOnly;
      default: // delivered, buyer_confirmed, ...
        return CancelUi.none;
    }
  }
  return CancelUi.none;
}

// ---------------------------------------------------------------------------
// Client write helpers
// ---------------------------------------------------------------------------

/// Directly cancels an UNPAID order (spec section 7, pre-acceptance path).
/// Records who cancelled and why; a Cloud Function (onOrderProgress) notifies
/// the seller + admin and writes the audit entry. Permitted by the Firestore
/// rules only while the order is still pending_payment / cod_pending.
Future<void> buyerDirectCancel(
  String orderId,
  String reasonCode,
  String details,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
    'status': 'cancelled',
    'orderStatus': 'cancelled',
    'cancelledAt': Timestamp.now(),
    'cancelledBy': uid,
    'cancelledByRole': 'buyer',
    'cancelReason': details.trim(),
    'cancelReasonCode': reasonCode,
    'updatedAt': Timestamp.now(),
  });
}

/// Files a cancellation request under orders/{id}/cancellationRequests (spec
/// section 8). A Cloud Function evaluates it: auto-approving (with refund) when
/// the order is still cancellable directly, or leaving it pending for the
/// seller/admin to decide once the order has been accepted.
Future<void> createCancellationRequest(
  String orderId,
  Map<String, dynamic> order,
  String reasonCode,
  String details,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('cancellationRequests')
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
        'sellerResponse': '',
        'adminDecision': '',
        'refundRequired': false,
        'refundStatus': 'not_required',
        'orderStatusAtRequest': orderStatusOf(order),
        'paymentStatusAtRequest': order['status']?.toString() ?? '',
      });
}

/// Buyer withdraws their own still-pending cancellation request.
Future<void> withdrawCancellationRequest(
  String orderId,
  String requestId,
) async {
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('cancellationRequests')
      .doc(requestId)
      .update({'requestStatus': 'withdrawn'});
}

/// Seller or admin approves/rejects a pending cancellation request. The heavy
/// lifting (cancel the order, issue a refund, notify, audit) is done by the
/// onCancellationRequestDecision Cloud Function.
Future<void> decideCancellationRequest(
  String orderId,
  String requestId, {
  required bool approve,
  String response = '',
  bool asAdmin = false,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final data = <String, dynamic>{
    'requestStatus': approve ? 'approved' : 'rejected',
    'reviewedAt': Timestamp.now(),
    'reviewedBy': uid,
    'decidedByRole': asAdmin ? 'admin' : 'seller',
  };
  if (response.trim().isNotEmpty) data['sellerResponse'] = response.trim();
  if (asAdmin) data['adminDecision'] = approve ? 'approved' : 'rejected';
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('cancellationRequests')
      .doc(requestId)
      .update(data);
}

/// Live stream of the still-pending cancellation requests for an order (used to
/// drive the buyer/seller cancellation UI). Single-field filter — no composite
/// index required.
Stream<QuerySnapshot<Map<String, dynamic>>> pendingCancellationRequests(
  String orderId,
) => FirebaseFirestore.instance
    .collection('orders')
    .doc(orderId)
    .collection('cancellationRequests')
    .where('requestStatus', isEqualTo: 'pending')
    .snapshots();

// ---------------------------------------------------------------------------
// UI — one insertion point per order card: CancellationSection.
// ---------------------------------------------------------------------------

/// Renders the cancellation controls for one order card. For a BUYER it shows
/// the status-appropriate action (Cancel / Request / Contact support / Withdraw
/// / declined notice). For a SELLER it shows an Approve/Reject card whenever a
/// buyer cancellation request is pending.
class CancellationSection extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final bool asSeller;
  const CancellationSection({
    super.key,
    required this.orderId,
    required this.data,
    required this.asSeller,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pendingCancellationRequests(orderId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final hasPending = docs.isNotEmpty;

        if (asSeller) {
          if (!hasPending) return const SizedBox.shrink();
          return _SellerCancellationCard(
            orderId: orderId,
            requestId: docs.first.id,
            request: docs.first.data(),
          );
        }

        // Buyer side.
        if (hasPending) {
          return _BuyerPendingRequestCard(
            orderId: orderId,
            requestId: docs.first.id,
            request: docs.first.data(),
          );
        }
        final reqStatus = data['cancellationRequestStatus']?.toString() ?? '';
        if (reqStatus == 'rejected') {
          final resp = data['cancellationDecisionNote']?.toString() ?? '';
          return _cancelBanner(
            icon: Icons.info_outline,
            color: Colors.orange,
            text: resp.isEmpty
                ? 'Your cancellation request was declined by the seller.'
                : 'Cancellation request declined: $resp',
          );
        }
        return _BuyerCancelAction(orderId: orderId, data: data);
      },
    );
  }
}

/// Small coloured info strip reused across the cancellation UI.
Widget _cancelBanner({
  required IconData icon,
  required Color color,
  required String text,
}) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  ),
);

class _BuyerCancelAction extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _BuyerCancelAction({required this.orderId, required this.data});

  @override
  Widget build(BuildContext context) {
    final ui = cancelUiFor(data);
    switch (ui) {
      case CancelUi.none:
        return const SizedBox.shrink();
      case CancelUi.supportOnly:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showDisputeSheet(context, orderId, data),
            icon: const Icon(Icons.support_agent, size: 16),
            label: const Text('Contact support'),
          ),
        );
      case CancelUi.directCancel:
      case CancelUi.cancelWithRefund:
      case CancelUi.requestApproval:
        final label = ui == CancelUi.requestApproval
            ? 'Request cancellation'
            : 'Cancel order';
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showCancellationSheet(context, orderId, data, ui),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: Text(label),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          ),
        );
    }
  }
}

class _BuyerPendingRequestCard extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _BuyerPendingRequestCard({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = cancelReasonLabel(request['reasonCode']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_top, size: 16, color: Colors.orange),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Cancellation requested — under review',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Reason: $reason. Your request has been sent for review.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await withdrawCancellationRequest(orderId, requestId);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Cancellation request withdrawn.'),
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

class _SellerCancellationCard extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _SellerCancellationCard({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = cancelReasonLabel(request['reasonCode']?.toString() ?? '');
    final details = request['reasonDetails']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cancel_schedule_send,
                  size: 16,
                  color: Colors.red,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Buyer requested cancellation',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Reason: $reason', style: const TextStyle(fontSize: 12)),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '“$details”',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _decide(context, approve: false),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () => _decide(context, approve: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  child: const Text('Approve & cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final messenger = ScaffoldMessenger.of(context);
    final noteCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(approve ? 'Approve cancellation?' : 'Reject request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'The order will be cancelled. If the buyer already paid, '
                        'PakBazar refunds them automatically.'
                  : 'The order stays active. Add a short note for the buyer.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtl,
              decoration: InputDecoration(
                labelText: approve ? 'Note (optional)' : 'Reason for the buyer',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    noteCtl.dispose();
    if (ok != true) return;
    try {
      await decideCancellationRequest(
        orderId,
        requestId,
        approve: approve,
        response: noteCtl.text,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Cancellation approved — processing.'
                : 'Cancellation request rejected.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }
}

/// Bottom sheet where the buyer picks a reason and confirms a cancellation /
/// cancellation request. [ui] selects the copy + which write path runs.
Future<void> showCancellationSheet(
  BuildContext context,
  String orderId,
  Map<String, dynamic> data,
  CancelUi ui,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var reasonCode = kCancelReasons.first.code;
  final detailsCtl = TextEditingController();
  var submitting = false;

  final isRequest = ui == CancelUi.requestApproval;
  final explanation = switch (ui) {
    CancelUi.requestApproval =>
      'This order has been accepted by the seller and cannot be cancelled '
          'directly. You can submit a cancellation request for review.',
    CancelUi.cancelWithRefund =>
      'Your payment is held safely by PakBazar. If you cancel now, it is '
          'refunded to your PakBazar wallet.',
    _ => 'You can cancel this order until the seller accepts it.',
  };

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
                Text(
                  isRequest ? 'Request cancellation' : 'Cancel order',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  explanation,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Why are you cancelling?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in kCancelReasons)
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
                            if (ui == CancelUi.directCancel) {
                              await buyerDirectCancel(
                                orderId,
                                reasonCode,
                                detailsCtl.text,
                              );
                            } else {
                              await createCancellationRequest(
                                orderId,
                                data,
                                reasonCode,
                                detailsCtl.text,
                              );
                            }
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
                            SnackBar(
                              content: Text(
                                isRequest
                                    ? 'Your cancellation request has been sent '
                                          'for review.'
                                    : 'Your order has been cancelled.',
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
                  label: Text(
                    isRequest ? 'Submit request' : 'Confirm cancellation',
                  ),
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
