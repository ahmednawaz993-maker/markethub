// Which sellers the followed-ads rail asks about.
//
// The follow list used to be read from a subcollection — thirty document reads
// on every launch and every resume, to answer a question that is almost always
// "the same four sellers as last time". The ids now ride on the profile
// document the session already fetches, so the list costs nothing.
//
// The trimming is the part that can go wrong quietly. Firestore's `whereIn`
// takes at most thirty values and REJECTS a longer list outright, so a user who
// follows thirty-one sellers would get no rail at all rather than a shorter
// one — and it would be the enthusiastic users, the ones who follow the most
// sellers, who lost the feature.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  test('a short list is used whole', () {
    expect(followedIdsFrom(['a', 'b', 'c']), ['a', 'b', 'c']);
  });

  test('an empty or absent list asks about nobody', () {
    expect(followedIdsFrom([]), isEmpty);
  });

  test('a list at the limit is still used whole', () {
    final ids = List.generate(30, (i) => 'seller$i');
    expect(followedIdsFrom(ids), hasLength(30));
    expect(followedIdsFrom(ids).last, 'seller29');
  });

  test('a list over the limit is trimmed to exactly the limit', () {
    // Left untrimmed, whereIn rejects the query and the rail vanishes.
    final ids = List.generate(100, (i) => 'seller$i');
    expect(followedIdsFrom(ids), hasLength(30));
  });

  test('trimming keeps the RECENT follows, not the oldest', () {
    // arrayUnion appends, so the newest follow is at the tail. Trimming the
    // wrong end would show somebody the thirty sellers they cared about least
    // — and it would look like the feature simply picking badly, not a bug.
    final ids = List.generate(100, (i) => 'seller$i');
    final kept = followedIdsFrom(ids);
    expect(kept.first, 'seller70');
    expect(kept.last, 'seller99');
  });

  test('rubbish in the array does not become a query value', () {
    // A null or empty id in a whereIn is a wasted slot at best.
    expect(followedIdsFrom(['a', null, '', 'b']), ['a', 'b']);
  });

  test('a duplicated follow does not waste one of the thirty slots', () {
    expect(followedIdsFrom(['a', 'b', 'a', 'c']), ['a', 'b', 'c']);
  });

  test('ids that are not strings are still usable', () {
    expect(followedIdsFrom([123, 'b']), ['123', 'b']);
  });

  test('the cap matches what whereIn actually accepts', () {
    // If Firestore ever raised its limit and this constant were bumped past
    // it, every followed-sellers rail in the app would start failing at once.
    expect(UserSession.maxFollowsQueried, lessThanOrEqualTo(30));
  });
}
