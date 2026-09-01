// What happens to a profile when a guest signs in.
//
// Browsing without an account is a button on the landing page now, so the
// common path into PakBazar is: browse as a guest, like something, then sign
// in with Google. Linking keeps the SAME uid, which means the profile document
// already exists — and the code that fills a profile in only ever ran when the
// document was missing.
//
// The result was an account that had signed in with Google and was still
// marked anonymous, still had no name, and had no email address on file. None
// of it throws, none of it appears in a log, and the user just sees their own
// ads posted by the first half of their email address.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('a guest who signs in with Google', () {
    // What their document looks like after browsing as a guest.
    Map<String, dynamic> guestDoc() => {
      'isAnonymous': true,
      'verified': false,
      'createdAt': 'whenever',
    };

    test('stops being marked anonymous', () {
      final updates = profileUpdates(
        existing: guestDoc(),
        isAnonymous: false,
        emailVerified: true,
        displayName: 'Ahmed Nawaz',
        photoUrl: 'https://example.com/a.jpg',
      );
      expect(updates['isAnonymous'], false);
    });

    test('gets the name Google gave us', () {
      final updates = profileUpdates(
        existing: guestDoc(),
        isAnonymous: false,
        emailVerified: true,
        displayName: 'Ahmed Nawaz',
      );
      expect(updates['displayName'], 'Ahmed Nawaz');
    });

    test('gets their photo', () {
      final updates = profileUpdates(
        existing: guestDoc(),
        isAnonymous: false,
        emailVerified: true,
        photoUrl: 'https://example.com/a.jpg',
      );
      expect(updates['photoUrl'], 'https://example.com/a.jpg');
    });

    test('and their verified badge is brought up to date', () {
      final updates = profileUpdates(
        existing: guestDoc(),
        isAnonymous: false,
        emailVerified: true,
      );
      expect(updates['verified'], true);
    });
  });

  group('what must NOT be touched', () {
    test('a name the user typed themselves is never overwritten', () {
      // Filling a blank is help. Replacing somebody's chosen name with the one
      // on their Google account is not, and it would happen on every launch.
      final updates = profileUpdates(
        existing: {
          'isAnonymous': false,
          'verified': true,
          'displayName': 'Ahmed Motors',
        },
        isAnonymous: false,
        emailVerified: true,
        displayName: 'Ahmed Nawaz',
      );
      expect(updates.containsKey('displayName'), isFalse);
    });

    test('a photo they chose is never overwritten either', () {
      final updates = profileUpdates(
        existing: {
          'isAnonymous': false,
          'verified': true,
          'photoUrl': 'https://example.com/mine.jpg',
        },
        isAnonymous: false,
        emailVerified: true,
        photoUrl: 'https://example.com/google.jpg',
      );
      expect(updates.containsKey('photoUrl'), isFalse);
    });

    test('a whitespace-only name does not count as having one', () {
      final updates = profileUpdates(
        existing: {'isAnonymous': false, 'verified': true, 'displayName': '   '},
        isAnonymous: false,
        emailVerified: true,
        displayName: 'Ahmed Nawaz',
      );
      expect(updates['displayName'], 'Ahmed Nawaz');
    });

    test('an empty name from the provider is not written', () {
      // Email and phone sign-ups have no display name. Writing '' would make
      // the profile look filled in when it is not.
      final updates = profileUpdates(
        existing: {'isAnonymous': false, 'verified': true},
        isAnonymous: false,
        emailVerified: true,
        displayName: '   ',
      );
      expect(updates.containsKey('displayName'), isFalse);
    });
  });

  group('when nothing has changed', () {
    test('nothing is written', () {
      // This runs on every launch. Returning a payload every time would be a
      // pointless write per user per app open — and the write itself would
      // keep bumping the document for no reason.
      final settled = {
        'isAnonymous': false,
        'verified': true,
        'displayName': 'Ahmed Nawaz',
        'photoUrl': 'https://example.com/a.jpg',
      };
      final updates = profileUpdates(
        existing: settled,
        isAnonymous: false,
        emailVerified: true,
        displayName: 'Ahmed Nawaz',
        photoUrl: 'https://example.com/a.jpg',
      );
      expect(updates, isEmpty);
    });

    test('a missing document asks for nothing — creation handles that', () {
      expect(
        profileUpdates(
          existing: null,
          isAnonymous: false,
          emailVerified: true,
          displayName: 'Ahmed Nawaz',
        ),
        isEmpty,
      );
    });
  });

  test('an email sign-up that later verifies gets its badge', () {
    // The one case the old code did handle, kept so the fix did not lose it.
    final updates = profileUpdates(
      existing: {'isAnonymous': false, 'verified': false},
      isAnonymous: false,
      emailVerified: true,
    );
    expect(updates, {'verified': true});
  });
}
