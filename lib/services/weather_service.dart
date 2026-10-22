import 'dart:convert';
import 'package:http/http.dart' as http;
import 'prayer_service.dart';

class WeatherInfo {
  final double tempC;
  final int weatherCode;
  final double windKph;
  final String description;

  const WeatherInfo({
    required this.tempC,
    required this.weatherCode,
    required this.windKph,
    required this.description,
  });
}

/// Realtime weather for Klaten via Open-Meteo — no API key required.
/// This call goes directly from the phone to Open-Meteo (not through the
/// server-agent), so weather still shows even if the monitored server
/// itself is offline.
class WeatherService {
  static const _url =
      'https://api.open-meteo.com/v1/forecast?latitude=${PrayerTimes.klatenLat}&longitude=${PrayerTimes.klatenLng}&current_weather=true&timezone=Asia%2FJakarta';

  static Future<WeatherInfo> fetchKlaten() async {
    final res = await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Weather request failed (${res.statusCode})');
    final body = jsonDecode(res.body);
    final current = body['current_weather'];
    final code = (current['weathercode'] as num).toInt();
    return WeatherInfo(
      tempC: (current['temperature'] as num).toDouble(),
      weatherCode: code,
      windKph: (current['windspeed'] as num).toDouble(),
      description: _describe(code),
    );
  }

  static String _describe(int code) {
    if (code == 0) return 'Cerah';
    if ([1, 2, 3].contains(code)) return 'Berawan';
    if ([45, 48].contains(code)) return 'Berkabut';
    if ([51, 53, 55, 56, 57].contains(code)) return 'Gerimis';
    if ([61, 63, 65, 66, 67, 80, 81, 82].contains(code)) return 'Hujan';
    if ([71, 73, 75, 77, 85, 86].contains(code)) return 'Salju';
    if ([95, 96, 99].contains(code)) return 'Badai Petir';
    return 'Tidak diketahui';
  }
}
