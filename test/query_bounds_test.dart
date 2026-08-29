// Live queries must be bounded.
//
// A `.snapshots()` with no `.limit()` on a collection that grows with the
// business is a download that grows with the business — and it is re-sent in
// full whenever any matching document changes. It is invisible while the app
// is small and it is the thing that breaks first when the app is not: the
// person it hurts most is your most successful seller, on their phone, paying
// for data by the megabyte.
//
// Found by measuring: 35 unbounded live queries on large collections, plus
// seven places that downloaded an entire collection to display a number. The
// admin dashboard streamed every user, listing, order and offer at once.
//
// This test reads the source. That is unusual, and it is deliberate: the fault
// is a shape a query has, not a behaviour a widget test can observe, and every
// one of these took a human reading the code to notice. A ratchet is the only
// thing that stops them coming back one convenient stream at a time.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Collections whose size grows with how well the marketplace is doing.
///
/// A live query over one of these must say how much it wants. Small fixed
/// collections (config, staff, categories) are exempt — they do not grow.
const _unbounded = {
  'listings',
  'orders',
  'users',
  'offers',
  'chats',
  'messages',
  'notifications',
  'followers',
  'following',
  'reviews',
  'favorites',
};

/// Query shapes that bound themselves without a `.limit()`.
///
/// The important one is `.doc(...)`: everything after the last `collection(..)`
/// in the chain decides what is actually being watched, and if a `.doc(` shows
/// up there then it is ONE document, however large the collection around it.
bool _selfBounding(String query) {
  // count() and the other aggregations never return documents at all.
  if (query.contains('.count()') || query.contains('.aggregate(')) return true;

  final collections = RegExp(
    r"collection(?:Group)?\('[A-Za-z_]+'\)",
  ).allMatches(query).toList();
  if (collections.isEmpty) return false;
  final tail = query.substring(collections.last.end);
  return tail.contains('.doc(');
}

/// The collection actually being watched: the last one named in the chain.
///
/// `users/{id}/favorites` watches favorites, not users — reading the first
/// name instead reports the wrong collection and, worse, exempts real
/// offenders whose parent happens not to be on the list.
String? _watchedCollection(String query) {
  final names = RegExp(
    r"collection(?:Group)?\('([A-Za-z_]+)'\)",
  ).allMatches(query).map((m) => m.group(1)!).toList();
  return names.isEmpty ? null : names.last;
}

/// Whether this `.snapshots()` is real code rather than an example in a
/// comment. The comments in this codebase quote the patterns they warn about,
/// which is exactly the text being searched for.
bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

void main() {
  final files = Directory('lib/src')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no live query streams a growing collection without a limit', () {
    final offenders = <String>[];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('.snapshots()')) continue;
        if (_isComment(lines[i])) continue;
        // Walk back far enough to see the whole chained query.
        final query = lines.sublist((i - 14).clamp(0, i), i + 1).join('\n');
        if (query.contains('.limit(') || _selfBounding(query)) continue;

        // The LAST collection in the chain is the one being watched:
        // users/{id}/favorites streams favorites, not users.
        final watched = _watchedCollection(query);
        if (watched == null || !_unbounded.contains(watched)) continue;

        offenders.add(
          '${file.uri.pathSegments.last}:${i + 1} '
          "streams '$watched' with no limit",
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These live queries have no bound on how much they download:\n'
          '  ${offenders.join('\n  ')}\n\n'
          'Add .limit(), or use .count() if the screen only needs a number.',
    );
  });

  test('nothing counts a collection by downloading it', () {
    // The pattern this replaces:
    //   stream: userRef.collection('followers').snapshots(),
    //   builder: (c, s) => Text('${s.data?.docs.length ?? 0}'),
    // which fetches every follower to print how many there are.
    final offenders = <String>[];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('docs.length')) continue;
        if (_isComment(lines[i])) continue;
        final context = lines.sublist((i - 12).clamp(0, i), i + 1).join('\n');
        if (!context.contains('.snapshots()')) continue;
        if (_selfBounding(context)) continue;
        if (context.contains('.limit(')) continue; // capped, e.g. "99+"
        final watched = _watchedCollection(context);
        if (watched == null || !_unbounded.contains(watched)) continue;
        offenders.add(
          '${file.uri.pathSegments.last}:${i + 1} '
          "counts '$watched' by downloading it",
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These download a whole collection to show a number:\n'
          '  ${offenders.join('\n  ')}\n\n'
          'Use CountBuilder, which asks Firestore to count from the index.',
    );
  });
}
