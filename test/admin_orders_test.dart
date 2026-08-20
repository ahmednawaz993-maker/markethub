import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// The admin Orders desk triages on these three predicates: which orders are
// stuck waiting on a seller, how old they are, and whether the money has moved
// far enough that cancelling or deleting needs the refund flow instead.
//
// Getting the first one wrong is the expensive direction. A false negative
// hides a paid buyer whose order nobody is touching — the exact failure the
// panel exists to catch — and a false positive sends staff chasing a seller who
// has done nothing wrong, which burns the signal.

Map<String, dynamic> order({
  String? orderStatus,
  String status = 'in_escrow',
  Duration age = Duration.zero,
}) => {
  'orderStatus': ?orderStatus,
  'status': status,
  'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
};

void main() {
  group('orderAwaitingSellerTooLong', () {
    test('a paid order the seller has just received is not overdue', () {
      expect(
        orderAwaitingSellerTooLong(
          order(orderStatus: 'pending', age: const Duration(hours: 1)),
        ),
        isFalse,
      );
    });

    test('a paid order still unaccepted past the SLA is overdue', () {
      expect(
        orderAwaitingSellerTooLong(
          order(
            orderStatus: 'pending',
            age: const Duration(hours: kSellerAcceptSlaHours + 1),
          ),
        ),
        isTrue,
      );
    });

    test('the SLA boundary itself counts as overdue', () {
      expect(
        orderAwaitingSellerTooLong(
          order(
            orderStatus: 'pending',
            age: const Duration(hours: kSellerAcceptSlaHours, minutes: 1),
          ),
        ),
        isTrue,
      );
    });

    // The seller cannot be blamed for not accepting an order the buyer has not
    // paid for. Flagging these would bury the real ones.
    test('an unpaid order is never the seller\'s fault', () {
      for (final money in ['pending_payment', 'payment_review']) {
        expect(
          orderAwaitingSellerTooLong(
            order(
              orderStatus: 'pending',
              status: money,
              age: const Duration(days: 5),
            ),
          ),
          isFalse,
          reason: '$money is waiting on the buyer, not the seller',
        );
      }
    });

    test('a COD order is live immediately, so it can go overdue', () {
      expect(
        orderAwaitingSellerTooLong(
          order(
            orderStatus: 'pending',
            status: 'cod_pending',
            age: const Duration(days: 2),
          ),
        ),
        isTrue,
      );
    });

    test('an order the seller has acted on is never overdue', () {
      for (final s in ['accepted', 'processing', 'shipped', 'delivered']) {
        expect(
          orderAwaitingSellerTooLong(
            order(orderStatus: s, age: const Duration(days: 30)),
          ),
          isFalse,
          reason: '$s means the seller responded',
        );
      }
    });

    test('a closed order is never chased', () {
      for (final s in ['cancelled', 'rejected', 'completed', 'returned']) {
        expect(
          orderAwaitingSellerTooLong(
            order(orderStatus: s, age: const Duration(days: 30)),
          ),
          isFalse,
        );
      }
    });

    // Fail quiet rather than flagging every ancient record at once.
    test('an order with no createdAt is not flagged', () {
      expect(
        orderAwaitingSellerTooLong({
          'orderStatus': 'pending',
          'status': 'in_escrow',
        }),
        isFalse,
      );
    });

    // Documents the legacy derivation rather than endorsing it: before
    // notifyOnNewOrder started backfilling orderStatus, a COD order carried no
    // explicit one and orderStatusOf reads 'cod_pending' as 'processing'. Such
    // a doc cannot be flagged. Every order created since the backfill has an
    // explicit orderStatus, so this only affects pre-backfill records.
    test('a legacy doc with no explicit orderStatus is not flagged', () {
      expect(
        orderAwaitingSellerTooLong(
          order(status: 'cod_pending', age: const Duration(days: 9)),
        ),
        isFalse,
      );
    });
  });

  group('orderAgeHours', () {
    test('reports elapsed hours', () {
      final h = orderAgeHours(order(age: const Duration(hours: 30)));
      expect(h, isNotNull);
      expect(h!, closeTo(30, 0.1));
    });

    test('is null without a createdAt', () {
      expect(orderAgeHours(const {}), isNull);
    });
  });

  group('orderMoneyIsCommitted', () {
    // The gate on cancel/delete. Wrong in the permissive direction, an admin
    // marks an order cancelled while the buyer's money stays in escrow.
    test('held or paid-out money is committed', () {
      for (final s in ['in_escrow', 'released', 'completed']) {
        expect(orderMoneyIsCommitted({'status': s}), isTrue, reason: s);
      }
    });

    test('unpaid and COD orders are not committed', () {
      for (final s in ['pending_payment', 'payment_review', 'cod_pending']) {
        expect(orderMoneyIsCommitted({'status': s}), isFalse, reason: s);
      }
    });

    test('an order with no status is treated as not committed', () {
      expect(orderMoneyIsCommitted(const {}), isFalse);
    });
  });

  // The order screen is dense — a fixed-width label column, a five-step
  // timeline laid out in a single Row with text under each dot, and long
  // real-world content (Pakistani addresses run long, ad titles longer). All of
  // that has to survive a 320px phone, which is where staff will actually open
  // it.
  group('AdminOrderView layout', () {
    Map<String, dynamic> fatOrder(String orderStatus, String money) => {
      'orderNumber': 'PB-104233',
      'listingTitle':
          'Toyota Corolla Altis Grande X 1.8 CVT-i Black Interior 2022 '
          'Model Single Owner Total Genuine Non-Accidental',
      'buyerName': 'Muhammad Abdul Rehman Siddiqui',
      'sellerName': 'Al-Madina Motors & General Traders (Pvt) Limited',
      'buyerId': 'buyer-1',
      'sellerId': 'seller-1',
      'listingId': 'listing-1',
      'deliveryAddress':
          'House 214-B, Street 9, Near Chandni Chowk Roundabout, Satellite '
          'Town Block C Extension, Rawalpindi Cantonment, Punjab 46000',
      'buyerPhone': '03001234567',
      'courierName': 'Leopards Courier Services (Pvt) Ltd',
      'trackingNumber': 'LCS-99887766554433',
      'amount': 12500000,
      'commission': 625000,
      'sellerPayout': 11875000,
      'quantity': 3,
      'paymentMethod': 'cod',
      'orderStatus': orderStatus,
      'status': money,
      'createdAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 4)),
      ),
      'updatedAt': Timestamp.now(),
      'adminActions': [
        {
          'action': 'advanced_to_accepted',
          'note': 'Seller unreachable on WhatsApp and phone for two days.',
          'by': 'staff@pakbazar24.com',
          'at': Timestamp.now(),
        },
      ],
    };

    for (final width in [320.0, 360.0, 411.0, 768.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final (label, status, money) in const [
          // Overdue pending draws the extra warning banner — the tallest case.
          ('overdue pending', 'pending', 'in_escrow'),
          ('shipped', 'shipped', 'in_escrow'),
          ('completed', 'completed', 'released'),
          ('cancelled', 'cancelled', 'cod_pending'),
        ]) {
          testWidgets(
            'no overflow — $label at ${width.toInt()}px, text x$scale',
            (tester) async {
              tester.view.physicalSize = Size(width, 900);
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.reset);

              await tester.pumpWidget(
                MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: MaterialApp(
                    home: AdminOrderView(
                      orderId: 'order-1',
                      data: fatOrder(status, money),
                    ),
                  ),
                ),
              );
              await tester.pump();

              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    testWidgets('an order with committed money refuses to offer cancel', (
      tester,
    ) async {
      // Tall on purpose: the actions card sits well down a lazily-built
      // ListView and is never constructed at phone height.
      tester.view.physicalSize = const Size(411, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: AdminOrderView(
            orderId: 'order-1',
            data: fatOrder('accepted', 'in_escrow'),
          ),
        ),
      );
      await tester.pump();

      // The label itself changes, and the button is disabled — an admin must
      // not be able to mark an escrowed order cancelled from here.
      final cancel = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Cancel — use refund flow'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(cancel.onPressed, isNull);
    });

    testWidgets('an unpaid order does offer cancel', (tester) async {
      tester.view.physicalSize = const Size(411, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: AdminOrderView(
            orderId: 'order-1',
            data: fatOrder('pending', 'cod_pending'),
          ),
        ),
      );
      await tester.pump();

      final cancel = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Cancel order'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(cancel.onPressed, isNotNull);
    });
  });

  group('kAdminUneditableOrderFields', () {
    // The admin editor writes a fixed field list; this pins the money fields it
    // must never grow to include.
    test('covers every money field the escrow backend owns', () {
      expect(
        kAdminUneditableOrderFields,
        containsAll([
          'amount',
          'commission',
          'sellerPayout',
          'paymentStatus',
          'platformCommissionAmount',
          'refundAmount',
        ]),
      );
    });
  });
}
