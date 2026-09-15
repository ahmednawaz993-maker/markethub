part of '../main.dart';

// The receipt as PAPER.
//
// Kept in its own file because it is not the app: an A4 page is measured in
// points, its type is sized for print rather than for a phone held at arm's
// length, and it has no theme to follow — a receipt is black on white whatever
// the reader's Appearance setting says. That is also why the design-system
// guards in design_tokens_test skip this file: every value here is a print
// value, and snapping them to AppSpacing would be cargo cult.

// ---------------------------------------------------------------------------
// The paper version
// ---------------------------------------------------------------------------

/// Share and print, side by side under the receipt.
///
/// `printing` does the platform-appropriate thing from one call: a share sheet
/// on Android, a download on the website, and the system print dialog on both.
class InvoiceActions extends StatefulWidget {
  final Invoice invoice;
  final InvoiceAudience audience;

  /// The receipt card on screen. When present the shared picture is a capture
  /// of it; without it the A4 page is rasterised instead.
  final GlobalKey? captureKey;

  const InvoiceActions({
    super.key,
    required this.invoice,
    required this.audience,
    this.captureKey,
  });

  @override
  State<InvoiceActions> createState() => _InvoiceActionsState();
}

class _InvoiceActionsState extends State<InvoiceActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (_) {
      // Usually a browser with no Web Share support rather than a broken
      // document, so point at the way out instead of just apologising.
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Sharing is not available here — use Print / save to keep a copy.',
          ),
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The receipt as a PNG of its own first page.
  ///
  /// Rasterised from the very PDF that would otherwise be attached, so there is
  /// one document and not two that can drift. An image matters because it is
  /// what a chat app can SHOW: WhatsApp renders a picture in the thread and
  /// files a PDF away as an attachment nobody opens, and a receipt is meant to
  /// be glanced at.
  Future<Uint8List> _receiptImage(Invoice i) async {
    // Preferred: a picture of the card the user is looking at, which is
    // receipt-shaped. Rasterising the PDF instead would attach an A4 page with
    // two thirds of it empty — fine to print, poor to send to somebody.
    final key = widget.captureKey;
    if (key != null) {
      final object = key.currentContext?.findRenderObject();
      if (object is RenderRepaintBoundary) {
        final image = await object.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) return data.buffer.asUint8List();
      }
    }
    // Fallback — a platform where capture is unavailable still gets a picture.
    final pdfBytes = await buildInvoicePdf(i, widget.audience);
    final page = await Printing.raster(pdfBytes, dpi: 140).first;
    return page.toPng();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invoice;
    final caption =
        'PakBazar receipt ${i.number} · '
        '${formatPrice(i.total.toStringAsFixed(0))}';

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 190,
          child: PrimaryActionButton(
            label: 'Share',
            icon: Icons.ios_share,
            busy: _busy,
            onPressed: () => _run(() async {
              final png = await _receiptImage(i);
              await SharePlus.instance.share(
                ShareParams(
                  text: caption,
                  files: [
                    XFile.fromData(
                      png,
                      mimeType: 'image/png',
                      name: 'PakBazar-${i.number}.png',
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        SizedBox(
          width: 190,
          child: PrimaryActionButton(
            label: 'Share PDF',
            icon: Icons.picture_as_pdf_outlined,
            outlined: true,
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final bytes = await buildInvoicePdf(i, widget.audience);
                    await Printing.sharePdf(
                      bytes: bytes,
                      filename: 'PakBazar-${i.number}.pdf',
                    );
                  }),
          ),
        ),
        SizedBox(
          width: 190,
          child: PrimaryActionButton(
            label: 'Print / save',
            icon: Icons.print_outlined,
            outlined: true,
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await Printing.layoutPdf(
                      name: 'PakBazar-${i.number}',
                      onLayout: (format) => buildInvoicePdf(i, widget.audience),
                    );
                  }),
          ),
        ),
        SizedBox(
          width: 190,
          child: PrimaryActionButton(
            label: 'Copy details',
            icon: Icons.copy_all_outlined,
            outlined: true,
            onPressed: _busy
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: i.asText()));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Receipt copied.')),
                    );
                  },
          ),
        ),
      ],
    );
  }
}

/// Builds the A4 receipt.
///
/// Deliberately plain typography rather than the app's: this document gets
/// printed, forwarded and filed, so it uses the PDF core fonts and leans on
/// rules and spacing for structure. Colour is only the brand navy and the
/// paid/unpaid stamp, both of which survive a black-and-white printer.
Future<Uint8List> buildInvoicePdf(
  Invoice i,
  InvoiceAudience audience,
) async {
  final doc = pw.Document(title: 'PakBazar receipt ${i.number}');
  const navy = PdfColor.fromInt(0xFF173A6B);
  const ink = PdfColor.fromInt(0xFF17223B);
  const muted = PdfColor.fromInt(0xFF6B7280);
  const hairline = PdfColor.fromInt(0xFFDDE2EA);
  final stamp = i.paid
      ? const PdfColor.fromInt(0xFF1E7E45)
      : const PdfColor.fromInt(0xFFB26A00);

  pw.Widget totalRow(String label, double value, {bool bold = false}) {
    // formatPrice, so the paper and the screen agree down to the comma.
    final text =
        '${value < 0 ? '- ' : ''}'
        '${formatPrice(value.abs().toStringAsFixed(0))}';
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: bold ? 12 : 10,
                color: bold ? ink : muted,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: bold ? 14 : 10,
              color: ink,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'PakBazar',
                    style: pw.TextStyle(
                      fontSize: 22,
                      color: navy,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Pakistan ka apna online bazaar',
                    style: const pw.TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'RECEIPT',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: muted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  pw.Text(
                    i.number,
                    style: pw.TextStyle(
                      fontSize: 18,
                      color: ink,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: stamp, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      (i.paid ? 'PAID' : i.statusLabel).toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: stamp,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '${formatInvoiceDate(i.issuedAt)}  |  ${i.paymentLabel}',
            style: const pw.TextStyle(fontSize: 10, color: muted),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: hairline, height: 1),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'SOLD BY',
                      style: const pw.TextStyle(fontSize: 8, color: muted),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      i.sellerName,
                      style: const pw.TextStyle(fontSize: 11, color: ink),
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'DELIVERED TO',
                      style: const pw.TextStyle(fontSize: 8, color: muted),
                    ),
                    pw.SizedBox(height: 2),
                    if (i.buyerName.isNotEmpty)
                      pw.Text(
                        i.buyerName,
                        style: const pw.TextStyle(fontSize: 11, color: ink),
                      ),
                    if (i.buyerPhone.isNotEmpty)
                      pw.Text(
                        i.buyerPhone,
                        style: const pw.TextStyle(fontSize: 10, color: muted),
                      ),
                    if (i.address.isNotEmpty)
                      pw.Text(
                        i.address,
                        style: const pw.TextStyle(fontSize: 10, color: muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(40),
              2: pw.FixedColumnWidth(90),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: hairline)),
                ),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(
                      'ITEM',
                      style: const pw.TextStyle(fontSize: 8, color: muted),
                    ),
                  ),
                  pw.Text(
                    'QTY',
                    style: const pw.TextStyle(fontSize: 8, color: muted),
                  ),
                  pw.Text(
                    'AMOUNT',
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontSize: 8, color: muted),
                  ),
                ],
              ),
              for (final l in i.lines)
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: hairline)),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 7),
                      child: pw.Text(
                        l.title,
                        style: const pw.TextStyle(fontSize: 10, color: ink),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 7),
                      child: pw.Text(
                        '${l.quantity}',
                        style: const pw.TextStyle(fontSize: 10, color: ink),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 7),
                      child: pw.Text(
                        formatPrice(l.lineTotal.toStringAsFixed(0)),
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 10, color: ink),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 240,
              child: pw.Column(
                children: [
                  totalRow('Items', i.itemSubtotal),
                  if (i.discount > 0) totalRow('Discount', -i.discount),
                  totalRow(
                    i.deliveryFee > 0 ? 'Delivery' : 'Delivery (free)',
                    i.deliveryFee,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(color: hairline, height: 1),
                  pw.SizedBox(height: 4),
                  totalRow('TOTAL', i.total, bold: true),
                  if (audience != InvoiceAudience.buyer) ...[
                    pw.SizedBox(height: 8),
                    totalRow('Platform commission', -i.commission),
                    totalRow('Seller payout', i.sellerPayout),
                  ],
                ],
              ),
            ),
          ),
          pw.Spacer(),
          pw.Divider(color: hairline, height: 1),
          pw.SizedBox(height: 8),
          pw.Text(
            i.paymentMethod == 'cod'
                ? 'Cash was collected on delivery. Returns and refunds are '
                      'handled in the PakBazar app.'
                : 'Payment was held by PakBazar until delivery was confirmed, '
                      'then released to the seller.',
            style: const pw.TextStyle(fontSize: 9, color: muted),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Ordered ${formatInvoiceDate(i.orderedAt)}  |  Order ${i.number}  |'
            '  pakbazar24.com',
            style: const pw.TextStyle(fontSize: 9, color: muted),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}
