part of '../main.dart';

// Checkout + order confirmation.
//
// A mandatory, complete delivery address and the free-delivery rule sit between
// the buyer tapping "Buy now" and an order being created. Single-listing model:
// one order = one listing = one seller (see placeListingOrder in commerce.dart).

/// Free-delivery progress banner for the checkout screen. Green once the
/// subtotal qualifies; otherwise shows how much more to add plus a progress bar
/// toward Rs [freeDeliveryThreshold].
class FreeDeliveryBanner extends StatelessWidget {
  final double subtotal;
  const FreeDeliveryBanner({super.key, required this.subtotal});

  @override
  Widget build(BuildContext context) {
    final qualifies = qualifiesForFreeDelivery(subtotal);
    final remaining = amountToFreeDelivery(subtotal);
    final progress = (subtotal / freeDeliveryThreshold).clamp(0.0, 1.0);
    final accent = qualifies ? kPakGreen : Colors.amber.shade800;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      // Opaque light surface so text is readable over the navy gradient.
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                qualifies
                    ? Icons.local_shipping
                    : Icons.local_shipping_outlined,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  qualifies
                      ? 'Congratulations! Your order qualifies for FREE delivery.'
                      : 'Shop ${formatPrice(remaining.toStringAsFixed(0))} more '
                            'to get FREE delivery.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: qualifies ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          if (!qualifies) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: accent.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Your order will be delivered free when you shop for '
            '${formatPrice(freeDeliveryThreshold.toStringAsFixed(0))} or more.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// A single "label: value" row for a price summary. Shows "FREE" in green when
/// [freeWhenZero] is set and [value] is 0.
class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final bool freeWhenZero;
  const _SummaryRow(
    this.label,
    this.value, {
    this.bold = false,
    this.freeWhenZero = false,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = freeWhenZero && value == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 16 : 14,
            ),
          ),
          Text(
            isFree ? 'FREE' : formatPrice(value.toStringAsFixed(0)),
            style: TextStyle(
              fontWeight: bold || isFree ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 16 : 14,
              color: isFree
                  ? kPakGreen
                  : (bold ? kPakGreen : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutScreen extends StatefulWidget {
  final Listing listing;
  const CheckoutScreen({super.key, required this.listing});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  DeliveryAddress? _address;
  bool _loadingAddress = true;
  bool _submitting = false;
  late String _paymentMethod; // 'escrow' | 'cod'
  final _notesController = TextEditingController();

  Listing get listing => widget.listing;
  double get subtotal => parsePrice(listing.price);
  double get deliveryFee => effectiveDeliveryFee(listing, subtotal);
  double get grandTotal => subtotal + deliveryFee;

  @override
  void initState() {
    super.initState();
    _paymentMethod = 'escrow';
    _loadAddress();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAddress() async {
    final a = await loadDefaultAddress();
    if (!mounted) return;
    setState(() {
      _address = a;
      _loadingAddress = false;
    });
  }

  Future<void> _changeAddress() async {
    final picked = await Navigator.push<DeliveryAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddressBookScreen(selectMode: true),
      ),
    );
    if (picked != null && mounted) setState(() => _address = picked);
  }

  bool get _canPlace =>
      !_submitting &&
      !_loadingAddress &&
      _address != null &&
      _address!.isComplete &&
      subtotal > 0 &&
      FirebaseAuth.instance.currentUser != null;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _placeOrder() async {
    final address = _address;
    if (address == null || !address.isComplete) {
      _snack('Please provide a complete delivery address first.');
      return;
    }
    // Guard against duplicate submissions from repeated taps.
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final orderId = await placeListingOrder(
        listing: listing,
        address: address,
        paymentMethod: _paymentMethod,
        notes: _notesController.text,
      );
      // A completed order is a meaningful engagement signal for the review
      // prompt (recorded only — the prompt itself appears later, on Home).
      recordMeaningfulAction();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderConfirmationScreen(
            orderId: orderId,
            listing: listing,
            address: address,
            itemSubtotal: subtotal,
            deliveryFee: deliveryFee,
            grandTotal: grandTotal,
            paymentMethod: _paymentMethod,
          ),
        ),
      );
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Could not place the order. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: _loadingAddress
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _itemCard(),
                const SizedBox(height: 12),
                FreeDeliveryBanner(subtotal: subtotal),
                const SizedBox(height: 12),
                _addressCard(),
                const SizedBox(height: 12),
                _paymentCard(),
                const SizedBox(height: 12),
                _notesCard(),
                const SizedBox(height: 12),
                _summaryCard(),
                const SizedBox(height: 24),
              ],
            ),
      bottomNavigationBar: _placeBar(),
    );
  }

  Widget _cardTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    ),
  );

  Widget _itemCard() {
    final img = listing.galleryImages.isEmpty
        ? ''
        : listing.galleryImages.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
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
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceLabel(listing),
                    style: const TextStyle(color: kPakGreen),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressCard() {
    final a = _address;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _cardTitle('Delivery address')),
                if (a != null)
                  TextButton.icon(
                    onPressed: _submitting ? null : _changeAddress,
                    icon: const Icon(Icons.edit_location_alt, size: 18),
                    label: const Text('Change'),
                  ),
              ],
            ),
            if (a == null)
              OutlinedButton.icon(
                onPressed: _submitting ? null : _changeAddress,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Add delivery address'),
              )
            else ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kPakGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      a.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: kPakGreen,
                      ),
                    ),
                  ),
                  if (a.isDefault) ...[
                    const SizedBox(width: 6),
                    Text(
                      'Default',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                a.fullName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(a.phone, style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(a.shortSummary),
              if (a.landmark.trim().isNotEmpty)
                Text(
                  'Landmark: ${a.landmark}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              if (a.postalCode.trim().isNotEmpty)
                Text(
                  'Postal code: ${a.postalCode}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Payment method'),
            RadioGroup<String>(
              groupValue: _paymentMethod,
              onChanged: (v) {
                if (_submitting || v == null) return;
                setState(() => _paymentMethod = v);
              },
              child: Column(
                children: [
                  const RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'escrow',
                    activeColor: kPakGreen,
                    title: Text('Pay online (escrow)'),
                    subtitle: Text(
                      'Held safely until you confirm you received the item.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (listing.codAvailable)
                    const RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'cod',
                      activeColor: kPakGreen,
                      title: Text('Cash on Delivery'),
                      subtitle: Text(
                        'Pay cash when the item is delivered.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Order notes (optional)'),
            TextField(
              controller: _notesController,
              enabled: !_submitting,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Anything the seller should know?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Order summary'),
            _SummaryRow('Item subtotal', subtotal),
            _SummaryRow('Delivery fee', deliveryFee, freeWhenZero: true),
            const Divider(height: 18),
            _SummaryRow('Total payable', grandTotal, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _placeBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_address == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Add a delivery address to place your order.',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canPlace ? _placeOrder : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Place Order · ${formatPrice(grandTotal.toStringAsFixed(0))}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after an order is successfully created.
class OrderConfirmationScreen extends StatelessWidget {
  final String orderId;
  final Listing listing;
  final DeliveryAddress address;
  final double itemSubtotal;
  final double deliveryFee;
  final double grandTotal;
  final String paymentMethod;

  const OrderConfirmationScreen({
    super.key,
    required this.orderId,
    required this.listing,
    required this.address,
    required this.itemSubtotal,
    required this.deliveryFee,
    required this.grandTotal,
    required this.paymentMethod,
  });

  String get _orderNo => orderId.length >= 6
      ? orderId.substring(0, 6).toUpperCase()
      : orderId.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final isCod = paymentMethod == 'cod';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order placed'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Icon(Icons.check_circle, color: AppColors.success, size: 64),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Order placed successfully!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.onNavy,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Order #$_orderNo',
              style: const TextStyle(color: AppColors.onNavyMuted),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment summary',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  _SummaryRow('Item subtotal', itemSubtotal),
                  _SummaryRow('Delivery fee', deliveryFee, freeWhenZero: true),
                  const Divider(height: 18),
                  _SummaryRow('Total', grandTotal, bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivering to',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    address.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    address.phone,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(address.shortSummary),
                  if (address.landmark.trim().isNotEmpty)
                    Text(
                      'Landmark: ${address.landmark}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPakGreen.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  isCod ? Icons.local_shipping : Icons.lock,
                  size: 18,
                  color: kPakGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isCod
                        ? 'Cash on Delivery — pay cash when the item is '
                              'delivered. Track it in Profile → My Orders.'
                        : 'Pay online — open Profile → My Orders to pay and hold '
                              'the amount safely in escrow.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Continue shopping'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersScreen()),
                    );
                  },
                  child: const Text('View my orders'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
