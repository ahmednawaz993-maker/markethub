// Unit tests for PakBazar pure helpers.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  test('formatPrice groups digits with commas', () {
    expect(formatPrice('4250000'), 'Rs 4,250,000');
    expect(formatPrice('500'), 'Rs 500');
  });

  test('formatPrice handles empty input gracefully', () {
    expect(formatPrice(''), 'Rs');
  });

  group('Pakistani mobile validation', () {
    test('accepts common formats', () {
      expect(isValidPakMobile('03001234567'), isTrue);
      expect(isValidPakMobile('+923001234567'), isTrue);
      expect(isValidPakMobile('0300 1234567'), isTrue);
      expect(isValidPakMobile('00923001234567'), isTrue);
    });

    test('rejects invalid numbers', () {
      expect(isValidPakMobile(''), isFalse);
      expect(isValidPakMobile('0300123456'), isFalse); // too short
      expect(isValidPakMobile('042123456789'), isFalse); // landline-ish
      expect(isValidPakMobile('12345'), isFalse);
    });

    test('normalizes to a single E.164 format', () {
      expect(normalizePakMobile('03001234567'), '+923001234567');
      expect(normalizePakMobile('0300 1234567'), '+923001234567');
      expect(normalizePakMobile('bad'), '');
    });
  });

  group('Free-delivery rule (threshold = Rs 3,000)', () {
    test('threshold boundary', () {
      expect(qualifiesForFreeDelivery(2999), isFalse);
      expect(qualifiesForFreeDelivery(3000), isTrue);
      expect(qualifiesForFreeDelivery(3001), isTrue);
    });

    test('effective delivery fee waives the seller fee at/above threshold', () {
      final l = Listing(
        id: '1',
        title: 'x',
        price: '5000',
        location: '',
        imageUrl: '',
        category: 'x',
        deliveryAvailable: true,
        deliveryFee: '250',
      );
      expect(effectiveDeliveryFee(l, 2999), 250);
      expect(effectiveDeliveryFee(l, 3000), 0);
      expect(effectiveDeliveryFee(l, 5000), 0);
    });

    test('amountToFreeDelivery counts down then clamps at zero', () {
      expect(amountToFreeDelivery(2000), 1000);
      expect(amountToFreeDelivery(3000), 0);
      expect(amountToFreeDelivery(4000), 0);
    });
  });

  group('DeliveryAddress completeness', () {
    DeliveryAddress base() => DeliveryAddress(
      fullName: 'Ali Khan',
      phone: '03001234567',
      province: 'Punjab',
      city: 'Lahore',
      area: 'Model Town',
      streetAddress: 'Street 5',
      houseOrBuilding: 'House 12',
    );

    test('complete when all required fields are present', () {
      expect(base().isComplete, isTrue);
    });

    test('incomplete when a required field is missing', () {
      final a = base()..city = '';
      expect(a.isComplete, isFalse);
    });

    test('incomplete when phone is invalid', () {
      final a = base()..phone = '12345';
      expect(a.isComplete, isFalse);
    });
  });

  group('Seller-controlled inventory status', () {
    test('migrates legacy isSold when status absent/invalid', () {
      expect(listingStatusFrom(null, false), 'in_stock');
      expect(listingStatusFrom(null, true), 'sold');
      expect(listingStatusFrom('', true), 'sold');
      expect(listingStatusFrom('garbage', true), 'sold');
      expect(listingStatusFrom('garbage', false), 'in_stock');
    });

    test('honours an explicit valid status over the legacy bool', () {
      expect(listingStatusFrom('in_stock', true), 'in_stock');
      expect(listingStatusFrom('out_of_stock', false), 'out_of_stock');
      expect(listingStatusFrom('inactive', true), 'inactive');
      expect(listingStatusFrom('sold', false), 'sold');
    });

    Listing withStatus(String s) => Listing(
      id: '1',
      title: 'x',
      price: '100',
      location: '',
      imageUrl: '',
      category: 'x',
      status: s,
    );

    test('only in_stock is purchasable', () {
      expect(withStatus('in_stock').isAvailableForSale, isTrue);
      expect(withStatus('out_of_stock').isAvailableForSale, isFalse);
      expect(withStatus('sold').isAvailableForSale, isFalse);
      expect(withStatus('inactive').isAvailableForSale, isFalse);
    });

    test('only inactive is hidden from public feeds', () {
      expect(withStatus('in_stock').isPubliclyVisible, isTrue);
      expect(withStatus('sold').isPubliclyVisible, isTrue);
      expect(withStatus('out_of_stock').isPubliclyVisible, isTrue);
      expect(withStatus('inactive').isPubliclyVisible, isFalse);
    });

    test('status labels are buyer-facing', () {
      expect(withStatus('in_stock').statusLabel, '');
      expect(withStatus('sold').statusLabel, 'Sold');
      expect(withStatus('out_of_stock').statusLabel, 'Out of stock');
      expect(withStatus('inactive').statusLabel, 'Inactive');
    });
  });

  group('Platform-held payment: separate order & payment status', () {
    test('explicit orderStatus wins over legacy status', () {
      expect(
        orderStatusOf({'orderStatus': 'shipped', 'status': 'in_escrow'}),
        'shipped',
      );
    });

    test('legacy status maps to an order-progress value', () {
      expect(orderStatusOf({'status': 'pending_payment'}), 'pending');
      expect(orderStatusOf({'status': 'cod_pending'}), 'processing');
      expect(orderStatusOf({'status': 'in_escrow'}), 'accepted');
      expect(
        orderStatusOf({'status': 'in_escrow', 'buyerConfirmed': true}),
        'buyer_confirmed',
      );
      expect(orderStatusOf({'status': 'released'}), 'completed');
      expect(orderStatusOf({'status': 'refunded'}), 'cancelled');
    });

    test('explicit paymentStatus wins over legacy status', () {
      expect(
        paymentStatusOf({
          'paymentStatus': 'release_pending',
          'status': 'in_escrow',
        }),
        'release_pending',
      );
    });

    test('legacy status maps to a money status', () {
      expect(paymentStatusOf({'status': 'pending_payment'}), 'payment_pending');
      expect(paymentStatusOf({'status': 'in_escrow'}), 'held_by_platform');
      expect(
        paymentStatusOf({'status': 'in_escrow', 'buyerConfirmed': true}),
        'release_pending',
      );
      expect(paymentStatusOf({'status': 'released'}), 'released_to_seller');
      expect(paymentStatusOf({'status': 'cod_pending'}), 'unpaid');
      expect(paymentStatusOf({'status': 'refunded'}), 'refunded');
    });

    test('order and payment status are genuinely independent', () {
      // A shipped-but-still-held order: fulfillment advanced, money unchanged.
      final o = {
        'status': 'in_escrow',
        'orderStatus': 'shipped',
        'paymentStatus': 'held_by_platform',
      };
      expect(orderStatusOf(o), 'shipped');
      expect(paymentStatusOf(o), 'held_by_platform');
    });
  });

  group('Seller shipping flow transitions', () {
    test('advances one legal step at a time', () {
      expect(nextShippingStep('pending'), 'accepted');
      expect(nextShippingStep('accepted'), 'processing');
      expect(nextShippingStep('processing'), 'shipped');
      expect(nextShippingStep('shipped'), 'delivered');
    });

    test('no further seller step after delivered', () {
      expect(nextShippingStep('delivered'), '');
      expect(nextShippingStep('buyer_confirmed'), '');
      expect(nextShippingStep('completed'), '');
    });
  });

  group('Policy-compliant status wording', () {
    test('payment labels never say "escrow"', () {
      for (final s in [
        'held_by_platform',
        'release_pending',
        'released_to_seller',
        'refunded',
      ]) {
        expect(paymentStatusLabel(s).toLowerCase().contains('escrow'), isFalse);
      }
      expect(paymentStatusLabel('held_by_platform'), 'Held by PakBazar');
      expect(
        paymentStatusLabel('release_pending'),
        'Pending seller settlement',
      );
      expect(paymentStatusLabel('released_to_seller'), 'Paid out to seller');
    });
  });
}
