part of '../main.dart';

// Seller shipping flow + buyer delivery confirmation for a platform-held
// (escrow) order. Rendered inside each order card while the payment is held by
// PakBazar. Money is never moved here — the seller only advances fulfillment
// (accept → process → ship → deliver) and the buyer confirms receipt; the
// payout stays server-authoritative (Cloud Functions).

/// The ordered fulfillment steps shown in the little progress strip.
const List<({String key, String label})> _shipSteps = [
  (key: 'accepted', label: 'Accepted'),
  (key: 'processing', label: 'Prep'),
  (key: 'shipped', label: 'Shipped'),
  (key: 'delivered', label: 'Delivered'),
  (key: 'buyer_confirmed', label: 'Confirmed'),
];

int _shipStepIndex(String orderStatus) => switch (orderStatus) {
  'accepted' => 0,
  'processing' => 1,
  'shipped' => 2,
  'delivered' => 3,
  'buyer_confirmed' || 'completed' => 4,
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
              const Icon(Icons.local_shipping, size: 14, color: Colors.grey),
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
              const Icon(Icons.event_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                shipDates,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
    final next = nextShippingStep(orderStatus);
    if (orderStatus == 'delivered') {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'Delivered — waiting for the buyer to confirm receipt so your '
          'payout can be released.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    if (next.isEmpty) return const SizedBox.shrink();
    final label = switch (next) {
      'accepted' => 'Accept order',
      'processing' => 'Mark preparing',
      'shipped' => 'Add shipping & mark shipped',
      'delivered' => 'Mark delivered',
      _ => 'Advance',
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (orderStatus == 'accepted')
              TextButton(
                onPressed: () => _advance(context, 'processing'),
                child: const Text('Mark preparing'),
              ),
            ElevatedButton.icon(
              onPressed: () {
                if (next == 'shipped') {
                  _showShipSheet(context);
                } else {
                  _advance(context, next);
                }
              },
              icon: Icon(
                next == 'shipped' ? Icons.local_shipping : Icons.arrow_forward,
                size: 16,
              ),
              label: Text(next == 'accepted' ? 'Accept order' : label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buyerActions(
    BuildContext context,
    String orderStatus,
    bool buyerConfirmed,
  ) {
    if (buyerConfirmed || orderStatus == 'buyer_confirmed') {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(Icons.verified, size: 16, color: kPakGreen),
            SizedBox(width: 4),
            Expanded(
              child: Text(
                'Delivery confirmed — the seller payout is pending platform '
                'verification.',
                style: TextStyle(
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
    // The buyer can confirm once the order has shipped/delivered, or on a
    // legacy held order that never entered the shipping flow.
    final canConfirm =
        orderStatus == 'shipped' ||
        orderStatus == 'delivered' ||
        orderStatus == 'accepted';
    if (!canConfirm) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'The seller is preparing your order. You can confirm delivery once '
          'it arrives.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ElevatedButton.icon(
          onPressed: () => _confirmDelivery(context),
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Confirm Delivery'),
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
        title: const Text('Confirm Delivery'),
        content: const Text(
          'Confirm only after you have received and checked your order. '
          'This lets PakBazar release the payment to the seller.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Confirm Delivery'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await confirmOrderDelivery(orderId);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Thank you — the seller payout is now under review.'),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add shipping details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enter the courier and tracking number so the buyer can '
                  'follow the delivery.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: courier,
                  decoration: const InputDecoration(
                    labelText: 'Courier (e.g. TCS, Leopards)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tracking,
                  decoration: const InputDecoration(
                    labelText: 'Tracking number',
                    border: OutlineInputBorder(),
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
                    if (courier.text.trim().isEmpty ||
                        tracking.text.trim().isEmpty) {
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
                      const SnackBar(content: Text('Order marked shipped.')),
                    );
                  },
                  icon: const Icon(Icons.local_shipping, size: 18),
                  label: const Text('Mark shipped'),
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
