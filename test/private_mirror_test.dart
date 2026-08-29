// Denormalised copies must not be more public than what they copy.
//
// This test exists because of a mistake made here, caught before any user data
// reached the field.
//
// The followed-sellers rail was costing thirty document reads on every launch,
// so the seller ids were mirrored somewhere the session was already reading —
// the user's profile document. That worked, and it was wrong: `users/{userId}`
// is `allow read: if isSignedIn()`, because seller pages need a name and a
// rating, while the `following` subcollection is owner-only and the rules call
// it "their own private list". The copy would have published who everybody
// follows to every signed-in account.
//
// THE GENERAL FORM: a denormalised copy inherits the permissions of where you
// PUT it, not of where it came from. Nothing about the code looks different,
// nothing fails, and no user ever sees a symptom — which is exactly why it
// needs a test rather than care.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the private mirrors are allowed to live.
const _privatePath = "collection('private')";

void main() {
  final rules = File('firestore.rules').readAsStringSync();
  final sources = {
    for (final f in Directory('lib/src').listSync().whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };
  final all = sources.values.join('\n');

  test('the profile document really is readable by anyone signed in', () {
    // The premise of this whole test. If profiles ever became owner-only, the
    // reasoning below would be obsolete rather than merely unnecessary — so
    // assert the fact instead of trusting a comment about it.
    final block = rules.substring(rules.indexOf('match /users/{userId} {'));
    final readLine = block
        .split('\n')
        .firstWhere((l) => l.contains('allow read'));
    expect(
      readLine,
      contains('isSignedIn()'),
      reason: 'users/{userId} is readable by any signed-in account',
    );
    expect(
      readLine,
      isNot(contains('request.auth.uid == userId')),
      reason: 'it is NOT restricted to the owner',
    );
  });

  test('the follow list is owner-only, so a mirror of it must be too', () {
    final block = rules.substring(rules.indexOf('match /following/{sellerId}'));
    expect(
      block.split('\n').take(4).join('\n'),
      contains('request.auth.uid == userId'),
      reason: 'the follow list is private to its owner',
    );
  });

  test('followingIds is written only to the private document', () {
    // The mistake, in the exact shape it took: a set() on users/{uid} carrying
    // the follow ids.
    //
    // The reference is usually held in a local, so a statement-level check
    // would see `batch.set(mySocial, ...)` and learn nothing. This resolves
    // that one hop — which matters, because the wrong version of this code
    // looked exactly the same at the call site and differed only in what the
    // variable had been assigned.
    for (final entry in sources.entries) {
      final src = entry.value;
      var from = 0;
      while (true) {
        final at = src.indexOf('kFollowingIdsField', from);
        if (at < 0) break;
        from = at + 1;
        final start = src.lastIndexOf(';', at) + 1;
        final end = src.indexOf(';', at);
        final stmt = src.substring(start, end < 0 ? src.length : end);
        if (!stmt.contains('set(') && !stmt.contains('update(')) continue;

        // What is being written to: the first argument of set(x, ...), or the
        // receiver of x.set(...) / x.update(...).
        var target = RegExp(r'(?:batch\.)?set\(\s*([A-Za-z_][A-Za-z0-9_.()]*)')
            .firstMatch(stmt)
            ?.group(1);
        target ??= RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(?:set|update)\(')
            .firstMatch(stmt)
            ?.group(1);

        var resolved = target ?? stmt;
        // One hop: if it is a plain local, find where it was assigned.
        if (target != null && !target.contains('(')) {
          final decl = RegExp(
            r'final\s+' + RegExp.escape(target) + r'\s*=\s*([^;]+);',
          ).firstMatch(src);
          if (decl != null) resolved = decl.group(1)!;
        }

        expect(
          resolved.contains('privateSocialRef') ||
              resolved.contains(_privatePath),
          isTrue,
          reason:
              'In ${entry.key.split(RegExp(r"[\/]")).last}, the follow ids are '
              'written to `$resolved`, which is not the owner-only private '
              'document. users/{uid} is readable by every signed-in account.',
        );
      }
    }
  });

  test('the mirror lives under the private subcollection', () {
    expect(
      all,
      contains(_privatePath),
      reason: 'privateSocialRef must point at users/{uid}/private/...',
    );
    final ref = all.substring(all.indexOf('privateSocialRef(String uid)'));
    expect(
      ref.split('\n').take(8).join('\n'),
      contains(_privatePath),
      reason: 'the mirror must be owner-only',
    );
  });

  test('browsing history is not written to the profile either', () {
    // The same trap, one rail over: what somebody has been looking at is at
    // least as private as who they follow. It lives on the device.
    expect(
      all.contains("'recentlyViewedIds'"),
      isFalse,
      reason: 'browsing history belongs on the device, not on a public profile',
    );
  });
}
