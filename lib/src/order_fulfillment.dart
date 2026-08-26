part of '../main.dart';

// Seller shipping flow + buyer delivery confirmation for a platform-held
// (escrow) order. Rendered inside each order card while the payment is held by
// PakBazar. Money is never moved here — the seller only advances fulfillment
// (accept → process → ship → deliver) and the buyer confirms receipt; the
// payout stays server-authoritative (Cloud Functions).

/// The ordered fulfillment steps shown in the little progress strip. The seller
/// drives Accepted → Ready → Dispatched; the buyer's receipt confirmation is
/// the final "Delivered" step.
const List<({String key, String label})> _shipSteps = [
  (key: 'accepted', label: 'Accepted'),
  (key: 'processing', label: 'Ready'),
  (key: 'shipped', label: 'Dispatched'),
  (key: 'delivered', label: 'Delivered'),
];

int _shipStepIndex(String orderStatus) => switch (orderStatus) {
  'accepted' => 0,
  'processing' => 1,
  'shipped' => 2,
  // The buyer confirming receipt (buyer_confirmed) IS the Delivered step.
  'delivered' || 'buyer_confirmed' || 'completed' => 3,
  _ => -1,
};

class OrderFulfillmentPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  final String orderId;
  final bool asSeller;
  const OrderFulfillmentPanel({
    super.key,
    required this.data,
    required this.orderId,
    required this.asSeller,
  });

  /// COD orders share the same Accepted→Ready→Dispatched→Delivered tracking, but
  /// there is no held payment: confirming receipt completes the order (cash was
  /// collected on delivery) rather than releasing an escrow payout.
  bool get _isCod =>
      data['paymentMethod']?.toString() == 'cod' ||
      data['status']?.toString() == 'cod_pending';

  @override
  Widget build(BuildContext context) {
    final orderStatus = orderStatusOf(data);
    final buyerConfirmed = data['buyerConfirmed'] == true;
    final courier = data['courierName']?.toString() ?? '';
    final tracking = data['trackingNumber']?.toString() ?? '';
    final trackingUrl = data['trackingUrl']?.toString() ?? '';
    final shippedAt = data['shippedAt'] as Timestamp?;
    final deliveredAt = data['deliveredAt'] as Timestamp?;
    final shipDates = [
      if (shippedAt != null) 'Shipped ${timeAgo(shippedAt)}',
      if (deliveredAt != null) 'Delivered ${timeAgo(deliveredAt)}',
    ].join(' · ');
    final activeIdx = _shipStepIndex(
      buyerConfirmed ? 'buyer_confirmed' : orderStatus,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // Progress strip.
        Row(
          children: [
            for (var i = 0; i < _shipSteps.length; i++) ...[
              Icon(
                i <= activeIdx
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 14,
                color: i <= activeIdx ? kPakGreen : Colors.grey.shade400,
              ),
              const SizedBox(width: 2),
              Text(
                _shipSteps[i].label,
                style: TextStyle(
                  fontSize: 10,
                  color: i <= activeIdx ? kPakGreen : Colors.grey,
                  fontWeight: i == activeIdx
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              if (i < _shipSteps.length - 1)
                const Expanded(child: Divider(indent: 3, endIndent: 3)),
            ],
          ],
        ),
        // Tracking info (both sides once shipped).
        if (courier.isNotEmpty || tracking.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.local_shipping, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  [
                    if (courier.isNotEmpty) courier,
                    if (tracking.isNotEmpty) 'Tracking: $tracking',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (trackingUrl.isNotEmpty)
                TextButton(
                  onPressed: () {
                    final uri = Uri.tryParse(trackingUrl);
                    if (uri != null) {
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Track'),
                ),
            ],
          ),
        ],
        if (shipDates.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                shipDates,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
        // Seller actions.
        if (asSeller) _sellerActions(context, orderStatus),
        // Buyer confirmation.
        if (!asSeller) _buyerActions(context, orderStatus, buyerConfirmed),
      ],
    );
  }

  Widget _sellerActions(BuildContext context, String orderStatus) {
    // After dispatch the seller is done — the buyer confirms receipt next.
    if (orderStatus == 'shipped' || orderStatus == 'delivered') {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _isCod
              ? 'Dispatched — waiting for the buyer to confirm they received it '
                    '(cash collected on delivery).'
              : 'Dispatched — waiting for the buyer to confirm they received it, '
                    'which releases your payout for settlement.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }
    final next = nextShippingStep(orderStatus);
    if (next.isEmpty) return const SizedBox.shrink();
    final (label, icon) = switch (next) {
      'accepted' => ('Accept order', Icons.check),
      'processing' => ('Mark ready to dispatch', Icons.inventory_2_outlined),
      'shipped' => ('Mark dispatched', Icons.local_shipping),
      _ => ('Advance', Icons.arrow_forward),
    };
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ElevatedButton.icon(
          onPressed: () {
            // Dispatching requires courier + tracking (collected in the sheet).
            if (next == 'shipped') {
              _showShipSheet(context);
            } else {
              _advance(context, next);
            }
          },
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _buyerActions(
    BuildContext context,
    String orderStatus,
    bool buyerConfirmed,
  ) {
    if (buyerConfirmed ||
        orderStatus == 'buyer_confirmed' ||
        (_isCod && orderStatus == 'delivered')) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            const Icon(Icons.verified, size: 16, color: kPakGreen),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _isCod
                    ? 'Delivered — you confirmed receipt. This order is complete.'
                    : 'Delivered — you confirmed receipt. The seller payout is '
                          'pending platform settlement.',
                style: const TextStyle(
                  fontSize: 12,
                  color: kPakGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    // The buyer confirms receipt once the order has been dispatched (or on a
    // legacy held order that never entered the fulfillment flow).
    final canConfirm = orderStatus == 'shipped' || orderStatus == 'delivered';
    if (!canConfirm) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _isCod
              ? 'The seller is preparing your order. Pay cash to the courier on '
                    'delivery, then confirm receipt once it has been dispatched.'
              : 'The seller is preparing your order. You can confirm receipt '
                    'once it has been dispatched.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ElevatedButton.icon(
          onPressed: () => _confirmDelivery(context),
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Confirm receipt (mark Delivered)'),
        ),
      ),
    );
  }

  Future<void> _advance(BuildContext context, String to) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setOrderShipping(orderId, to);
      messenger.showSnackBar(
        SnackBar(content: Text('Order marked "${orderStatusLabel(to)}".')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }

  Future<void> _confirmDelivery(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Confirm receipt'),
        content: Text(
          _isCod
              ? 'Confirm only after you have received and checked your order '
                    'and paid the courier. This marks it Delivered and '
                    'completes the order.'
              : 'Confirm only after you have received and checked your order. '
                    'This marks it Delivered and lets PakBazar settle the '
                    'payment to the seller.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Mark Delivered'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await confirmOrderDelivery(orderId, isCod: _isCod);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isCod
                ? 'Thank you — your order is marked delivered.'
                : 'Thank you — the seller payout is now under review.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not confirm. Please try again.')),
      );
    }
  }

  Future<void> _showShipSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final courier = TextEditingController();
    final tracking = TextEditingController();
    final url = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Dispatch order',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _isCod
                      ? 'Add a courier and tracking number if you are using a '
                            'courier, or leave them blank for a hand delivery. '
                            'Marking dispatched notifies the buyer.'
                      : 'Enter the courier and tracking number so the buyer can '
                            'follow the delivery. Marking dispatched notifies '
                            'the buyer.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: courier,
                  decoration: InputDecoration(
                    labelText: _isCod
                        ? 'Courier (optional)'
                        : 'Courier (e.g. TCS, Leopards)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tracking,
                  decoration: InputDecoration(
                    labelText: _isCod
                        ? 'Tracking number (optional)'
                        : 'Tracking number',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Tracking link (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Escrow dispatch needs courier + tracking; COD may be
                    // hand-delivered, so they're optional there.
                    if (!_isCod &&
                        (courier.text.trim().isEmpty ||
                            tracking.text.trim().isEmpty)) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Courier and tracking number are required.',
                          ),
                        ),
                      );
                      return;
                    }
                    try {
                      await setOrderShipping(
                        orderId,
                        'shipped',
                        courierName: courier.text,
                        trackingNumber: tracking.text,
                        trackingUrl: url.text,
                      );
                    } catch (_) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Could not update. Please try again.'),
                        ),
                      );
                      return;
                    }
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Order dispatched.')),
                    );
                  },
                  icon: const Icon(Icons.local_shipping, size: 18),
                  label: const Text('Mark dispatched'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    courier.dispose();
    tracking.dispose();
    url.dispose();
  }
}
