part of '../main.dart';

// Prayer times for Pakistan.
//
// Computed on the device from the sun's position — no API, no network, works
// in a village with no signal. That matters more than it might seem: a prayer
// schedule that needs connectivity is useless at exactly the moments people
// reach for it.
//
// The astronomy is the standard sunrise/sunset equation set (the same one
// PrayTimes and every mainstream prayer app implement). What makes it correct
// for Pakistan specifically is the two conventions below:
//
//  * ANGLES — University of Islamic Sciences, Karachi: Fajr and Isha both at
//    18° below the horizon. This is the method Pakistani mosques and the
//    Ministry of Religious Affairs publish against.
//  * ASR — Hanafi by default (shadow = object length x2 + noon shadow), which
//    is the majority school in Pakistan. Shafi'i (x1) is offered because it is
//    what many Ahl-e-Hadith and overseas users follow, and getting Asr wrong
//    by an hour is not a rounding error.
//
// Deliberately NOT included: any claim that these are authoritative. Local
// mosque timetables differ by a minute or two and, for Fajr and Isha
// especially, communities follow their own masjid. The UI says so.

/// The six daily times, plus sunrise, for one date and place.
class PrayerTimes {
  const PrayerTimes({
    required this.date,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final DateTime date;
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  /// In the order they occur. Sunrise is included because it closes the Fajr
  /// window, which is the thing people actually need to know at dawn.
  List<({String key, String name, String urdu, DateTime at})> get schedule => [
    (key: 'fajr', name: 'Fajr', urdu: 'فجر', at: fajr),
    (key: 'sunrise', name: 'Sunrise', urdu: 'طلوعِ آفتاب', at: sunrise),
    (key: 'dhuhr', name: 'Dhuhr', urdu: 'ظہر', at: dhuhr),
    (key: 'asr', name: 'Asr', urdu: 'عصر', at: asr),
    (key: 'maghrib', name: 'Maghrib', urdu: 'مغرب', at: maghrib),
    (key: 'isha', name: 'Isha', urdu: 'عشاء', at: isha),
  ];

  /// The next prayer after [from], skipping sunrise (it is not a prayer).
  /// Returns null when Isha has passed — the caller shows tomorrow's Fajr.
  ({String key, String name, String urdu, DateTime at})? nextAfter(
    DateTime from,
  ) {
    for (final p in schedule) {
      if (p.key == 'sunrise') continue;
      if (p.at.isAfter(from)) return p;
    }
    return null;
  }
}

/// Which shadow length starts Asr. The two schools genuinely differ here by
/// roughly an hour in summer, so this is a user choice, not a default to bury.
enum AsrSchool {
  hanafi('Hanafi', 'حنفی', 2),
  shafi('Shafi\'i / Hanbali / Maliki', 'شافعی', 1);

  const AsrSchool(this.label, this.urdu, this.shadowFactor);
  final String label;
  final String urdu;
  final int shadowFactor;
}

/// A place to compute for.
class PrayerLocation {
  const PrayerLocation(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
}

/// Pakistan is UTC+5 year-round — no daylight saving since the 2009
/// experiment was abandoned, so this is a constant rather than a lookup.
const double kPakistanUtcOffsetHours = 5;

/// Fajr/Isha depression angle, University of Islamic Sciences Karachi.
const double kKarachiFajrAngle = 18;
const double kKarachiIshaAngle = 18;

/// Major Pakistani cities with coordinates, for users who would rather pick a
/// city than grant location access. Ordered by population so the list opens on
/// something useful.
const List<PrayerLocation> kPakistanPrayerCities = [
  PrayerLocation('Karachi', 24.8607, 67.0011),
  PrayerLocation('Lahore', 31.5204, 74.3587),
  PrayerLocation('Faisalabad', 31.4187, 73.0791),
  PrayerLocation('Rawalpindi', 33.5651, 73.0169),
  PrayerLocation('Islamabad', 33.6844, 73.0479),
  PrayerLocation('Gujranwala', 32.1877, 74.1945),
  PrayerLocation('Peshawar', 34.0151, 71.5249),
  PrayerLocation('Multan', 30.1575, 71.5249),
  PrayerLocation('Hyderabad', 25.3960, 68.3578),
  PrayerLocation('Quetta', 30.1798, 66.9750),
  PrayerLocation('Bahawalpur', 29.3956, 71.6836),
  PrayerLocation('Sargodha', 32.0836, 72.6711),
  PrayerLocation('Sialkot', 32.4945, 74.5229),
  PrayerLocation('Sukkur', 27.7052, 68.8574),
  PrayerLocation('Larkana', 27.5590, 68.2120),
  PrayerLocation('Sheikhupura', 31.7131, 73.9783),
  PrayerLocation('Mardan', 34.1989, 72.0231),
  PrayerLocation('Gujrat', 32.5731, 74.0789),
  PrayerLocation('Kasur', 31.1179, 74.4408),
  PrayerLocation('Rahim Yar Khan', 28.4202, 70.2952),
  PrayerLocation('Sahiwal', 30.6682, 73.1114),
  PrayerLocation('Okara', 30.8100, 73.4597),
  PrayerLocation('Wah Cantonment', 33.7960, 72.7089),
  PrayerLocation('Dera Ghazi Khan', 30.0489, 70.6455),
  PrayerLocation('Mingora', 34.7795, 72.3603),
  PrayerLocation('Nawabshah', 26.2442, 68.4100),
  PrayerLocation('Chiniot', 31.7200, 72.9784),
  PrayerLocation('Kotri', 25.3660, 68.3080),
  PrayerLocation('Khanpur', 28.6453, 70.6567),
  PrayerLocation('Hafizabad', 32.0709, 73.6880),
  PrayerLocation('Kohat', 33.5889, 71.4432),
  PrayerLocation('Jhang', 31.2781, 72.3317),
  PrayerLocation('Muzaffargarh', 30.0736, 71.1805),
  PrayerLocation('Khanewal', 30.3017, 71.9321),
  PrayerLocation('Abbottabad', 34.1688, 73.2215),
  PrayerLocation('Mirpur Khas', 25.5276, 69.0116),
  PrayerLocation('Jacobabad', 28.2769, 68.4514),
  PrayerLocation('Attock', 33.7660, 72.3609),
  PrayerLocation('Gilgit', 35.9208, 74.3144),
  PrayerLocation('Muzaffarabad', 34.3700, 73.4711),
];

// ---------------------------------------------------------------------------
// Astronomy
// ---------------------------------------------------------------------------

double _dtr(double d) => d * math.pi / 180.0;
double _rtd(double r) => r * 180.0 / math.pi;
double _sin(double d) => math.sin(_dtr(d));
double _cos(double d) => math.cos(_dtr(d));
double _tan(double d) => math.tan(_dtr(d));
double _arcsin(double x) => _rtd(math.asin(x));
double _arccos(double x) => _rtd(math.acos(x));
double _arctan2(double y, double x) => _rtd(math.atan2(y, x));
double _arccot(double x) => _rtd(math.atan2(1.0, x));

double _wrap(double a, double b) {
  final r = a - b * (a / b).floorToDouble();
  return r < 0 ? r + b : r;
}

double _fixAngle(double a) => _wrap(a, 360);
double _fixHour(double a) => _wrap(a, 24);

/// Julian day at 00:00 UT for a civil date.
double julianDay(int year, int month, int day) {
  var y = year;
  var m = month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floorToDouble();
  final b = 2 - a + (a / 4).floorToDouble();
  return (365.25 * (y + 4716)).floorToDouble() +
      (30.6001 * (m + 1)).floorToDouble() +
      day +
      b -
      1524.5;
}

/// Sun's declination and the equation of time for a Julian day.
({double declination, double equationOfTime}) sunPosition(double jd) {
  final d = jd - 2451545.0;
  final g = _fixAngle(357.529 + 0.98560028 * d); // mean anomaly
  final q = _fixAngle(280.459 + 0.98564736 * d); // mean longitude
  final l = _fixAngle(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g)); // ecliptic
  final e = 23.439 - 0.00000036 * d; // obliquity
  final ra = _fixHour(_arctan2(_cos(e) * _sin(l), _cos(l)) / 15.0);
  return (
    declination: _arcsin(_sin(e) * _sin(l)),
    equationOfTime: q / 15.0 - ra,
  );
}

/// Local solar noon, in hours, for a day portion [t].
double _midDay(double jd, double t) =>
    _fixHour(12 - sunPosition(jd + t).equationOfTime);

/// Hours at which the sun sits [angle] degrees below the horizon.
/// Null in the polar case where it never does — irrelevant for Pakistan, but
/// returning null beats returning a NaN that renders as "NaN:NaN".
double? _sunAngleTime(
  double jd,
  double t,
  double angle,
  double latitude, {
  required bool afternoon,
}) {
  final decl = sunPosition(jd + t).declination;
  final ratio =
      (-_sin(angle) - _sin(decl) * _sin(latitude)) /
      (_cos(decl) * _cos(latitude));
  if (ratio.isNaN || ratio > 1 || ratio < -1) return null;
  final h = _arccos(ratio) / 15.0;
  final noon = _midDay(jd, t);
  return afternoon ? noon + h : noon - h;
}

double? _asrAngleTime(double jd, double t, int factor, double latitude) {
  final decl = sunPosition(jd + t).declination;
  final angle = -_arccot(factor + _tan((latitude - decl).abs()));
  return _sunAngleTime(jd, t, angle, latitude, afternoon: true);
}

/// Computes the day's times for [location] on [date].
///
/// [date] is interpreted as a local Pakistan date; the result is returned as
/// local DateTimes on that same date.
PrayerTimes computePrayerTimes({
  required DateTime date,
  required PrayerLocation location,
  AsrSchool asr = AsrSchool.hanafi,
  double utcOffsetHours = kPakistanUtcOffsetHours,
  double fajrAngle = kKarachiFajrAngle,
  double ishaAngle = kKarachiIshaAngle,
}) {
  final jd =
      julianDay(date.year, date.month, date.day) - location.longitude / 360.0;
  final lat = location.latitude;

  // Two passes. The sun's position depends on the time of day, which is what
  // we are solving for, so the first pass uses a rough guess and the second
  // refines it. Further passes move the answer by well under a second.
  double refine(double? Function(double t) f, double guessHours) {
    var t = guessHours / 24.0;
    for (var i = 0; i < 2; i++) {
      final v = f(t);
      if (v == null) return double.nan;
      t = v / 24.0;
    }
    final v = f(t);
    return v ?? double.nan;
  }

  final fajrH = refine(
    (t) => _sunAngleTime(jd, t, fajrAngle, lat, afternoon: false),
    5,
  );
  final sunriseH = refine(
    (t) => _sunAngleTime(jd, t, 0.833, lat, afternoon: false),
    6,
  );
  final dhuhrH = refine((t) => _midDay(jd, t), 12);
  final asrH = refine((t) => _asrAngleTime(jd, t, asr.shadowFactor, lat), 13);
  final maghribH = refine(
    (t) => _sunAngleTime(jd, t, 0.833, lat, afternoon: true),
    18,
  );
  final ishaH = refine(
    (t) => _sunAngleTime(jd, t, ishaAngle, lat, afternoon: true),
    18,
  );

  // Everything above is in local solar hours; shift onto the wall clock.
  final shift = utcOffsetHours - location.longitude / 15.0;
  DateTime at(double hours) {
    if (hours.isNaN) return DateTime(date.year, date.month, date.day);
    final total = (hours + shift) * 60.0;
    // Round to the minute the way a printed timetable does.
    final minutes = total.round();
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: minutes));
  }

  return PrayerTimes(
    date: DateTime(date.year, date.month, date.day),
    fajr: at(fajrH),
    sunrise: at(sunriseH),
    dhuhr: at(dhuhrH + 1 / 60), // a minute past true noon, as timetables do
    asr: at(asrH),
    maghrib: at(maghribH),
    isha: at(ishaH),
  );
}
