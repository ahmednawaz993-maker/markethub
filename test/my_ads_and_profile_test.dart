// Two screens a seller lives on, and what they were telling people.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

Listing _ad({
  String id = 'a',
  String approval = 'approved',
  String status = 'in_stock',
  String reason = '',
}) => Listing(
  id: id,
  title: 'An ad',
  price: '1000',
  location: 'Lahore',
  imageUrl: '',
  category: 'Motors',
  approvalStatus: approval,
  status: status,
  rejectionReason: reason,
);

void main() {
  group('what to call somebody on their own account card', () {
    test('a phone sign-up is not a guest', () {
      // This is the bug. The card read `user?.email ?? 'Guest user'`, and a
      // phone account has no email — so every phone sign-up opened their
      // profile and was told they were browsing as a guest, directly above
      // their own verification badge.
      expect(
        accountHeadline(isAnonymous: false, phoneNumber: '+923001234567'),
        '+923001234567',
      );
    });

    test('a name they chose wins over the address they signed up with', () {
      expect(
        accountHeadline(
          isAnonymous: false,
          displayName: 'Ahmed Motors',
          email: 'ahmed@example.com',
        ),
        'Ahmed Motors',
      );
    });

    test('an email account with no name still shows the address', () {
      expect(
        accountHeadline(isAnonymous: false, email: 'ahmed@example.com'),
        'ahmed@example.com',
      );
    });

    test('a blank name does not count as having one', () {
      expect(
        accountHeadline(
          isAnonymous: false,
          displayName: '   ',
          email: 'ahmed@example.com',
        ),
        'ahmed@example.com',
      );
    });

    test('a guest is a guest whatever else is on the account', () {
      // Anonymous accounts can carry a display name after a half-finished
      // link; calling them by it would claim they are signed in.
      expect(
        accountHeadline(isAnonymous: true, displayName: 'Ahmed'),
        'Guest user',
      );
    });

    test('signed in but anonymous to us', () {
      expect(accountHeadline(isAnonymous: false), 'Your account');
    });
  });

  group('the shelves in My Ads', () {
    test('a live ad is on the live shelf only', () {
      final ad = _ad();
      expect(MyAdsShelf.live.accepts(ad), isTrue);
      expect(MyAdsShelf.pending.accepts(ad), isFalse);
      expect(MyAdsShelf.rejected.accepts(ad), isFalse);
      expect(MyAdsShelf.sold.accepts(ad), isFalse);
    });

    test('an ad waiting for review is not live', () {
      // It is invisible to buyers, and mixing it in with what is live is how
      // a seller ends up believing an ad is running when it is not.
      final ad = _ad(approval: 'pending');
      expect(MyAdsShelf.live.accepts(ad), isFalse);
      expect(MyAdsShelf.pending.accepts(ad), isTrue);
    });

    test('a rejected ad is not live either', () {
      final ad = _ad(approval: 'rejected');
      expect(MyAdsShelf.live.accepts(ad), isFalse);
      expect(MyAdsShelf.rejected.accepts(ad), isTrue);
    });

    test('a sold ad is off the live shelf', () {
      final ad = _ad(status: 'sold');
      expect(MyAdsShelf.sold.accepts(ad), isTrue);
      expect(MyAdsShelf.live.accepts(ad), isFalse);
    });

    test('a paused ad is on neither the live nor the sold shelf', () {
      final ad = _ad(status: 'inactive');
      expect(MyAdsShelf.live.accepts(ad), isFalse);
      expect(MyAdsShelf.sold.accepts(ad), isFalse);
      expect(MyAdsShelf.all.accepts(ad), isTrue, reason: 'but it still exists');
    });

    test('an ad from before moderation existed counts as live', () {
      // approvalStatus is '' on ads posted before the review queue. They are
      // public, so the shelf has to agree with what buyers can see.
      expect(MyAdsShelf.live.accepts(_ad(approval: '')), isTrue);
    });

    test('every ad lands on the All shelf', () {
      for (final ad in [
        _ad(),
        _ad(approval: 'pending'),
        _ad(approval: 'rejected'),
        _ad(status: 'sold'),
        _ad(status: 'inactive'),
      ]) {
        expect(MyAdsShelf.all.accepts(ad), isTrue);
      }
    });
  });

  group('why an ad was turned down', () {
    test('the reason survives a round trip through Firestore', () {
      // It is written by the admin panel and read on My Ads; the model sat
      // between them and used to drop it.
      final ad = _ad(approval: 'rejected', reason: 'Photos show another shop');
      expect(ad.toMap()['rejectionReason'], 'Photos show another shop');
    });

    test('an ad with no reason recorded still has a field to read', () {
      expect(_ad().rejectionReason, '');
    });

    testWidgets('the seller is shown the reason and what to do', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RejectedAdNote(reason: 'Photos show another shop'),
          ),
        ),
      );

      expect(find.text('Photos show another shop'), findsOneWidget);
      expect(
        find.text('Tap to edit and send it back for review.'),
        findsOneWidget,
      );
    });

    testWidgets('an old rejection with no reason still says something', (
      tester,
    ) async {
      // Ads turned down before the reason was stored have nothing to show,
      // and a blank strip would read as a rendering fault.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RejectedAdNote(reason: '   ')),
        ),
      );

      expect(find.text('This ad was not approved.'), findsOneWidget);
    });

    testWidgets('a long reason wraps instead of overflowing', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RejectedAdNote(
              reason:
                  'The photos in this ad belong to another shop and the price '
                  'does not match the description, so please post your own '
                  'pictures and correct the price before sending it back.',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
