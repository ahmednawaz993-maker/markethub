// The idle app must hold no Firestore listener.
//
// This is the property the whole session layer exists to protect, and it is
// easy to lose by accident.
//
// The Firestore SDK multiplexes EVERY listener a client has over one
// connection, and Firestore allows one million concurrent connections per
// database. So what decides whether a million people can use this app at once
// is not how many listeners each of them has — it is whether they have any at
// all. One listener and twenty cost the same connection. Zero costs none.
//
// Which means a single `.snapshots()` added to the home screen — the screen
// every user sits on, doing nothing — silently undoes the entire change, and
// nothing about the app would look or behave any differently. There is no
// runtime symptom to notice. Only this test.
//
// Screens you have to OPEN are exempt: a chat thread should absolutely hold a
// live listener while you are reading it. The rule is about the resting state.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The widgets that are mounted while a user is simply browsing.
///
/// Anything reachable without tapping anything: the home tab, its rails, its
/// header, and the notification bell in that header.
const _idleWidgets = {
  'VerifyBanner',
  'ContinueBrowsingRail',
  'RecentlyViewedRail',
  'FollowingRail',
  'DealsRail',
  'FeaturedBusinessesRail',
  'NotificationBell',
};

/// Reads a class body out of a source file.
String? _classBody(String source, String name) {
  final start = source.indexOf('class $name extends');
  if (start < 0) return null;
  // Up to the next top-level declaration.
  final next = source.indexOf('\nclass ', start + 1);
  return source.substring(start, next < 0 ? source.length : next);
}

void main() {
  final sources = <String, String>{
    for (final f in Directory('lib/src').listSync().whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };

  test('nothing on the resting home screen opens a Firestore listener', () {
    final offenders = <String>[];
    final found = <String>{};

    for (final entry in sources.entries) {
      for (final widget in _idleWidgets) {
        final body = _classBody(entry.value, widget);
        if (body == null) continue;
        found.add(widget);
        if (body.contains('.snapshots()')) {
          offenders.add(
            '$widget (${entry.key.split(RegExp(r"[\\/]")).last}) '
            'opens a live listener',
          );
        }
      }
    }

    // If a widget was renamed away, this test would quietly stop checking it.
    expect(
      found,
      containsAll(_idleWidgets),
      reason:
          'These widgets were not found, so they are no longer being checked: '
          '${_idleWidgets.difference(found)}. Update _idleWidgets.',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'The idle app must hold NO Firestore listener — one is a connection, '
          'and connections are what run out at a million users:\n'
          '  ${offenders.join('\n  ')}\n\n'
          'Read it through UserSession instead, and refresh it on a signal: '
          'launch, resume, a push, or the user\'s own action.',
    );
  });

  test('the session is refreshed on every signal it depends on', () {
    // The session trades a live socket for being told when things change. If a
    // signal is dropped, the app does not break — it just quietly goes stale,
    // which is far harder to notice than a crash and much worse to debug from
    // a user's description.
    final all = sources.values.join('\n');
    final signals = {
      'launch': 'userSession.refresh()',
      'a push arriving': 'userSession.refreshUnread()',
      // Follows also update the id list cached on the profile, so this
      // signal carries the change as well as triggering the reload.
      'following a seller': 'userSession.noteFollowChange(',
      'opening an ad': 'userSession.refreshRecentlyViewed()',
      'signing out': 'userSession.clear()',
    };
    for (final e in signals.entries) {
      expect(
        all.contains(e.value),
        isTrue,
        reason:
            'Nothing refreshes the session on ${e.key} (${e.value}). '
            'Without it that part of the screen goes stale silently.',
      );
    }
  });

  test('app resume refreshes the session', () {
    // The one signal that cannot be inferred from a user action: anything may
    // have changed while the app was in the background, and by design nothing
    // was listening.
    final presence = sources.entries
        .firstWhere((e) => e.key.endsWith('presence.dart'))
        .value;
    final resume = presence.substring(
      presence.indexOf('didChangeAppLifecycleState'),
    );
    expect(
      resume.split('\n').take(20).join('\n'),
      contains('userSession.refresh()'),
      reason: 'Coming back to the app must re-read what changed while it slept',
    );
  });
}
