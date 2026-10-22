import 'dart:math' as math;

/// Self-contained prayer-time calculator (no external package/network
/// dependency) tuned for Indonesia's Kemenag settings:
/// Fajr 20°, Isha 18°, Asr = Shafi'i.
class PrayerTimes {
  static const double klatenLat = -7.7061;
  static const double klatenLng = 110.6042;
  static const double klatenTimezoneOffset = 7.0; // WIB, UTC+7

  static const double fajrAngle = 20.0;
  static const double ishaAngle = 18.0;

  static const _labels = ['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

  static Map<String, DateTime> forDay({
    DateTime? date,
    double lat = klatenLat,
    double lng = klatenLng,
    double tzOffset = klatenTimezoneOffset,
  }) {
    final d = date ?? DateTime.now();
    final jd = _julianDate(d.year, d.month, d.day);

    final eqt = _equationOfTime(jd);
    final decl = _sunDeclination(jd);

    // Dhuhr (Jam tengah hari dalam UTC)
    // 12 + TimezoneOffset - Longitude/15 - EquationOfTime
    final dhuhr = 12 + tzOffset - (lng / 15) - eqt;

    // Sudut terbit/terbenam matahari dengan refraksi atmosfer (~0.833°)
    final sunriseAngle = 0.833 + 0.0347 * math.sqrt(_elevationApprox());

    // Fungsi kalkulasi selisih jam dari Dhuhr
    double hourAngle(double angle) {
      final val = (-_sin(angle) - _sin(lat) * _sin(decl)) / (_cos(lat) * _cos(decl));
      if (val < -1.0 || val > 1.0) return 0;
      return _arccos(val) / 15.0;
    }

    final fajrTime = dhuhr - hourAngle(fajrAngle);
    final sunriseTime = dhuhr - hourAngle(sunriseAngle);
    
    // Asr (Metode Syafi'i factor = 1.0)
    final asrAngle = -_arccot(1.0 + _tan((lat - decl).abs()));
    final asrTime = dhuhr + hourAngle(asrAngle);

    final maghribTime = dhuhr + hourAngle(sunriseAngle);
    final ishaTime = dhuhr + hourAngle(ishaAngle);

    final values = [fajrTime, sunriseTime, dhuhr, asrTime, maghribTime, ishaTime];
    final result = <String, DateTime>{};

    for (var i = 0; i < _labels.length; i++) {
      result[_labels[i]] = _hoursToDateTime(d, values[i]);
    }
    return result;
  }

  static MapEntry<String, DateTime> nextPrayer([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = forDay(date: n);
    for (final label in ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha']) {
      final t = today[label]!;
      if (t.isAfter(n)) return MapEntry(label, t);
    }
    final tomorrow = forDay(date: n.add(const Duration(days: 1)));
    return MapEntry('Fajr', tomorrow['Fajr']!);
  }

  // ---- internal solar math --------------------------------------------------
  static double _julianDate(int year, int month, int day) {
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor() + (30.6001 * (month + 1)).floor() + day + b - 1524.5;
  }

  static double _elevationApprox() => 150; // Meter dpl Klaten

  static double _sunDeclination(double jd) {
    final d = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g));
    final e = 23.439 - 0.00000036 * d;
    return _arcsin(_sin(e) * _sin(l));
  }

  static double _equationOfTime(double jd) {
    final d = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g));
    final e = 23.439 - 0.00000036 * d;
    var ra = _arctan2(_cos(e) * _sin(l), _cos(l)) / 15;
    ra = _fixHour(ra);
    return (q / 15) - ra;
  }

  static DateTime _hoursToDateTime(DateTime baseDate, double hours) {
    final h = hours.floor();
    final remainderMinutes = (hours - h) * 60;
    final m = remainderMinutes.floor();
    final s = ((remainderMinutes - m) * 60).round();

    return DateTime(baseDate.year, baseDate.month, baseDate.day, h, m, s);
  }

  // ---- Trigonometri Helper --------------------------------------------------
  static double _dtr(double d) => d * math.pi / 180.0;
  static double _rtd(double r) => r * 180.0 / math.pi;
  static double _sin(double d) => math.sin(_dtr(d));
  static double _cos(double d) => math.cos(_dtr(d));
  static double _tan(double d) => math.tan(_dtr(d));
  static double _arcsin(double x) => _rtd(math.asin(x.clamp(-1.0, 1.0)));
  static double _arccos(double x) => _rtd(math.acos(x.clamp(-1.0, 1.0)));
  static double _arctan2(double y, double x) => _rtd(math.atan2(y, x));
  static double _arccot(double x) => _rtd(math.atan2(1, x));
  static double _fixAngle(double a) => a - 360.0 * (a / 360.0).floor();
  static double _fixHour(double h) => h - 24.0 * (h / 24.0).floor();
}