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
}
