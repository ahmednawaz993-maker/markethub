import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// The receipt is the one screen a user is likely to forward to somebody else,
// print, or wave at a courier — so it gets checked on both of its surfaces:
// the numbers it derives from an order, and how the document actually looks.

/// A cart order: two lines, delivery, escrow, completed.
Map<String, dynamic> _cartOrder() => {
  'orderNumber': 'PB-1043',
  'sellerName': 'Meer Collections',
  'buyerName': 'Ahmed Nawaz',
  'buyerPhone': '03001234567',
  'deliveryAddress': {
    'houseOrBuilding': 'House 12',
    'streetAddress': 'Street 4',
    'area': 'G-10/2',
    'city': 'Islamabad',
  },
  'items': [
    {
      'title': 'DHANAK 2pc Premium Winter Embroidered Suit',
      'quantity': 2,
      'unitPrice': 2450,
    },
    {'title': 'Premium Ladies Watch | Gift Collection', 'quantity': 1, 'unitPrice': 1750},
  ],
  'itemSubtotal': 6650,
  'deliveryFee': 350,
  'discount': 0,
  'amount': 7000,
  'commission': 332.5,
  'sellerPayout': 6667.5,
  'paymentMethod': 'escrow',
  'status': 'released',
  'createdAt': Timestamp.fromDate(DateTime(2026, 9, 11)),
  'completedAt': Timestamp.fromDate(DateTime(2026, 9, 15)),
};

/// A Buy-now order: no items[], one implied line, cash on delivery.
Map<String, dynamic> _singleOrder() => {
  'orderNumber': 'PB-1044',
  'sellerName': 'Meer Collections',
  'buyerName': 'Ahmed Nawaz',
  'listingTitle': '2 piece lawn',
  'itemSubtotal': 1500,
  'deliveryFee': 0,
  'amount': 1500,
  'paymentMethod': 'cod',
  'status': 'cod_pending',
  'createdAt': Timestamp.fromDate(DateTime(2026, 9, 14)),
};

void main() {
  group('Invoice.fromOrder', () {
    test('reads a cart order line by line', () {
      final i = Invoice.fromOrder('abc123', _cartOrder());
      expect(i.number, 'PB-1043');
      expect(i.lines.length, 2);
      expect(i.lines.first.quantity, 2);
      expect(i.lines.first.lineTotal, 4900);
      expect(i.total, 7000);
      expect(i.deliveryFee, 350);
      expect(i.paid, isTrue, reason: 'released means the money moved');
      expect(i.issuedAt, DateTime(2026, 9, 15));
    });

    test('rebuilds one line for a Buy-now order', () {
      final i = Invoice.fromOrder('def456', _singleOrder());
      expect(i.lines.length, 1);
      expect(i.lines.single.title, '2 piece lawn');
      expect(i.lines.single.lineTotal, 1500);
      expect(i.paymentLabel, 'Cash on delivery');
    });

    test('an order still in escrow is not a paid receipt', () {
      final m = _cartOrder()..['status'] = 'in_escrow';
      expect(Invoice.fromOrder('abc123', m).paid, isFalse);
    });

    test('falls back to a number when the order has none', () {
      final m = _cartOrder()..remove('orderNumber');
      expect(Invoice.fromOrder('abcdef123', m).number, '#ABCDEF');
    });

    test('prints the address the order actually stores', () {
      final i = Invoice.fromOrder('abc123', _cartOrder());
      expect(i.address, 'House 12, Street 4, G-10/2, Islamabad');
    });

    test('labels the fulfilment state, not the money state', () {
      final m = _cartOrder()
        ..['status'] = 'in_escrow'
        ..['orderStatus'] = 'shipped';
      expect(Invoice.fromOrder('abc123', m).stampLabel, 'Dispatched');
    });

    test('a refunded order is not stamped paid', () {
      final m = _cartOrder()
        ..['status'] = 'refunded'
        ..['refundAmount'] = 7000;
      final i = Invoice.fromOrder('abc123', m);
      expect(i.paid, isFalse);
      expect(i.stampLabel, 'Refunded');
      expect(i.settlementNote, contains('refunded'));
    });

    test('a partial refund is shown', () {
      final m = _cartOrder()
        ..['status'] = 'in_escrow'
        ..['refundAmount'] = 500;
      expect(Invoice.fromOrder('abc123', m).refundAmount, 500);
    });

    test('the totals it prints are the order\'s, not a recomputation', () {
      // A receipt must not "fix" an order that was charged at a different
      // rate; whatever was taken is what it says.
      final m = _cartOrder()..['amount'] = 6800;
      expect(Invoice.fromOrder('abc123', m).total, 6800);
    });
  });

  group('the document', () {
    testWidgets('renders for a buyer', (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: InvoiceDocument(
                invoice: Invoice.fromOrder('abc123', _cartOrder()),
                audience: InvoiceAudience.buyer,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PB-1043'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      // The buyer is not shown what the platform took.
      expect(find.text('Platform commission'), findsNothing);
      await expectLater(
        find.byType(InvoiceDocument),
        matchesGoldenFile('goldens/receipt_buyer.png'),
      );
    });

    testWidgets('adds commission and payout for staff', (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: InvoiceDocument(
                invoice: Invoice.fromOrder('abc123', _cartOrder()),
                audience: InvoiceAudience.admin,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Platform commission'), findsOneWidget);
      expect(find.text('Seller payout'), findsOneWidget);
    });
  });

  group('the PDF', () {
    test('renders an A4 page and writes it for inspection', () async {
      final bytes = await buildInvoicePdf(
        Invoice.fromOrder('abc123', _cartOrder()),
        InvoiceAudience.buyer,
      );
      expect(bytes.length, greaterThan(1000));
      expect(
        String.fromCharCodes(bytes.take(5)),
        '%PDF-',
        reason: 'it should actually be a PDF',
      );
      // Dropped where a human (or the next session) can open it; build/ is
      // ignored, so this never lands in the repo.
      final out = File('build/receipt_preview.pdf');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes);
    });

    test('the staff copy carries the commission lines', () async {
      final buyer = await buildInvoicePdf(
        Invoice.fromOrder('abc123', _cartOrder()),
        InvoiceAudience.buyer,
      );
      final admin = await buildInvoicePdf(
        Invoice.fromOrder('abc123', _cartOrder()),
        InvoiceAudience.admin,
      );
      expect(admin.length, greaterThan(buyer.length));
    });
  });
}
