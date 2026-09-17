part of '../main.dart';

// ---------------------------------------------------------------------------
// The receipt.
//
// An order document is already the frozen record of a sale: it stores the
// titles, unit prices, quantities, the delivery fee that applied on the day,
// the commission, the address it went to and how it was paid. None of that
// moves when a listing is later edited. So a receipt needs no second copy and
// no new collection — it is a VIEW over the order, which is also why it cannot
// drift out of step with what the buyer was actually charged.
//
// Three audiences read the same document and should not see the same thing:
// a buyer has no business seeing the platform's commission, and a seller wants
// to see their payout. Hence [InvoiceAudience].
// ---------------------------------------------------------------------------

enum InvoiceAudience { buyer, seller, admin }

/// One line of the receipt.
class InvoiceLine {
  final String title;
  final int quantity;
  final double unitPrice;

  const InvoiceLine({
    required this.title,
    required this.quantity,
    required this.unitPrice,
  });

  double get lineTotal => unitPrice * quantity;
}

/// A receipt, built from an order document.
class Invoice {
  final String orderId;
  final String number;
  final DateTime issuedAt;
  final DateTime orderedAt;
  final String sellerName;
  final String buyerName;
  final String buyerPhone;
  final String address;
  final List<InvoiceLine> lines;
  final double itemSubtotal;
  final double deliveryFee;
  final double discount;
  final double total;
  final double commission;
  final double sellerPayout;
  final String paymentMethod; // 'cod' | 'escrow'
  final String statusLabel;
  final bool paid;

  /// What has gone back to the buyer so far. A partial refund leaves the order
  /// held, so this can be non-zero on an order that is not [fullyRefunded].
  final double refundAmount;
  final bool fullyRefunded;

  const Invoice({
    required this.orderId,
    required this.number,
    required this.issuedAt,
    required this.orderedAt,
    required this.sellerName,
    required this.buyerName,
    required this.buyerPhone,
    required this.address,
    required this.lines,
    required this.itemSubtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.commission,
    required this.sellerPayout,
    required this.paymentMethod,
    required this.statusLabel,
    required this.paid,
    this.refundAmount = 0,
    this.fullyRefunded = false,
  });

  /// Builds a receipt from an `orders/{id}` document.
  ///
  /// Handles both shapes the app writes: a cart order carries `items[]`, and a
  /// Buy-now order carries a single `listingTitle` with the amounts at the top
  /// level. The single-item path reconstructs one line from `itemSubtotal`
  /// rather than the listing's current price — the point of a receipt is what
  /// was charged, not what the ad says today.
  factory Invoice.fromOrder(String id, Map<String, dynamic> m) {
    double num$(String key) => (m[key] as num?)?.toDouble() ?? 0;
    DateTime? ts(String key) => (m[key] as Timestamp?)?.toDate();

    final rawItems = (m['items'] as List?) ?? const [];
    final lines = <InvoiceLine>[];
    for (final it in rawItems) {
      if (it is! Map) continue;
      final qty = (it['quantity'] as num?)?.toInt() ?? 1;
      lines.add(
        InvoiceLine(
          title: it['title']?.toString() ?? 'Item',
          quantity: qty < 1 ? 1 : qty,
          unitPrice: (it['unitPrice'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    final subtotal = num$('itemSubtotal');
    if (lines.isEmpty) {
      lines.add(
        InvoiceLine(
          title: m['listingTitle']?.toString() ?? 'Item',
          quantity: 1,
          unitPrice: subtotal,
        ),
      );
    }

    final address = (m['deliveryAddress'] as Map?)?.cast<String, dynamic>();
    final addressLine = [
      address?['houseOrBuilding'],
      address?['streetAddress'],
      address?['area'],
      address?['city'],
      address?['province'],
    ].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).join(', ');

    final status = m['status']?.toString() ?? '';
    // "Paid" means the money has actually moved: cash collected on a COD
    // delivery, or escrow released to the seller. An order sitting in escrow is
    // not a completed sale and its receipt should not claim to be one.
    // A refunded order is not one: the money went back, not to the seller.
    final paid = status == 'completed' || status == 'released';
    final fullyRefunded = status == 'refunded';

    return Invoice(
      orderId: id,
      number: m['orderNumber']?.toString().trim().isNotEmpty == true
          ? m['orderNumber'].toString().trim()
          // Not PB-: that would pass for a real order number support can find.
          : '#${id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()}',
      issuedAt:
          ts('completedAt') ??
          ts('releasedAt') ??
          ts('buyerConfirmedAt') ??
          ts('createdAt') ??
          DateTime.now(),
      orderedAt: ts('createdAt') ?? DateTime.now(),
      sellerName: m['sellerName']?.toString() ?? 'Seller',
      buyerName: m['buyerName']?.toString() ?? '',
      buyerPhone: m['buyerPhone']?.toString() ?? '',
      address: addressLine,
      lines: lines,
      itemSubtotal: subtotal,
      deliveryFee: num$('deliveryFee'),
      discount: num$('discount'),
      total: num$('amount'),
      commission: num$('commission'),
      sellerPayout: num$('sellerPayout'),
      paymentMethod: m['paymentMethod']?.toString() ?? '',
      // `status` is the money state (in_escrow, cod_pending…), which
      // orderStatusLabel does not know; derive the fulfilment state instead.
      statusLabel: fullyRefunded
          ? 'Refunded'
          : orderStatusLabel(orderStatusOf(m)),
      paid: paid,
      refundAmount: num$('refundAmount'),
      fullyRefunded: fullyRefunded,
    );
  }

  /// The label on the stamp.
  String get stampLabel => paid ? 'PAID' : statusLabel;

  /// The closing line, which has to match what actually happened to the money.
  String get settlementNote {
    if (fullyRefunded) {
      return 'This order was refunded to the buyer’s PakBazar wallet.';
    }
    if (paymentMethod == 'cod') {
      return paid
          ? 'Cash was collected on delivery. Returns and refunds are handled '
                'in the PakBazar app.'
          : 'Cash is paid on delivery. Returns and refunds are handled in the '
                'PakBazar app.';
    }
    return paid
        ? 'Payment was held by PakBazar until delivery was confirmed, then '
              'released to the seller.'
        : 'Payment is held by PakBazar until delivery is confirmed.';
  }

  String get paymentLabel =>
      paymentMethod == 'cod' ? 'Cash on delivery' : 'Paid through PakBazar';

  /// Plain text, for a share sheet that has no room for a file.
  String asText() {
    final b = StringBuffer()
      ..writeln('PakBazar receipt $number')
      ..writeln(formatInvoiceDate(issuedAt))
      ..writeln('')
      ..writeln('Sold by $sellerName');
    if (buyerName.isNotEmpty) b.writeln('To $buyerName');
    b.writeln('');
    for (final l in lines) {
      b.writeln(
        '${l.title} x${l.quantity}  ${formatPrice(l.lineTotal.toStringAsFixed(0))}',
      );
    }
    if (deliveryFee > 0) {
      b.writeln('Delivery  ${formatPrice(deliveryFee.toStringAsFixed(0))}');
    }
    b
      ..writeln('TOTAL  ${formatPrice(total.toStringAsFixed(0))}')
      ..writeln(paymentLabel);
    return b.toString();
  }
}

/// `15 Sep 2026` — the same everywhere the receipt is rendered.
String formatInvoiceDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

// ---------------------------------------------------------------------------
// The document
// ---------------------------------------------------------------------------

/// The receipt screen: the same document on screen and on paper.
///
/// It reads the order live rather than taking a snapshot argument, so a receipt
/// opened while an escrow order is still settling updates itself the moment the
/// money is released instead of showing "not paid yet" for ever.
class InvoiceScreen extends StatelessWidget {
  final String orderId;
  final InvoiceAudience audience;

  const InvoiceScreen({
    super.key,
    required this.orderId,
    this.audience = InvoiceAudience.buyer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const ErrorStateWidget(
              message: 'We could not load this receipt.',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return const EmptyStateWidget(
              icon: Icons.receipt_long,
              title: 'Receipt not found',
              subtitle: 'This order no longer exists.',
            );
          }
          final invoice = Invoice.fromOrder(orderId, data);
          // What gets shared as a picture is this exact card — see
          // InvoiceActions. Capturing the widget rather than rasterising the
          // A4 page means the image is receipt-shaped instead of a short
          // document adrift on a page of white.
          final captureKey = GlobalKey();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.section,
            ),
            children: [
              ContentColumn(
                maxWidth: 720,
                child: Column(
                  children: [
                    RepaintBoundary(
                      key: captureKey,
                      child: InvoiceDocument(
                        invoice: invoice,
                        audience: audience,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    InvoiceActions(
                      invoice: invoice,
                      audience: audience,
                      captureKey: captureKey,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The receipt itself — one card, so it reads as a document rather than as a
/// screen that happens to list numbers.
class InvoiceDocument extends StatelessWidget {
  final Invoice invoice;
  final InvoiceAudience audience;

  const InvoiceDocument({
    super.key,
    required this.invoice,
    required this.audience,
  });

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/pakbazar_mark_light.png',
                height: 34,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    Icon(Icons.storefront, size: 30, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'PakBazar',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('RECEIPT', style: AppType.label),
                  Text(i.number, style: AppType.pageTitle),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              InvoiceStatusStamp(
                paid: i.paid,
                label: i.stampLabel,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${formatInvoiceDate(i.issuedAt)} · ${i.paymentLabel}',
                  style: AppType.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: AppColors.borderSoft),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InvoiceParty(
                  title: 'Sold by',
                  lines: [i.sellerName, 'PakBazar seller'],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: InvoiceParty(
                  title: 'Delivered to',
                  lines: [
                    if (i.buyerName.isNotEmpty) i.buyerName,
                    if (i.buyerPhone.isNotEmpty) i.buyerPhone,
                    if (i.address.isNotEmpty) i.address,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          InvoiceLineTable(invoice: i, audience: audience),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Ordered ${formatInvoiceDate(i.orderedAt)} · Order ${i.number}',
            style: AppType.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(i.settlementNote, style: AppType.caption),
        ],
      ),
    );
  }
}

class InvoiceStatusStamp extends StatelessWidget {
  final bool paid;
  final String label;

  const InvoiceStatusStamp({
    super.key,
    required this.paid,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colour = paid ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: AppRadius.rSm,
        border: Border.all(color: colour.withValues(alpha: 0.4)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: colour,
        ),
      ),
    );
  }
}

class InvoiceParty extends StatelessWidget {
  final String title;
  final List<String> lines;

  const InvoiceParty({super.key, required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppType.label),
        const SizedBox(height: 2),
        for (final l in lines) Text(l, style: AppType.secondary),
      ],
    );
  }
}

class InvoiceLineTable extends StatelessWidget {
  final Invoice invoice;
  final InvoiceAudience audience;

  const InvoiceLineTable({
    super.key,
    required this.invoice,
    required this.audience,
  });

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('Item', style: AppType.label)),
            SizedBox(width: 40, child: Text('Qty', style: AppType.label)),
            SizedBox(
              width: 96,
              child: Text(
                'Amount',
                textAlign: TextAlign.end,
                style: AppType.label,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Divider(height: 1, color: AppColors.borderSoft),
        for (final l in i.lines) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(l.title, style: AppType.body)),
                SizedBox(
                  width: 40,
                  child: Text('${l.quantity}', style: AppType.body),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    formatPrice(l.lineTotal.toStringAsFixed(0)),
                    textAlign: TextAlign.end,
                    style: AppType.body,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.borderSoft),
        ],
        const SizedBox(height: AppSpacing.sm),
        InvoiceTotalRow(label: 'Items', value: i.itemSubtotal),
        if (i.discount > 0)
          InvoiceTotalRow(label: 'Discount', value: -i.discount),
        InvoiceTotalRow(
          label: i.deliveryFee > 0 ? 'Delivery' : 'Delivery (free)',
          value: i.deliveryFee,
        ),
        const SizedBox(height: AppSpacing.xs),
        InvoiceTotalRow(label: 'Total', value: i.total, emphasise: true),
        if (i.refundAmount > 0) ...[
          InvoiceTotalRow(label: 'Refunded', value: -i.refundAmount),
          InvoiceTotalRow(
            label: 'Net paid',
            value: (i.total - i.refundAmount).clamp(0, double.infinity).toDouble(),
          ),
        ],
        if (audience != InvoiceAudience.buyer) ...[
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppColors.borderSoft),
          const SizedBox(height: AppSpacing.sm),
          InvoiceTotalRow(label: 'Platform commission', value: -i.commission),
          InvoiceTotalRow(label: 'Seller payout', value: i.sellerPayout),
        ],
      ],
    );
  }
}

class InvoiceTotalRow extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasise;

  const InvoiceTotalRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasise ? AppType.cardTitle : AppType.secondary,
            ),
          ),
          Text(
            '${value < 0 ? '− ' : ''}'
            '${formatPrice(value.abs().toStringAsFixed(0))}',
            style: emphasise
                ? AppType.price
                : AppType.secondary.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
