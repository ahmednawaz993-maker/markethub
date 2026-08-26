part of '../main.dart';

// Admin-side order management.
//
// The seller drives fulfillment (accept → ready → dispatched) and the buyer
// confirms receipt. That works right up until a seller goes quiet, and then an
// order sits at "pending" with a buyer who has already paid and nobody able to
// move it. This file is the back-office answer to that: every order is visible,
// inspectable, editable and — when the seller misses the acceptance window —
// advanceable by an admin, who can also reach the seller on WhatsApp/phone and
// leave a follow-up trail on the order.
//
// DELIBERATE LIMIT: money is never written here. Amounts, commission, payout
// and the escrow `status` machine belong to the Cloud Functions (admin SDK),
// and the firestore rules only exempt back-office writes because the panel is
// trusted — not because editing them is safe. Anything with a money
// consequence (refund, escrow release) routes to the flow that owns it.

/// How long a seller has to accept before the order is flagged for admin
/// follow-up. Kept as a constant rather than a config doc so it needs no rules
/// change; bump it here if the acceptance window ever moves.
const int kSellerAcceptSlaHours = 24;

/// Order fields the admin editor must never write. These are owned by the
/// Cloud Functions that run the escrow/payout machine — editing `amount` on a
/// paid order would silently desync the commission, the seller payout and the
/// financial audit trail from what the buyer actually paid.
const List<String> kAdminUneditableOrderFields = [
  'amount',
  'commission',
  'sellerPayout',
  'paymentStatus',
  'itemSubtotal',
  'deliveryFee',
  'platformCommissionRate',
  'platformCommissionAmount',
  'sellerPayableAmount',
  'releasedAmount',
  'refundAmount',
  'transactionReference',
  'paymentId',
];

/// Hours since the buyer placed the order, or null when it carries no
/// createdAt (very old docs).
double? orderAgeHours(Map<String, dynamic> d) {
  final ts = d['createdAt'] as Timestamp?;
  if (ts == null) return null;
  return DateTime.now().difference(ts.toDate()).inMinutes / 60.0;
}

/// True when an order is still waiting on the seller's acceptance past the
/// SLA. Cancelled/rejected/completed orders are never "waiting" — and neither
/// is one the buyer has not paid for yet, since there is nothing for the seller
/// to accept until the money lands (or it is COD, which is live immediately).
bool orderAwaitingSellerTooLong(Map<String, dynamic> d) {
  if (orderStatusOf(d) != 'pending') return false;
  final money = d['status']?.toString() ?? '';
  if (money == 'pending_payment' || money == 'payment_review') return false;
  final age = orderAgeHours(d);
  return age != null && age >= kSellerAcceptSlaHours;
}

/// True when the payment is held by the platform or already paid out, so
/// cancelling or deleting the order has a real money consequence that this
/// panel must not apply on its own.
bool orderMoneyIsCommitted(Map<String, dynamic> d) {
  final money = d['status']?.toString() ?? '';
  return money == 'in_escrow' || money == 'released' || money == 'completed';
}

/// Appends one entry to the order's admin follow-up trail.
///
/// The platform audit log (`financialAuditLog`) is Cloud-Functions-only, so an
/// admin acting from the panel has nowhere server-side to record it. Keeping
/// the trail on the order doc means the next person to open it can see who
/// accepted on the seller's behalf, when, and why.
Map<String, dynamic> _adminTrailEntry(String action, String note) => {
  'action': action,
  'note': note,
  'by': FirebaseAuth.instance.currentUser?.email ?? '',
  'at': Timestamp.now(),
};

/// Advances an order's fulfillment as an admin, on the seller's behalf.
///
/// Writes the same fulfillment fields the seller's own flow writes, so the
/// existing onOrderProgress Cloud Function still fires and the buyer still gets
/// the normal "Order accepted" / "Order shipped" notification — the buyer sees
/// no difference. The extra `adminAdvanced*` stamps record that a human in the
/// back office moved it, which the seller's own writes never set.
Future<void> adminAdvanceOrder(
  String orderId,
  String toStatus, {
  String courierName = '',
  String trackingNumber = '',
  String trackingUrl = '',
  String note = '',
}) async {
  final data = <String, dynamic>{
    'orderStatus': toStatus,
    'updatedAt': Timestamp.now(),
    'adminAdvancedBy': FirebaseAuth.instance.currentUser?.email ?? '',
    'adminAdvancedAt': Timestamp.now(),
    'adminActions': FieldValue.arrayUnion([
      _adminTrailEntry('advanced_to_$toStatus', note),
    ]),
  };
  if (toStatus == 'accepted') {
    data['acceptedAt'] = Timestamp.now();
    // Distinguishes an admin rescue from the seller accepting normally, so
    // seller-responsiveness reporting is not quietly flattered by it.
    data['acceptedByAdmin'] = true;
  }
  if (toStatus == 'shipped') {
    if (courierName.trim().isNotEmpty) {
      data['courierName'] = courierName.trim();
    }
    if (trackingNumber.trim().isNotEmpty) {
      data['trackingNumber'] = trackingNumber.trim();
    }
    if (trackingUrl.trim().isNotEmpty) data['trackingUrl'] = trackingUrl.trim();
    data['shippedAt'] = Timestamp.now();
  }
  if (toStatus == 'delivered') data['deliveredAt'] = Timestamp.now();
  await FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .update(data);
}

/// Saves the operational (non-money) fields an admin may correct: where it is
/// going, who to call about it, and the courier details.
Future<void> adminEditOrderDetails(
  String orderId, {
  required String deliveryAddress,
  required String buyerPhone,
  required String courierName,
  required String trackingNumber,
  required String trackingUrl,
  required String adminNote,
}) async {
  await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
    'deliveryAddress': deliveryAddress.trim(),
    'buyerPhone': buyerPhone.trim(),
    'courierName': courierName.trim(),
    'trackingNumber': trackingNumber.trim(),
    'trackingUrl': trackingUrl.trim(),
    'adminNote': adminNote.trim(),
    'updatedAt': Timestamp.now(),
    'adminActions': FieldValue.arrayUnion([
      _adminTrailEntry('edited_details', adminNote.trim()),
    ]),
  });
}

/// Cancels an order that carries no committed money (unpaid or COD).
///
/// Held or paid-out orders are refused: unwinding those means issuing a refund
/// through the escrow flow, which is server-side and audited. Doing it here
/// would mark the order cancelled while the money stayed exactly where it was.
Future<void> adminCancelOrder(
  String orderId,
  Map<String, dynamic> data, {
  required String reason,
}) async {
  if (orderMoneyIsCommitted(data)) {
    throw StateError('Payment is committed — use the refund flow.');
  }
  await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
    'status': 'cancelled',
    'orderStatus': 'cancelled',
    'cancelledAt': Timestamp.now(),
    'cancelledByRole': 'admin',
    'cancelReason': reason.trim(),
    'updatedAt': Timestamp.now(),
    'adminActions': FieldValue.arrayUnion([
      _adminTrailEntry('cancelled', reason.trim()),
    ]),
  });
}

/// Drops a notice into a user's in-app notification feed.
///
/// In-app only: pushes are sent by Cloud Functions via the Admin SDK, and there
/// is no trigger on notification documents, so this will NOT ring the seller's
/// phone. That is exactly why the order screen pairs it with WhatsApp/call —
/// chasing a silent seller needs a channel they will actually see.
Future<void> adminNotifyUser(
  String uid,
  String title,
  String body, {
  String orderId = '',
}) async {
  if (uid.isEmpty) return;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .add({
        'title': title,
        'body': body,
        'type': 'order',
        if (orderId.isNotEmpty) 'orderId': orderId,
        'read': false,
        'createdAt': Timestamp.now(),
      });
}

/// Shared confirmation for a back-office action that destroys something.
///
/// The admin panel had several one-tap deletes with no confirmation at all —
/// a stray tap in the Reports queue permanently removed a seller's live ad.
/// Anything irreversible routes through here so the consequence is stated
/// before it happens.
Future<bool> _confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Compact step names for the admin progress strip. The buyer-facing
/// [orderStatusLabel] strings ("Ready to dispatch") are far too long to sit
/// five-across on a phone.
String _shortStepLabel(String s) => switch (s) {
  'pending' => 'Placed',
  'accepted' => 'Accepted',
  'processing' => 'Ready',
  'shipped' => 'Dispatched',
  'delivered' => 'Delivered',
  _ => orderStatusLabel(s),
};

void _openWhatsAppNumber(String number) {
  final cleaned = normalizePhoneForWhatsApp(number);
  if (cleaned.isEmpty) return;
  launchUrl(
    Uri.parse('https://wa.me/$cleaned'),
    mode: LaunchMode.externalApplication,
  );
}

void _dialNumber(String number) {
  final n = number.trim();
  if (n.isEmpty) return;
  launchUrl(Uri.parse('tel:$n'), mode: LaunchMode.externalApplication);
}

// ---------------------------------------------------------------------------
// Order manager screen
// ---------------------------------------------------------------------------

/// Everything about one order, plus every admin action that order allows.
/// Streams the doc so it reflects a seller acting at the same moment.
class AdminOrderScreen extends StatelessWidget {
  const AdminOrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order')),
            body: const EmptyState(
              icon: Icons.receipt_long,
              title: 'Order deleted',
              subtitle: 'This order no longer exists.',
            ),
          );
        }
        final d = snap.data!.data() as Map<String, dynamic>;
        return AdminOrderView(orderId: orderId, data: d);
      },
    );
  }
}

/// Public so the layout tests can pump it at real phone widths — it is a dense
/// screen (fixed-width label column, a five-step timeline in one Row) and this
/// repo treats "no overflow at 320px" as a rule worth pinning.
class AdminOrderView extends StatelessWidget {
  const AdminOrderView({super.key, required this.orderId, required this.data});

  final String orderId;
  final Map<String, dynamic> data;

  String get _number =>
      (data['orderNumber']?.toString() ?? '').isEmpty
      ? orderId
      : data['orderNumber'].toString();

  @override
  Widget build(BuildContext context) {
    final fulfil = orderStatusOf(data);
    final overdue = orderAwaitingSellerTooLong(data);
    final age = orderAgeHours(data);

    return Scaffold(
      appBar: AppBar(
        title: Text(_number),
        actions: [
          IconButton(
            tooltip: 'Copy order number',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _number));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied $_number')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        children: [
          if (overdue) _overdueBanner(context, age),
          _statusCard(fulfil),
          const SizedBox(height: AppSpacing.md),
          _partiesCard(context),
          const SizedBox(height: AppSpacing.md),
          _deliveryCard(),
          const SizedBox(height: AppSpacing.md),
          _moneyCard(),
          const SizedBox(height: AppSpacing.md),
          _actionsCard(context, fulfil),
          const SizedBox(height: AppSpacing.md),
          _trailCard(),
        ],
      ),
    );
  }

  Widget _overdueBanner(BuildContext context, double? age) {
    final hrs = age == null ? '' : ' — ${age.round()}h old';
    return Card(
      color: const Color(0xFFFFF3CD),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.running_with_errors, color: Colors.orange),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'The seller has not accepted this order within '
                '$kSellerAcceptSlaHours hours$hrs. Contact them below, or '
                'accept on their behalf to keep the buyer moving.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppType.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _statusCard(String fulfil) {
    final steps = ['pending', 'accepted', 'processing', 'shipped', 'delivered'];
    final idx = steps.indexOf(fulfil);
    return _section('Status', [
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(orderStatusLabel(fulfil)),
            backgroundColor: kPakGreen.withValues(alpha: 0.12),
          ),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(paymentStatusLabel(paymentStatusOf(data))),
            backgroundColor: Colors.blueGrey.withValues(alpha: 0.12),
          ),
          if (data['paymentMethod']?.toString() == 'cod')
            const Chip(
              visualDensity: VisualDensity.compact,
              label: Text('Cash on delivery'),
            ),
          if (data['acceptedByAdmin'] == true)
            const Chip(
              visualDensity: VisualDensity.compact,
              label: Text('Accepted by admin'),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      // Same order of steps the buyer sees on their own order card, so an
      // admin reading a complaint is looking at the buyer's view.
      //
      // A Wrap, not a Row: five steps of long-form labels overflowed a 320px
      // phone by 354px. Short step names (the seller's own progress strip uses
      // these) plus wrapping means it cannot overflow at any width or text
      // scale — the long labels still appear on the status chip above.
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (var i = 0; i < steps.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  i <= idx ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 13,
                  color: i <= idx ? kPakGreen : Colors.grey.shade400,
                ),
                const SizedBox(width: 3),
                Text(
                  _shortStepLabel(steps[i]),
                  style: TextStyle(
                    fontSize: 11,
                    color: i <= idx ? kPakGreen : Colors.grey,
                    fontWeight: i == idx ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      _row(Icons.tag, 'Order', _number),
      _row(Icons.shopping_bag_outlined, 'Item',
          data['listingTitle']?.toString() ?? ''),
      _row(Icons.numbers, 'Quantity', '${data['quantity'] ?? 1}'),
      _row(Icons.schedule, 'Placed',
          timeAgo(data['createdAt'] as Timestamp?)),
      if (data['updatedAt'] != null)
        _row(Icons.update, 'Updated', timeAgo(data['updatedAt'] as Timestamp?)),
    ]);
  }

  Widget _partiesCard(BuildContext context) => _section('People', [
    _ContactRow(
      role: 'Buyer',
      name: data['buyerName']?.toString() ?? '',
      uid: data['buyerId']?.toString() ?? '',
      fallbackPhone: data['buyerPhone']?.toString() ?? '',
      orderId: orderId,
      orderNumber: _number,
      isSeller: false,
    ),
    const Divider(),
    _ContactRow(
      role: 'Seller',
      name: data['sellerName']?.toString() ?? '',
      uid: data['sellerId']?.toString() ?? '',
      fallbackPhone: '',
      orderId: orderId,
      orderNumber: _number,
      isSeller: true,
      listingId: data['listingId']?.toString() ?? '',
    ),
  ]);

  Widget _deliveryCard() => _section('Delivery', [
    _row(Icons.home_outlined, 'Address',
        data['deliveryAddress']?.toString() ?? ''),
    _row(Icons.phone, 'Phone', data['buyerPhone']?.toString() ?? ''),
    _row(Icons.local_shipping, 'Courier',
        data['courierName']?.toString() ?? ''),
    _row(Icons.qr_code, 'Tracking', data['trackingNumber']?.toString() ?? ''),
    if ((data['sellerNote']?.toString() ?? '').isNotEmpty)
      _row(Icons.sticky_note_2_outlined, 'Seller note',
          data['sellerNote'].toString()),
    if ((data['adminNote']?.toString() ?? '').isNotEmpty)
      _row(Icons.admin_panel_settings, 'Admin note',
          data['adminNote'].toString()),
  ]);

  Widget _moneyCard() => _section('Payment', [
    _row(Icons.payments, 'Total',
        formatPrice('${data['amount'] ?? 0}')),
    _row(Icons.percent, 'Commission',
        formatPrice('${data['commission'] ?? 0}')),
    _row(Icons.account_balance_wallet, 'Seller payout',
        formatPrice('${data['sellerPayout'] ?? 0}')),
    _row(Icons.credit_card, 'Method',
        data['paymentMethod']?.toString() ?? ''),
    Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        'Amounts are owned by the payment/escrow backend and cannot be '
        'edited here. Use Escrow, Payments or the refund flow to move money.',
        style: AppType.caption,
      ),
    ),
  ]);

  Widget _actionsCard(BuildContext context, String fulfil) {
    final next = nextShippingStep(fulfil);
    final committed = orderMoneyIsCommitted(data);
    final closed = ['cancelled', 'rejected', 'completed', 'returned']
        .contains(fulfil);

    return _section('Admin actions', [
      if (closed)
        Text(
          'This order is ${orderStatusLabel(fulfil).toLowerCase()} — '
          'fulfillment actions are closed.',
          style: AppType.secondary,
        )
      else ...[
        if (next.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  next == 'accepted' ? Icons.check : Icons.arrow_forward,
                  size: 18,
                ),
                label: Text(
                  switch (next) {
                    'accepted' => 'Accept on seller\'s behalf',
                    'processing' => 'Mark ready to dispatch',
                    'shipped' => 'Mark dispatched',
                    _ => 'Advance order',
                  },
                ),
                onPressed: () => _advance(context, next),
              ),
            ),
          ),
        if (fulfil == 'shipped')
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.inventory, size: 18),
                label: const Text('Mark delivered'),
                onPressed: () => _advance(context, 'delivered'),
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit delivery & tracking'),
            onPressed: () => _edit(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: committed ? Colors.grey : Colors.orange,
            ),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: Text(
              committed ? 'Cancel — use refund flow' : 'Cancel order',
            ),
            onPressed: committed ? null : () => _cancel(context),
          ),
        ),
        if (committed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'The payment is held or already paid out. Cancelling here would '
              'mark the order cancelled without moving the money — issue a '
              'refund from the Refunds/Escrow tab instead.',
              style: AppType.caption,
            ),
          ),
      ],
      const Divider(height: AppSpacing.xl),
      SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete order'),
          onPressed: () => _delete(context),
        ),
      ),
    ]);
  }

  Widget _trailCard() {
    final raw = (data['adminActions'] as List?) ?? const [];
    if (raw.isEmpty) {
      return _section('Admin trail', [
        Text('No admin action on this order yet.', style: AppType.secondary),
      ]);
    }
    final entries = raw.whereType<Map>().toList()
      ..sort((a, b) {
        final at = (a['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bt = (b['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
    return _section('Admin trail', [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${e['action'] ?? ''} · ${e['by'] ?? ''}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  timeAgo(e['at'] as Timestamp?),
                  if ((e['note']?.toString() ?? '').isNotEmpty)
                    e['note'].toString(),
                ].join(' · '),
                style: AppType.caption,
              ),
            ],
          ),
        ),
    ]);
  }

  // -- action handlers ------------------------------------------------------

  Future<void> _advance(BuildContext context, String to) async {
    final messenger = ScaffoldMessenger.of(context);
    final noteCtrl = TextEditingController();
    final courierCtrl = TextEditingController(
      text: data['courierName']?.toString() ?? '',
    );
    final trackCtrl = TextEditingController(
      text: data['trackingNumber']?.toString() ?? '',
    );
    final isShip = to == 'shipped';
    final label = orderStatusLabel(to);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark "$label"?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                to == 'accepted'
                    ? 'You are accepting on behalf of '
                          '${data['sellerName'] ?? 'the seller'}. The buyer is '
                          'notified exactly as if the seller had accepted, and '
                          'the order is stamped as an admin acceptance.'
                    : 'The buyer is notified of this step.',
                style: AppType.secondary,
              ),
              if (isShip) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: courierCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Courier',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: trackCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tracking number',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Why (kept on the order)',
                  hintText: 'e.g. seller unreachable for 2 days',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Mark $label'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text;
    final courier = courierCtrl.text;
    final tracking = trackCtrl.text;
    noteCtrl.dispose();
    courierCtrl.dispose();
    trackCtrl.dispose();
    if (ok != true) return;
    try {
      await adminAdvanceOrder(
        orderId,
        to,
        courierName: courier,
        trackingNumber: tracking,
        note: note,
      );
      messenger.showSnackBar(SnackBar(content: Text('Order marked "$label".')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _edit(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final address = TextEditingController(
      text: data['deliveryAddress']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: data['buyerPhone']?.toString() ?? '',
    );
    final courier = TextEditingController(
      text: data['courierName']?.toString() ?? '',
    );
    final tracking = TextEditingController(
      text: data['trackingNumber']?.toString() ?? '',
    );
    final trackingUrl = TextEditingController(
      text: data['trackingUrl']?.toString() ?? '',
    );
    final note = TextEditingController(
      text: data['adminNote']?.toString() ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit order'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (c, label) in [
                  (address, 'Delivery address'),
                  (phone, 'Contact phone'),
                  (courier, 'Courier'),
                  (tracking, 'Tracking number'),
                  (trackingUrl, 'Tracking URL'),
                  (note, 'Admin note'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TextField(
                      controller: c,
                      maxLines: label == 'Delivery address' ? 2 : 1,
                      decoration: InputDecoration(
                        labelText: label,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                Text(
                  'Amounts, commission and payout are not editable — they are '
                  'owned by the payment backend.',
                  style: AppType.caption,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final values = (
      address.text,
      phone.text,
      courier.text,
      tracking.text,
      trackingUrl.text,
      note.text,
    );
    for (final c in [address, phone, courier, tracking, trackingUrl, note]) {
      c.dispose();
    }
    if (ok != true) return;
    try {
      await adminEditOrderDetails(
        orderId,
        deliveryAddress: values.$1,
        buyerPhone: values.$2,
        courierName: values.$3,
        trackingNumber: values.$4,
        trackingUrl: values.$5,
        adminNote: values.$6,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Order updated.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The buyer and seller are both notified. No money moves — this '
              'order has nothing held by the platform.',
              style: AppType.secondary,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep order'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    final why = reason.text;
    reason.dispose();
    if (ok != true) return;
    try {
      await adminCancelOrder(orderId, data, reason: why);
      await adminNotifyUser(
        data['buyerId']?.toString() ?? '',
        'Order cancelled',
        'Your order $_number was cancelled by PakBazar support'
        '${why.trim().isEmpty ? '' : ': ${why.trim()}'}.',
        orderId: orderId,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Order cancelled.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final committed = orderMoneyIsCommitted(data);
    final confirmCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete this order?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deleting removes the record for the buyer and the seller too. '
                'It cannot be undone. Cancelling is almost always the right '
                'action instead — it keeps the history.',
                style: AppType.secondary,
              ),
              if (committed) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'This order has money held or already paid out. Deleting it '
                  'leaves the payment and payout records pointing at an order '
                  'that no longer exists. Type $_number to confirm.',
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: confirmCtrl,
                  onChanged: (_) => setLocal(() {}),
                  decoration: InputDecoration(
                    labelText: 'Type $_number',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: committed && confirmCtrl.text.trim() != _number
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .delete();
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Order deleted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }
}

/// One party on the order, with the channels an admin can actually reach them
/// on. The phone is loaded from the private contact doc (orders only carry the
/// buyer's), which is why this is stateful.
class _ContactRow extends StatefulWidget {
  const _ContactRow({
    required this.role,
    required this.name,
    required this.uid,
    required this.fallbackPhone,
    required this.orderId,
    required this.orderNumber,
    required this.isSeller,
    this.listingId = '',
  });

  final String role;
  final String name;
  final String uid;
  final String fallbackPhone;
  final String orderId;
  final String orderNumber;
  final bool isSeller;
  final String listingId;

  @override
  State<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends State<_ContactRow> {
  String _phone = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var phone = widget.fallbackPhone;
    if (widget.uid.isNotEmpty) {
      try {
        final c = await loadPrivateContact(widget.uid);
        final p = c['phone']?.toString() ?? '';
        if (p.isNotEmpty) phone = p;
      } catch (_) {}
    }
    // Sellers publish a contact number on the ad itself, and an order carries
    // no seller phone at all — so fall back to the listing when the profile has
    // nothing. This is also the safety net if the private-contact read is
    // denied for a staff role.
    if (phone.isEmpty && widget.isSeller && widget.listingId.isNotEmpty) {
      try {
        final l = await FirebaseFirestore.instance
            .collection('listings')
            .doc(widget.listingId)
            .get();
        phone = l.data()?['phone']?.toString() ?? '';
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _phone = phone;
      _loading = false;
    });
  }

  Future<void> _nudge() async {
    final messenger = ScaffoldMessenger.of(context);
    final body = widget.isSeller
        ? 'Order ${widget.orderNumber} is still waiting for you to accept it. '
              'Please open Selling → Orders and accept or decline it now.'
        : 'An update on your order ${widget.orderNumber} — our team is '
              'following it up with the seller.';
    try {
      await adminNotifyUser(
        widget.uid,
        widget.isSeller ? 'Please accept your order' : 'Order update',
        body,
        orderId: widget.orderId,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('In-app reminder sent to ${widget.role}.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.role,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                widget.name.isEmpty ? '(no name)' : widget.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (_loading)
          Text('Loading contact…', style: AppType.caption)
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  _phone.isEmpty ? 'No phone on file' : _phone,
                  style: AppType.caption,
                ),
              ),
              IconButton(
                tooltip: 'WhatsApp',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                onPressed: _phone.isEmpty
                    ? null
                    : () => _openWhatsAppNumber(_phone),
              ),
              IconButton(
                tooltip: 'Call',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.call, color: kPakGreen),
                onPressed: _phone.isEmpty ? null : () => _dialNumber(_phone),
              ),
              IconButton(
                tooltip: 'Send in-app reminder',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: widget.uid.isEmpty ? null : _nudge,
              ),
            ],
          ),
      ],
    );
  }
}
