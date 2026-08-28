// A shared link that survives sign-in.
//
// The gap this closes: a link opened by somebody with no account used to say
// "sign in, then open the link again", which asks a person to go back and find
// the message a second time. Most will not. It applies to ad links as much as
// game invites — arguably more, since an ad link is what Google indexes and
// what a seller shares, so it is the front door for people who have never used
// PakBazar at all.
//
// The storage needs a device, so what is tested here is the expiry rule — which
// is where the two bad outcomes live. Too short and a person who stopped to
// create an account loses the invite anyway. Too long and a link followed last
// week hijacks today's launch, dropping somebody into a game that finished days
// ago.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  final now = DateTime(2026, 8, 28, 12);
  int at(Duration ago) => now.subtract(ago).millisecondsSinceEpoch;

  group('a remembered invite expires', () {
    test('one followed moments ago is honoured', () {
      expect(pendingInviteIsFresh(at(Duration.zero), now), isTrue);
      expect(pendingInviteIsFresh(at(const Duration(minutes: 2)), now), isTrue);
    });

    test('there is time to create an account and come back', () {
      // Signing up means an email, a password, possibly a verification mail.
      // Half an hour must not be too late.
      expect(pendingInviteIsFresh(at(const Duration(minutes: 30)), now), isTrue);
    });

    test('one from last week does not hijack this launch', () {
      expect(pendingInviteIsFresh(at(const Duration(days: 7)), now), isFalse);
    });

    test('the boundary is the stated TTL', () {
      expect(pendingInviteIsFresh(at(kPendingInviteTtl), now), isTrue);
      expect(
        pendingInviteIsFresh(
          at(kPendingInviteTtl + const Duration(minutes: 1)),
          now,
        ),
        isFalse,
      );
    });
  });

  group('bad values are not trusted', () {
    test('no timestamp is treated as expired, not as fresh', () {
      // A value written by an older build carries no way to tell its age, and
      // guessing "fresh" would fire a stale invite on some later launch.
      expect(pendingInviteIsFresh(null, now), isFalse);
    });

    test('a future timestamp is refused rather than trusted forever', () {
      // Clock skew. Treating it as fresh would make it fresh indefinitely.
      expect(
        pendingInviteIsFresh(
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          now,
        ),
        isFalse,
      );
    });

    test('zero and negative timestamps are expired', () {
      expect(pendingInviteIsFresh(0, now), isFalse);
      expect(pendingInviteIsFresh(-1, now), isFalse);
    });
  });

  group('a stored value resolves to the right destination', () {
    test('an ad route and a game route are kept as they are', () {
      expect(pendingRouteOf('/ad/abc123'), '/ad/abc123');
      expect(pendingRouteOf('/ludo/room789'), '/ludo/room789');
    });

    test('a bare id from an older build is still a Ludo room', () {
      // 1.0.79 stored the room id alone. Those values are sitting on devices
      // that have not updated yet, and dropping them would break the invite
      // flow for exactly the people mid-upgrade.
      expect(pendingRouteOf('room789'), '/ludo/room789');
    });

    test('every stored form resolves to a real screen', () {
      // generateAppRoute is what actually opens it, so a value that does not
      // resolve there would be silently discarded.
      for (final stored in ['/ad/abc', '/ludo/xyz', 'legacyRoomId']) {
        final route = pendingRouteOf(stored);
        expect(
          generateAppRoute(RouteSettings(name: route)),
          isNotNull,
          reason: '$stored resolved to a route nothing handles',
        );
      }
    });

    test('a route this build does not understand is dropped, not crashed on', () {
      expect(generateAppRoute(const RouteSettings(name: '/whatever/x')), isNull);
    });
  });

  group('the window itself', () {
    test('is long enough to be useful and short enough to be safe', () {
      expect(kPendingInviteTtl.inMinutes, greaterThanOrEqualTo(30));
      expect(kPendingInviteTtl.inHours, lessThanOrEqualTo(24));
    });
  });
}
