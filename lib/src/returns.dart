part of '../main.dart';

// ---------------------------------------------------------------------------
// Order returns (Phase 4).
//
// After an order is delivered, the buyer can request a RETURN. It always needs
// seller/admin approval (unlike a pre-acceptance cancellation). Returns are
// self-service only while the payment is still HELD by the platform
// (status in_escrow + delivered/buyer_confirmed) so approval issues a clean
// refund with no seller-wallet clawback; once released/COD, returns go through
// support. On approval a Cloud Function reuses the audited escrow-refund path
// and sets orderStatus 'returned'. Mirrors the cancellation system.
// ---------------------------------------------------------------------------

const List<({String code, String label})> kReturnReasons = [
  (code: 'damaged', label: 'Damaged or defective'),
  (code: 'not_as_described', label: 'Not as described'),
  (code: 'wrong_item', label: 'Wrong item received'),
  (code: 'missing_parts', label: 'Missing parts or accessories'),
  (code: 'no_longer_needed', label: 'No longer needed'),
  (code: 'other', label: 'Other'),
];

String returnReasonLabel(String code) {
  for (final r in kReturnReasons) {
    if (r.code == code) return r.label;
  }
  return code.isEmpty ? 'Not specified' : code;
}

/// What the buyer can do about returning an order right now.
enum ReturnUi {
  /// Delivered & money still held → request a return (needs approval).
  request,

  /// Delivered but already settled / COD → support handles returns.
  supportOnly,

  /// Not delivered yet, or terminal — no return path.
  none,
}

/// Decides the return option for [o]. Mirrors returnEligibility() on the server.
ReturnUi returnUiFor(Map<String, dynamic> o) {
  final status = o['status']?.toString() ?? '';
  final os = orderStatusOf(o);
  if (status == 'in_escrow' && (os == 'delivered' || os == 'buyer_confirmed')) {
    return ReturnUi.request;
  }
  if (os == 'completed' ||
      status == 'released' ||
      status == 'completed' ||
      (os == 'delivered' && status == 'cod_pending')) {
    return ReturnUi.supportOnly;
  }
  return ReturnUi.none;
}

// --- Client write helpers ---------------------------------------------------

Future<void> createReturnRequest(
  String orderId,
  Map<String, dynamic> order,
  String reasonCode,
  String details,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('returnRequests')
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
        'refundStatus': 'pending',
        'orderStatusAtRequest': orderStatusOf(order),
        'paymentStatusAtRequest': order['status']?.toString() ?? '',
      });
}

Future<void> withdrawReturnRequest(String orderId, String requestId) async {
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .collection('returnRequests')
      .doc(requestId)
      .update({'requestStatus': 'withdrawn'});
}

Future<void> decideReturnRequest(
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
      .collection('returnRequests')
      .doc(requestId)
      .update(data);
}

Stream<QuerySnapshot<Map<String, dynamic>>> pendingReturnRequests(
  String orderId,
) => FirebaseFirestore.instance
    .collection('orders')
    .doc(orderId)
    .collection('returnRequests')
    .where('requestStatus', isEqualTo: 'pending')
    .snapshots();

// --- UI ---------------------------------------------------------------------

/// Return controls for one order card. Buyer: request / pending / declined
/// notice. Seller: approve/reject when a return request is pending.
class ReturnSection extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final bool asSeller;
  const ReturnSection({
    super.key,
    required this.orderId,
    required this.data,
    required this.asSeller,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pendingReturnRequests(orderId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final hasPending = docs.isNotEmpty;

        if (asSeller) {
          if (!hasPending) return const SizedBox.shrink();
          return _SellerReturnCard(
            orderId: orderId,
            requestId: docs.first.id,
            request: docs.first.data(),
          );
        }
        if (hasPending) {
          return _BuyerReturnPendingCard(
            orderId: orderId,
            requestId: docs.first.id,
            request: docs.first.data(),
          );
        }
        final reqStatus = data['returnRequestStatus']?.toString() ?? '';
        if (reqStatus == 'rejected') {
          final note = data['returnDecisionNote']?.toString() ?? '';
          return _cancelBanner(
            icon: Icons.info_outline,
            color: Colors.orange,
            text: note.isEmpty
                ? 'Your return request was declined.'
                : 'Return request declined: $note',
          );
        }
        if (reqStatus == 'approved' || orderStatusOf(data) == 'returned') {
          return _cancelBanner(
            icon: Icons.assignment_return,
            color: Colors.blueGrey,
            text: 'This order was returned and refunded.',
          );
        }
        return _BuyerReturnAction(orderId: orderId, data: data);
      },
    );
  }
}

class _BuyerReturnAction extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _BuyerReturnAction({required this.orderId, required this.data});

  @override
  Widget build(BuildContext context) {
    switch (returnUiFor(data)) {
      case ReturnUi.none:
        return const SizedBox.shrink();
      case ReturnUi.supportOnly:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showDisputeSheet(context, orderId, data),
            icon: const Icon(Icons.assignment_return_outlined, size: 16),
            label: const Text('Return / report a problem'),
          ),
        );
      case ReturnUi.request:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showReturnSheet(context, orderId, data),
            icon: const Icon(Icons.assignment_return_outlined, size: 16),
            label: const Text('Request return'),
            style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
          ),
        );
    }
  }
}

class _BuyerReturnPendingCard extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _BuyerReturnPendingCard({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = returnReasonLabel(request['reasonCode']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withValues(alpha: 0.08),
          borderRadius: AppRadius.rSm,
          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hourglass_top,
                  size: 16,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Return requested — under review',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Text(
              'Reason: $reason',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await withdrawReturnRequest(orderId, requestId);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Return request withdrawn.'),
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

class _SellerReturnCard extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _SellerReturnCard({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = returnReasonLabel(request['reasonCode']?.toString() ?? '');
    final details = request['reasonDetails']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withValues(alpha: 0.06),
          borderRadius: AppRadius.rSm,
          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.assignment_return,
                  size: 16,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Buyer requested a return',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Text('Reason: $reason', style: const TextStyle(fontSize: 12)),
            if (details.isNotEmpty)
              Text(
                '“$details”',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                    backgroundColor: Colors.blueGrey,
                  ),
                  child: const Text('Approve & refund'),
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
        title: Text(approve ? 'Approve return?' : 'Reject return?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'The buyer will be refunded to their wallet and the order '
                        'marked returned. Arrange collection of the item.'
                  : 'The order stays as-is. Add a note for the buyer.',
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
      await decideReturnRequest(
        orderId,
        requestId,
        approve: approve,
        response: noteCtl.text,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Return approved — refunding.'
                : 'Return request rejected.',
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

/// Bottom sheet: buyer picks a reason and submits a return request.
Future<void> showReturnSheet(
  BuildContext context,
  String orderId,
  Map<String, dynamic> data,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var reasonCode = kReturnReasons.first.code;
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
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Request a return',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your payment is held by PakBazar. If the seller or PakBazar '
                  'approves, it is refunded to your wallet.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Why are you returning this?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in kReturnReasons)
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
                            await createReturnRequest(
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
                                'Your return request has been sent for review.',
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
