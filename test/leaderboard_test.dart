// Weekly Ludo standings.
//
// The week id is the thing worth testing, and it is a MIRROR: the server writes
// each player's row under its own week id and this screen reads them back under
// ours. If the two ever disagree, the leaderboard is simply empty — no error,
// no crash, just a table nobody appears on, which is close to impossible to
// diagnose from the outside.
//
// The reference values below were produced by game_economy.js and pasted in on
// purpose. A test that recomputed them with the same arithmetic would agree
// with itself no matter how wrong both sides were.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

void main() {
  group('the week id matches the server', () {
    test('known values from game_economy.js', () {
      // Verified against node: weekIdOf(Date.UTC(...)) for each of these.
      expect(ludoWeekId(utc(2026, 1, 1)), '2025-W52');
      expect(ludoWeekId(utc(2026, 6, 15)), '2026-W24');
      expect(ludoWeekId(utc(2026, 12, 31)), '2026-W52');
    });

    test('the format is a sortable, zero-padded string', () {
      // Used as a document id and ordered as text, so the padding is not
      // cosmetic: W9 would sort after W10.
      for (final d in [1, 60, 120, 200, 300, 360]) {
        final id = ludoWeekId(utc(2026, 1, 1).add(Duration(days: d)));
        expect(RegExp(r'^\d{4}-W\d{2}$').hasMatch(id), isTrue, reason: id);
      }
    });
  });

  group('a week runs Monday to Sunday in Pakistan time', () {
    test('midnight Monday PKT starts a new week', () {
      // Sunday 23:00 PKT and Monday 01:00 PKT are different weeks. A UTC week
      // would roll at 5am Monday PKT and swallow Sunday evening, which is when
      // people actually play.
      final sundayNight = utc(2026, 8, 30, 18);
      final mondayEarly = utc(2026, 8, 30, 20);
      expect(ludoWeekId(sundayNight), isNot(ludoWeekId(mondayEarly)));
    });

    test('01:00 and 06:00 Monday PKT are the same week', () {
      expect(
        ludoWeekId(utc(2026, 8, 30, 20)),
        ludoWeekId(utc(2026, 8, 31, 1)),
      );
    });

    test('all seven days of a week share one id', () {
      final monday = utc(2026, 8, 30, 20); // Mon 01:00 PKT
      final id = ludoWeekId(monday);
      for (var d = 0; d < 7; d++) {
        expect(
          ludoWeekId(monday.add(Duration(days: d))),
          id,
          reason: 'day $d fell outside its week',
        );
      }
      expect(ludoWeekId(monday.add(const Duration(days: 7))), isNot(id));
    });

    test('over a year, the id only ever changes on a Monday', () {
      // The failure this catches would split one week across two documents.
      var changes = 0;
      String? prev;
      for (var d = 0; d < 400; d++) {
        final when = utc(2026, 1, 1).add(Duration(days: d));
        final id = ludoWeekId(when);
        if (prev != null && id != prev) {
          changes++;
          // Monday in Pakistan time.
          final pkt = when.add(const Duration(hours: 5));
          expect(
            pkt.weekday,
            DateTime.monday,
            reason: 'week changed on ${pkt.weekday} at $when',
          );
        }
        prev = id;
      }
      expect(changes, greaterThan(50));
      expect(changes, lessThan(60));
    });
  });

  group('stake tiers match the server', () {
    test('the same ladder as STAKE_TIERS in game_economy.js', () {
      expect(kLudoStakeTiers, [0, 100, 500, 2000, 10000]);
    });

    test('free is first, so a table costs nothing by default', () {
      expect(kLudoStakeTiers.first, 0);
    });

    test('the ladder only goes up', () {
      for (var i = 1; i < kLudoStakeTiers.length; i++) {
        expect(kLudoStakeTiers[i], greaterThan(kLudoStakeTiers[i - 1]));
      }
    });
  });

  group('a leaderboard row survives bad data', () {
    test('a missing document reads as an empty row', () {
      final e = LeaderboardEntry.fromMap('u1', null);
      expect(e.userId, 'u1');
      expect(e.coinsWon, 0);
      expect(e.name, 'Player');
    });

    test('junk in the counters does not throw', () {
      final e = LeaderboardEntry.fromMap('u1', const {
        'coinsWon': 'many',
        'wins': null,
        'games': [1, 2],
      });
      expect(e.coinsWon, 0);
      expect(e.wins, 0);
      expect(e.games, 0);
    });
  });
}
