import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// The feedback queue has to cope with two schemas at once. Messages written by
// the Help & Feedback sheet carry `email`/`type`/`status`; messages written by
// the older review-prompt path carried `userEmail` and nothing else. Both are
// already in the collection, so the admin panel reads defensively rather than
// assuming the newer shape.

void main() {
  group('feedbackEmailOf', () {
    test('reads the Help & Feedback sheet field', () {
      expect(feedbackEmailOf({'email': 'a@b.com'}), 'a@b.com');
    });

    test('falls back to the legacy review-prompt field', () {
      expect(feedbackEmailOf({'userEmail': 'legacy@b.com'}), 'legacy@b.com');
    });

    test('prefers the current field when a doc carries both', () {
      expect(
        feedbackEmailOf({'email': 'new@b.com', 'userEmail': 'old@b.com'}),
        'new@b.com',
      );
    });

    // An empty string in the current field must not shadow a usable legacy one,
    // or the admin sees "no email" on a message that has one.
    test('an empty current field falls through to the legacy one', () {
      expect(
        feedbackEmailOf({'email': '', 'userEmail': 'old@b.com'}),
        'old@b.com',
      );
    });

    test('returns empty when neither is present', () {
      expect(feedbackEmailOf(const {}), '');
    });
  });

  group('feedbackStatusOf', () {
    test('passes through the known statuses', () {
      for (final s in kFeedbackStatuses) {
        expect(feedbackStatusOf({'status': s}), s);
      }
    });

    // Legacy review-prompt docs have no status at all. Defaulting anywhere but
    // 'open' would hide them from the queue staff actually work.
    test('a missing status is open', () {
      expect(feedbackStatusOf(const {}), 'open');
    });

    test('an unrecognised status is open rather than passed through', () {
      expect(feedbackStatusOf({'status': 'archived'}), 'open');
      expect(feedbackStatusOf({'status': ''}), 'open');
    });
  });

  group('AdminFeedbackCard layout', () {
    Map<String, dynamic> fat({String status = 'open', bool replied = false}) => {
      'type': 'Help',
      'source': 'review_prompt',
      'status': status,
      'userId': 'u1',
      'email': 'muhammad.abdul.rehman.siddiqui@somereallylongdomain.com.pk',
      'message':
          'Mera order abhi tak nahi aaya aur seller reply nahi kar raha. '
          'I have been waiting eleven days for a delivery that the tracking '
          'says was dispatched, and nobody from the seller side answers.',
      'createdAt': Timestamp.now(),
      if (replied) ...{
        'adminReply':
            'Sorry about that — we have contacted the seller and will follow '
            'up with you within 24 hours.',
        'adminReplyBy': 'someone.with.a.long.address@pakbazar24.com',
        'adminReplyAt': Timestamp.now(),
      },
    };

    for (final width in [320.0, 360.0, 411.0, 768.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final (label, st, rep) in const [
          ('open', 'open', false),
          ('replied', 'replied', true),
          ('resolved', 'resolved', true),
        ]) {
          testWidgets('no overflow — $label at ${width.toInt()}px, text x$scale',
              (tester) async {
            tester.view.physicalSize = Size(width, 1400);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1400),
                  textScaler: TextScaler.linear(scale),
                ),
                child: MaterialApp(
                  home: Scaffold(
                    body: ListView(
                      children: [
                        AdminFeedbackCard(
                          docId: 'f1',
                          data: fat(status: st, replied: rep),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('a resolved item offers Re-open instead of Mark resolved',
        (tester) async {
      tester.view.physicalSize = const Size(411, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AdminFeedbackCard(
                  docId: 'f1',
                  data: fat(status: 'resolved', replied: true),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Re-open'), findsOneWidget);
      expect(find.text('Mark resolved'), findsNothing);
    });

    testWidgets('an already-answered item offers "Reply again"',
        (tester) async {
      tester.view.physicalSize = const Size(411, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AdminFeedbackCard(docId: 'f1', data: fat(replied: true)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Reply again'), findsOneWidget);
      // The reply itself is shown back to the admin, not just recorded.
      expect(find.textContaining('contacted the seller'), findsOneWidget);
    });
  });
}
