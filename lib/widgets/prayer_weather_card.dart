import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_style.dart';
import '../services/prayer_service.dart';
import '../services/media_prefs.dart';
import '../services/weather_service.dart';

/// Jadwal Sholat (Klaten, Jawa Tengah) + realtime weather + a live countdown
/// to the next prayer. Rendered over a futuristic gold/orange gradient
/// background (falls back to a pure gradient if assets/images/prayer_bg.jpg
/// isn't supplied) so the card stays legible and on-theme either way.
class PrayerWeatherCard extends StatefulWidget {
  const PrayerWeatherCard({super.key});

  @override
  State<PrayerWeatherCard> createState() => _PrayerWeatherCardState();
}

class _PrayerWeatherCardState extends State<PrayerWeatherCard> {
  Timer? _ticker;
  WeatherInfo? _weather;
  String? _weatherError;
  late MapEntry<String, DateTime> _next;
  MediaMode _bgMode = MediaMode.standard;
  String? _bgPath;

  @override
  void initState() {
    super.initState();
    _next = PrayerTimes.nextPrayer();
    MediaPrefs.changes.addListener(_loadBg);
    _loadBg();
    _loadWeather();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _next = PrayerTimes.nextPrayer());
    });
  }

  Future<void> _loadBg() async {
    final m = await MediaPrefs.prayerMode();
    final p = m == MediaMode.custom ? await MediaPrefs.prayerPath() : null;
    if (mounted) setState(() { _bgMode = m; _bgPath = p; });
  }

  /// Gambar latar kartu: pilihan user (di-decode kecil agar hemat memori) /
  /// aset bawaan / tanpa gambar (hanya gradien).
  DecorationImage? _bgImage() {
    if (_bgMode == MediaMode.off) return null;
    if (_bgMode == MediaMode.custom && _bgPath != null) {
      return DecorationImage(
        image: ResizeImage(FileImage(File(_bgPath!)), width: 900),
        fit: BoxFit.cover,
        onError: (_, __) {},
      );
    }
    return DecorationImage(
      image: const AssetImage('assets/images/prayer_bg.jpg'),
      fit: BoxFit.cover,
      onError: (_, __) {}, // aset opsional — jatuh ke gradien bila tidak ada
    );
  }

  Future<void> _loadWeather() async {
    try {
      final w = await WeatherService.fetchKlaten();
      if (mounted) setState(() => _weather = w);
    } catch (e) {
      if (mounted) setState(() => _weatherError = e.toString());
    }
  }

  @override
  void dispose() {
    MediaPrefs.changes.removeListener(_loadBg);
    _ticker?.cancel();
    super.dispose();
  }

  String _countdown() {
    final d = _next.value.difference(DateTime.now());
    if (d.isNegative) return '--:--:--';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final today = PrayerTimes.forDay();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: AppStyleKit.isNeo
              ? Border.all(color: AppStyleKit.neoInk, width: 2.5)
              : Border.all(color: AppColors.neonGold.withOpacity(AppStyleKit.isMinimal ? 0.25 : 0.5), width: AppStyleKit.isMinimal ? 1 : 1.3),
          boxShadow: AppStyleKit.isGlass ? [BoxShadow(color: AppColors.neonGold.withOpacity(0.25), blurRadius: 22, spreadRadius: -2)] : [],
          image: _bgImage(),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF241300), Color(0xFF120A05), Color(0xFF08080A)],
          ),
        ),
        child: Container(
          // Gradient overlay for contrast, regardless of whether the
          // background image asset is present.
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.bgTop.withOpacity(0.55), AppColors.bgTop.withOpacity(0.75)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Jadwal Sholat — Klaten', style: AppTheme.orbitron.copyWith(color: AppColors.neonGold, fontSize: 13, fontWeight: FontWeight.w700)),
                  _weatherPill(),
                ],
              ),
              const SizedBox(height: 12),
              Text('Menuju ${_next.key}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Text(_countdown(), style: AppTheme.orbitron.copyWith(color: AppColors.neonGold, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: today.entries.where((e) => e.key != 'Sunrise').map((e) {
                  final active = e.key == _next.key;
                  return Expanded(
                    child: Column(
                      children: [
                        Text(e.key, style: TextStyle(color: active ? AppColors.neonGold : AppColors.textSecondary, fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                        const SizedBox(height: 2),
                        Text(
                          '${e.value.hour.toString().padLeft(2, '0')}:${e.value.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: active ? AppColors.textPrimary : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weatherPill() {
    if (_weatherError != null) {
      return const Text('Cuaca n/a', style: TextStyle(color: AppColors.textSecondary, fontSize: 11));
    }
    if (_weather == null) {
      return const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonGold));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.neonCyan.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(
        '${_weather!.tempC.toStringAsFixed(0)}°C · ${_weather!.description}',
        style: const TextStyle(color: AppColors.neonCyan, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
