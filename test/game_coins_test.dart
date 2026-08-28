// Ludo coins on the client.
//
// The balance itself is decided by a Cloud Function, so what is testable here
// is what the player SEES: whether the claim button is offered, how the count
// is written, and how far off the next chest is. The claim check is the one
// that matters — it mirrors the server's day arithmetic, and if the two
// disagree the button invites a tap the server silently refuses.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

/// A UTC instant for a given Pakistan-time wall clock. PKT is UTC+5.
DateTime pkt(int y, int m, int d, int hh, [int mm = 0]) =>
    DateTime.utc(y, m, d, hh, mm).subtract(const Duration(hours: 5));

GameProfile profileClaimedAt(DateTime t, {int streak = 1}) =>
    GameProfile.fromMap({
      'coins': 500,
      'streak': streak,
      'lastDailyAt': t.millisecondsSinceEpoch,
    });

void main() {
  group('coins are never formatted as money', () {
    test('grouped with commas, no currency symbol, no decimals', () {
      expect(formatCoins(0), '0');
      expect(formatCoins(500), '500');
      expect(formatCoins(1000), '1,000');
      expect(formatCoins(1234567), '1,234,567');
      for (final n in [0, 7, 1000, 999999]) {
        final s = formatCoins(n);
        expect(s, isNot(contains('PKR')));
        expect(s, isNot(contains('Rs')));
        expect(s, isNot(contains('.')));
      }
    });

    test('a negative count still reads sensibly', () {
      // Should never happen, but a minus sign is better than "-,100".
      expect(formatCoins(-1500), '-1,500');
    });
  });

  group('the daily claim mirrors the server day', () {
    test('a player who has never claimed can claim', () {
      expect(const GameProfile().canClaimDaily, isTrue);
    });

    test('a claim earlier the same Pakistan day blocks another', () {
      // Claimed 01:00 PKT today; it is now later today.
      final earlierToday = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      expect(profileClaimedAt(earlierToday).canClaimDaily, isFalse);
    });

    test('a claim yesterday allows one today', () {
      final yesterday = DateTime.now().toUtc().subtract(
        const Duration(days: 1, hours: 2),
      );
      expect(profileClaimedAt(yesterday).canClaimDaily, isTrue);
    });

    test('the day boundary is midnight in Pakistan, not UTC', () {
      // 23:30 PKT and 00:30 PKT are DIFFERENT days. Under UTC days they would
      // both fall on the same date, and a player claiming late at night would
      // be told to come back tomorrow when tomorrow had already started.
      final lateNight = pkt(2026, 8, 28, 23, 30);
      final afterMidnight = pkt(2026, 8, 29, 0, 30);
      expect(
        GameProfile.pktDayNumber(lateNight),
        isNot(GameProfile.pktDayNumber(afterMidnight)),
      );
      // ...and 01:00 with 05:00 PKT are the SAME day, which a UTC boundary
      // would wrongly split.
      expect(
        GameProfile.pktDayNumber(pkt(2026, 8, 28, 1)),
        GameProfile.pktDayNumber(pkt(2026, 8, 28, 5)),
      );
    });
  });

  group('chests', () {
    test('a new player is a full run away', () {
      expect(const GameProfile().winsToNextChest, kWinsPerChest);
    });

    test('the count comes down with each win', () {
      for (var w = 1; w < kWinsPerChest; w++) {
        final p = GameProfile.fromMap({'gamesWon': w});
        expect(p.winsToNextChest, kWinsPerChest - w, reason: '$w wins');
      }
    });

    test('landing exactly on a chest resets to a full run, never zero', () {
      // "Win 0 more games to earn a chest" would be nonsense on screen.
      for (final w in [kWinsPerChest, kWinsPerChest * 2, kWinsPerChest * 9]) {
        final p = GameProfile.fromMap({'gamesWon': w});
        expect(p.winsToNextChest, kWinsPerChest, reason: '$w wins');
        expect(p.winsToNextChest, greaterThan(0));
      }
    });

    test('it is never zero or negative for any number of wins', () {
      for (var w = 0; w < 50; w++) {
        final n = GameProfile.fromMap({'gamesWon': w}).winsToNextChest;
        expect(n, inInclusiveRange(1, kWinsPerChest), reason: '$w wins');
      }
    });
  });

  group('a missing or malformed profile does not break the screen', () {
    test('an absent document reads as a starting profile', () {
      final p = GameProfile.fromMap(null);
      expect(p.coins, kStartingCoins);
      expect(p.chests, 0);
      expect(p.canClaimDaily, isTrue);
    });

    test('an empty document reads as a starting profile', () {
      expect(GameProfile.fromMap(const {}).coins, kStartingCoins);
    });

    test('junk in the fields does not throw', () {
      final p = GameProfile.fromMap(const {
        'coins': 'lots',
        'streak': null,
        'chests': 'two',
        'lastDailyAt': 'yesterday',
      });
      expect(p.coins, kStartingCoins);
      expect(p.streak, 0);
      expect(p.chests, 0);
      expect(p.lastDailyAt, isNull);
      expect(p.canClaimDaily, isTrue);
    });
  });

  group('the client constants match the server', () {
    // These are duplicated across game_coins.dart and game_economy.js. Drift
    // would show the player a number the server does not agree with.
    test('starting coins and chest cadence are the documented values', () {
      expect(kStartingCoins, 500);
      expect(kWinsPerChest, 3);
    });
  });
}
