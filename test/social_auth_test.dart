// Facebook sign-in: the parts that can be tested without a live OAuth window.
//
// The sign-in call itself needs a real popup and a real Meta app, so what is
// pinned here is the logic that decides what the USER is told — which is where
// a social login actually goes wrong. A person who already has an email/
// password account and taps "Continue with Facebook" gets a Firebase error
// code, and if we render that raw they are simply stuck with no idea which door
// to use.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

FirebaseAuthException err(String code, [String? message]) =>
    FirebaseAuthException(code: code, message: message);

void main() {
  group('friendlyFacebookError', () {
    test('an existing email account gets told to use the other door', () {
      final msg = friendlyFacebookError(
        err('account-exists-with-different-credential'),
      );
      // The specifics matter: name the account, name the way in.
      expect(msg, contains('email'));
      expect(msg, contains('password'));
      expect(msg, isNot(contains('account-exists')));
    });

    test('a cancelled popup is silent, not an error', () {
      // The user closing the window is a decision, not a failure. An empty
      // string is the signal to show nothing at all; anything else would put a
      // red banner on the screen for someone who simply changed their mind.
      for (final code in [
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-canceled',
        'user-cancelled',
      ]) {
        expect(friendlyFacebookError(err(code)), '', reason: code);
      }
    });

    test('a blocked popup explains the fix', () {
      expect(friendlyFacebookError(err('popup-blocked')), contains('pop-up'));
    });

    test('no message is ever a raw Firebase code', () {
      for (final code in [
        'network-request-failed',
        'too-many-requests',
        'operation-not-allowed',
        'user-disabled',
      ]) {
        final msg = friendlyFacebookError(err(code));
        expect(msg, isNotEmpty, reason: code);
        expect(msg, isNot(contains(code)), reason: code);
        // Sentences, not codes: every one ends like something a person wrote.
        expect(msg.endsWith('.'), isTrue, reason: code);
      }
    });

    test('an unknown code falls back to the Firebase message, then to prose',
        () {
      expect(
        friendlyFacebookError(err('something-new', 'Server said no.')),
        'Server said no.',
      );
      expect(friendlyFacebookError(err('something-new')), contains('Facebook'));
    });

    test('a non-Firebase throwable still produces a sentence', () {
      // A TypeError or a timeout must not reach the user as a stack trace.
      expect(friendlyFacebookError(StateError('boom')), contains('Facebook'));
      expect(friendlyFacebookError('boom'), contains('Facebook'));
    });
  });

  group('facebookFriendsOnPakBazar', () {
    test('returns nothing when nobody signed in with Facebook', () async {
      // No token means no Graph call at all — this must not throw or hang for
      // the overwhelming majority of players, who sign in with email.
      facebookAccessToken = null;
      expect(await facebookFriendIds(), isEmpty);
      expect(await facebookFriendsOnPakBazar(), isEmpty);
    });
  });
}
