// The two screens between wanting something and owning it.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

DeliveryAddress _address({
  String fullName = 'Ahmed Nawaz',
  String phone = '03001234567',
  String province = 'Punjab',
  String city = 'Lahore',
  String area = 'Gulberg',
  String streetAddress = 'Main Boulevard',
  String houseOrBuilding = 'House 12',
}) => DeliveryAddress(
  id: 'a1',
  label: 'Home',
  fullName: fullName,
  phone: phone,
  province: province,
  city: city,
  area: area,
  streetAddress: streetAddress,
  houseOrBuilding: houseOrBuilding,
);

void main() {
  group('why Place Order is greyed out', () {
    test('a complete address blocks nothing', () {
      expect(_address().missing, isEmpty);
      expect(_address().isComplete, isTrue);
    });

    test('a missing house number is named', () {
      // The case that actually happened: an address saved before the field
      // existed. The button went grey and the screen said nothing at all,
      // because the only explanation in the code sat behind that button.
      expect(_address(houseOrBuilding: '').missing, ['a house or building']);
    });

    test('a number that is not a Pakistani mobile is named', () {
      expect(_address(phone: '12345').missing, ['a valid mobile number']);
    });

    test('several missing fields are all named, in reading order', () {
      expect(_address(fullName: '  ', city: '', area: '').missing, [
        'a name',
        'a city',
        'an area',
      ]);
    });

    test('complete and missing can never disagree', () {
      // isComplete is now defined as missing.isEmpty, so the button and the
      // explanation cannot drift apart — which is how the silent version
      // survived so long.
      for (final a in [
        _address(),
        _address(phone: ''),
        _address(streetAddress: ''),
        _address(province: '', city: ''),
      ]) {
        expect(a.isComplete, a.missing.isEmpty);
      }
    });
  });

  group('saying it in a sentence', () {
    test('one thing', () {
      expect(listPhrase(['a city']), 'a city');
    });

    test('two things', () {
      expect(listPhrase(['a city', 'an area']), 'a city and an area');
    });

    test('three things', () {
      expect(
        listPhrase(['a name', 'a city', 'an area']),
        'a name, a city and an area',
      );
    });

    test('nothing', () {
      expect(listPhrase([]), '');
    });
  });

  group('the shelves in My Orders', () {
    test('an order awaiting payment is the one that needs the buyer', () {
      expect(OrderShelf.unpaid.accepts('pending_payment'), isTrue);
      expect(OrderShelf.active.accepts('pending_payment'), isFalse);
      expect(OrderShelf.done.accepts('pending_payment'), isFalse);
    });

    test('money moving counts as in progress', () {
      for (final s in ['payment_review', 'cod_pending', 'in_escrow']) {
        expect(OrderShelf.active.accepts(s), isTrue, reason: s);
        expect(OrderShelf.unpaid.accepts(s), isFalse, reason: s);
      }
    });

    test('paid out and completed are both finished', () {
      expect(OrderShelf.done.accepts('released'), isTrue);
      expect(OrderShelf.done.accepts('completed'), isTrue);
    });

    test('a refund is closed, not completed', () {
      // The buyer did not end up with the item. Filing it under Completed
      // would tell them a story that did not happen.
      expect(OrderShelf.closed.accepts('refunded'), isTrue);
      expect(OrderShelf.done.accepts('refunded'), isFalse);
    });

    test('cancelled is closed', () {
      expect(OrderShelf.closed.accepts('cancelled'), isTrue);
    });

    test('every status lands on the All shelf', () {
      for (final s in [
        'pending_payment',
        'payment_review',
        'cod_pending',
        'in_escrow',
        'released',
        'completed',
        'refunded',
        'cancelled',
        'something_added_later',
      ]) {
        expect(OrderShelf.all.accepts(s), isTrue, reason: s);
      }
    });

    test('a status nobody has a shelf for is still reachable', () {
      // A new status added server-side must never make an order invisible.
      // It falls off the four named shelves, and All is what catches it.
      const unknown = 'something_added_later';
      final named = OrderShelf.values.where((s) => s != OrderShelf.all);
      expect(named.any((s) => s.accepts(unknown)), isFalse);
      expect(OrderShelf.all.accepts(unknown), isTrue);
    });

    test('the shelf is named for who is looking at it', () {
      expect(OrderShelf.unpaid.label(false), 'To pay');
      expect(OrderShelf.unpaid.label(true), 'Unpaid');
    });
  });
}
