import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Prayer times are the one feature in this app where being quietly wrong is
// worse than being obviously broken: nobody double-checks a schedule, they just
// pray at the wrong time.
//
// So these tests do not compare the code against itself. They compare it
// against astronomy that is true independently of any implementation — the
// solstices, the equinoxes, the equation of time — and against the longitude
// arithmetic anyone can do on paper.

void main() {
  group('the astronomy is right, independent of this code', () {
    // Declination is the sun's angle above the celestial equator. Its extremes
    // are the solstices at ±23.44°, and it passes through zero at the
    // equinoxes. Any error in the ecliptic maths shows up here immediately.
    test('solar declination hits the solstices and equinoxes', () {
      double declOn(int y, int m, int d) =>
          sunPosition(julianDay(y, m, d) + 0.5).declination;

      expect(declOn(2026, 6, 21), closeTo(23.44, 0.2), reason: 'June solstice');
      expect(
        declOn(2026, 12, 21),
        closeTo(-23.44, 0.2),
        reason: 'December solstice',
      );
      expect(declOn(2026, 3, 20), closeTo(0, 0.6), reason: 'March equinox');
      expect(
        declOn(2026, 9, 23),
        closeTo(0, 0.6),
        reason: 'September equinox',
      );
    });

    // The equation of time is how far true solar noon drifts from mean noon.
    // It is a fixed annual curve: about +16 minutes in early November, about
    // -14 in mid February, and near zero four times a year.
    test('the equation of time follows its known annual curve', () {
      double eqtMinutes(int y, int m, int d) =>
          sunPosition(julianDay(y, m, d) + 0.5).equationOfTime * 60;

      expect(
        eqtMinutes(2026, 11, 3),
        closeTo(16.4, 1.0),
        reason: 'early-November maximum',
      );
      expect(
        eqtMinutes(2026, 2, 11),
        closeTo(-14.2, 1.0),
        reason: 'mid-February minimum',
      );
      expect(eqtMinutes(2026, 4, 15), closeTo(0, 1.5));
      expect(eqtMinutes(2026, 9, 1), closeTo(0, 1.5));
    });
  });

  group('Pakistan wall-clock arithmetic', () {
    // Pakistan Standard Time is UTC+5, i.e. the 75°E meridian. Karachi sits at
    // 67.0°E — eight degrees west — so the sun crosses its meridian
    // (75 - 67.0011) / 15 = 0.533h = 32 minutes AFTER the clock says noon.
    // Dhuhr must therefore land near 12:32, offset by the equation of time.
    test('Dhuhr in Karachi lands where the longitude says it must', () {
      for (final d in [
        DateTime(2026, 1, 15),
        DateTime(2026, 4, 15),
        DateTime(2026, 7, 15),
        DateTime(2026, 10, 15),
      ]) {
        final t = computePrayerTimes(
          date: d,
          location: kPakistanPrayerCities.first,
        );
        final eqtMin = sunPosition(
              julianDay(d.year, d.month, d.day) + 0.5,
            ).equationOfTime *
            60;
        final expected = 12 * 60 + 32 - eqtMin + 1; // +1: timetable convention
        final actual = t.dhuhr.hour * 60 + t.dhuhr.minute;
        expect(
          actual.toDouble(),
          closeTo(expected, 2),
          reason: 'Karachi Dhuhr on $d',
        );
      }
    });

    // Lahore is at 74.36°E, practically on the meridian, so its Dhuhr is only
    // ~2.6 minutes after clock noon — roughly half an hour earlier than
    // Karachi's on the same day. A sign error in the longitude shift would
    // reverse this.
    test('Lahore Dhuhr precedes Karachi Dhuhr by about half an hour', () {
      final date = DateTime(2026, 8, 27);
      final khi = computePrayerTimes(
        date: date,
        location: kPakistanPrayerCities.firstWhere((c) => c.name == 'Karachi'),
      );
      final lhr = computePrayerTimes(
        date: date,
        location: kPakistanPrayerCities.firstWhere((c) => c.name == 'Lahore'),
      );
      final gap = khi.dhuhr.difference(lhr.dhuhr).inMinutes;
      expect(gap, inInclusiveRange(27, 33));
    });
  });

  group('the schedule is internally coherent', () {
    final cities = kPakistanPrayerCities.take(12);
    final dates = [
      DateTime(2026, 1, 1),
      DateTime(2026, 6, 21), // longest day
      DateTime(2026, 12, 21), // shortest day
      DateTime(2026, 8, 27),
    ];

    test('prayers occur in order, every city, every season', () {
      for (final c in cities) {
        for (final d in dates) {
          final t = computePrayerTimes(date: d, location: c);
          final order = [
            t.fajr,
            t.sunrise,
            t.dhuhr,
            t.asr,
            t.maghrib,
            t.isha,
          ];
          for (var i = 1; i < order.length; i++) {
            expect(
              order[i].isAfter(order[i - 1]),
              isTrue,
              reason: '${c.name} on $d: ${order[i]} should follow ${order[i - 1]}',
            );
          }
        }
      }
    });

    // Fajr and Isha use the same 18° depression, so Fajr sits as far before
    // sunrise as Isha sits after sunset — the day is symmetric about noon.
    test('Fajr and Isha are symmetric about the solar day', () {
      for (final c in cities) {
        for (final d in dates) {
          final t = computePrayerTimes(date: d, location: c);
          final beforeSunrise = t.sunrise.difference(t.fajr).inMinutes;
          final afterSunset = t.isha.difference(t.maghrib).inMinutes;
          expect(
            (beforeSunrise - afterSunset).abs(),
            lessThanOrEqualTo(6),
            reason: '${c.name} on $d: $beforeSunrise vs $afterSunset',
          );
        }
      }
    });

    // The whole point of offering the choice: the Hanafi shadow factor of 2
    // always puts Asr later than the Shafi'i factor of 1.
    test('Hanafi Asr is always later than Shafi\'i Asr', () {
      for (final c in cities) {
        for (final d in dates) {
          final hanafi = computePrayerTimes(date: d, location: c);
          final shafi = computePrayerTimes(
            date: d,
            location: c,
            asr: AsrSchool.shafi,
          );
          expect(
            hanafi.asr.isAfter(shafi.asr),
            isTrue,
            reason: '${c.name} on $d',
          );
        }
      }
    });

    // Daylight is longest at the June solstice and shortest in December, and
    // the swing is larger the further north you go. Gilgit (35.9°N) must show
    // a bigger spread than Karachi (24.9°N).
    test('day length varies with season and latitude the right way', () {
      int daylight(PrayerLocation c, DateTime d) {
        final t = computePrayerTimes(date: d, location: c);
        return t.maghrib.difference(t.sunrise).inMinutes;
      }

      final khi = kPakistanPrayerCities.firstWhere((c) => c.name == 'Karachi');
      final gil = kPakistanPrayerCities.firstWhere((c) => c.name == 'Gilgit');
      final june = DateTime(2026, 6, 21);
      final dec = DateTime(2026, 12, 21);

      expect(daylight(khi, june), greaterThan(daylight(khi, dec)));
      expect(daylight(gil, june), greaterThan(daylight(gil, dec)));
      expect(
        daylight(gil, june) - daylight(gil, dec),
        greaterThan(daylight(khi, june) - daylight(khi, dec)),
        reason: 'the seasonal swing grows with latitude',
      );
    });
  });

  group('nextAfter', () {
    final t = computePrayerTimes(
      date: DateTime(2026, 8, 27),
      location: kPakistanPrayerCities.first,
    );

    test('never returns sunrise, which is not a prayer', () {
      final justBeforeSunrise = t.sunrise.subtract(const Duration(minutes: 1));
      expect(t.nextAfter(justBeforeSunrise)?.key, 'dhuhr');
    });

    test('returns the upcoming prayer through the day', () {
      expect(t.nextAfter(t.date)?.key, 'fajr');
      expect(t.nextAfter(t.dhuhr)?.key, 'asr');
      expect(t.nextAfter(t.maghrib)?.key, 'isha');
    });

    // After Isha there is nothing left today; the caller shows tomorrow's Fajr
    // rather than this silently wrapping to a time that has already passed.
    test('is null once Isha has gone', () {
      expect(t.nextAfter(t.isha.add(const Duration(minutes: 1))), isNull);
    });
  });

  group('the bundled city list', () {
    test('covers the country without a bad coordinate', () {
      expect(kPakistanPrayerCities.length, greaterThanOrEqualTo(40));
      for (final c in kPakistanPrayerCities) {
        expect(c.latitude, inInclusiveRange(23.5, 37.1), reason: c.name);
        expect(c.longitude, inInclusiveRange(60.8, 77.9), reason: c.name);
        expect(c.name.trim(), isNotEmpty);
      }
    });

    test('has no duplicates', () {
      final names = kPakistanPrayerCities.map((c) => c.name).toSet();
      expect(names.length, kPakistanPrayerCities.length);
    });
  });
}
