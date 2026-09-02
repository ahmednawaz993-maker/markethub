// The web half of Google sign-in, which has now broken twice in opposite
// directions.
//
// First it was a popup on firebaseapp.com: a different origin from the site,
// sending Cross-Origin-Opener-Policy: same-origin, so the app could never see
// the popup close and sat there after the user had signed in.
//
// The fix for that pointed authDomain at whatever host was serving the app,
// which made the popup same-origin — and broke sign-in outright, earlier and
// harder, because our own host is not a registered redirect URI on the OAuth
// client:
//
//   Error 400: redirect_uri_mismatch
//   redirect_uri = https://pakbazar24.com/__/auth/handler
//
// Neither failure is visible from the code, from a test that mocks Firebase,
// or from the app on Android — which uses the native picker and was working
// fine throughout. Both were found by driving the live site and reading where
// the browser actually ended up. What is pinned here is the pair of choices
// that keep both failures away.

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/firebase_options.dart';
import 'package:markethub/main.dart';

void main() {
  test('the auth domain is one Google will accept a redirect to', () {
    // Adding a domain to Firebase Auth's authorised list does NOT add it to
    // the OAuth client's redirect URIs. Only this one is registered.
    expect(
      DefaultFirebaseOptions.webAuthDomain,
      'markethub-80276.firebaseapp.com',
    );
  });

  test('the web signs in by redirect, not by popup', () {
    // A popup needs the opener relationship that the handler's COOP header
    // severs. A redirect needs no opener at all.
    final src = File('lib/src/social_auth.dart').readAsStringSync();
    expect(src, contains('signInWithRedirect'));
    expect(src, contains('linkWithRedirect'));

    // Scoped to the Google entry point. The Facebook function still uses a
    // popup and has the same flaw, but its button was removed in v1.2.4 and
    // nothing reaches it.
    final start = src.indexOf('Future<UserCredential> signInWithGoogle()');
    final end = src.indexOf('/// Starts the web sign-in', start);
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    expect(
      src.substring(start, end),
      isNot(contains('Popup')),
      reason: 'the popup flow is what COOP breaks',
    );
  });

  test('a browsing guest is upgraded rather than replaced', () {
    // Somebody who has been browsing has a cart and favourites on an
    // anonymous uid. Signing them in with a fresh account throws that away.
    final src = File('lib/src/social_auth.dart').readAsStringSync();
    expect(src, contains('guest.linkWithRedirect(provider)'));
  });

  test('the result of the redirect is collected at startup', () {
    // This is the half that actually signs the user in. Without it the
    // browser comes back from Google and nothing happens at all.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('await completeWebSignIn()'));

    final src = File('lib/src/social_auth.dart').readAsStringSync();
    expect(src, contains('getRedirectResult'));
  });

  test('an already-claimed Google account does not send the user back', () {
    // Linking fails when that Google account already has its own PakBazar
    // account. The credential comes back attached to the error, so they can
    // be signed into their real account without a second trip to Google.
    final src = File('lib/src/social_auth.dart').readAsStringSync();
    expect(src, contains('signInWithCredential(credential)'));
  });

  test('being sent to Google is not reported as a failure', () {
    // The web call never returns — the page is replaced. The caller sees a
    // thrown redirect-in-progress, and a red banner on a page that is about
    // to disappear helps nobody.
    expect(
      friendlySignInError(
        FirebaseAuthException(code: 'redirect-in-progress'),
        provider: 'Google',
      ),
      '',
    );
  });

  test('but a real refusal still gets a message', () {
    expect(
      friendlySignInError(
        FirebaseAuthException(code: 'network-request-failed'),
        provider: 'Google',
      ),
      isNotEmpty,
    );
  });
}
