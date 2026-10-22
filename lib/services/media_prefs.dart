import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// standard = aset bawaan app · custom = file pilihan user · off = dimatikan
enum MediaMode { standard, custom, off }

/// Ganti / hapus video banner dan background aplikasi langsung dari app
/// (tanpa rebuild). File pilihan disalin ke penyimpanan privat app.
class MediaPrefs {
  MediaPrefs._();

  /// Naik tiap ada perubahan → widget yang mendengarkan memuat ulang medianya.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static const _bannerModeKey = 'media_banner_mode';
  static const _bannerPathKey = 'media_banner_path';
  static const _bgModeKey = 'media_bg_mode';
  static const _bgPathKey = 'media_bg_path';
  static const _prayerModeKey = 'media_prayer_mode';
  static const _prayerPathKey = 'media_prayer_path';
  static const _splashModeKey = 'media_splash_mode';
  static const _splashPathKey = 'media_splash_path';

  static Future<MediaMode> _mode(String key) async {
    final v = (await SharedPreferences.getInstance()).getString(key);
    return MediaMode.values
        .firstWhere((m) => m.name == v, orElse: () => MediaMode.standard);
  }

  static Future<void> _setMode(String key, MediaMode m) async {
    await (await SharedPreferences.getInstance()).setString(key, m.name);
    changes.value++;
  }

  static Future<String?> _path(String key) async {
    final p = (await SharedPreferences.getInstance()).getString(key);
    return (p != null && File(p).existsSync()) ? p : null;
  }

  static Future<MediaMode> bannerMode() => _mode(_bannerModeKey);
  static Future<MediaMode> bgMode() => _mode(_bgModeKey);
  static Future<String?> bannerPath() => _path(_bannerPathKey);
  static Future<String?> bgPath() => _path(_bgPathKey);
  static Future<MediaMode> prayerMode() => _mode(_prayerModeKey);
  static Future<String?> prayerPath() => _path(_prayerPathKey);
  static Future<MediaMode> splashMode() => _mode(_splashModeKey);
  static Future<String?> splashPath() => _path(_splashPathKey);

  static Future<void> setBannerMode(MediaMode m) => _setMode(_bannerModeKey, m);
  static Future<void> setBgMode(MediaMode m) => _setMode(_bgModeKey, m);
  static Future<void> setPrayerMode(MediaMode m) => _setMode(_prayerModeKey, m);
  static Future<void> setSplashMode(MediaMode m) => _setMode(_splashModeKey, m);

  static Future<bool> pickBanner() =>
      _pick(FileType.video, 'custom_banner', _bannerPathKey, _bannerModeKey);
  static Future<bool> pickBackground() =>
      _pick(FileType.image, 'custom_background', _bgPathKey, _bgModeKey);
  static Future<bool> pickPrayerBackground() =>
      _pick(FileType.image, 'custom_prayer', _prayerPathKey, _prayerModeKey);
  static Future<bool> pickSplashVideo() =>
      _pick(FileType.video, 'custom_splash', _splashPathKey, _splashModeKey);

  static Future<bool> _pick(
      FileType type, String base, String pathKey, String modeKey) async {
    final res =
        await FilePicker.platform.pickFiles(type: type, allowMultiple: false);
    final src = res?.files.single.path;
    if (src == null) return false;
    final dir = await getApplicationDocumentsDirectory();
    final dot = src.lastIndexOf('.');
    final ext =
        dot > src.lastIndexOf('/') && dot >= 0 ? src.substring(dot) : '';
    // nama unik per pilihan supaya cache gambar/video lama tidak ikut terpakai
    final dest =
        '${dir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(src).copy(dest);

    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(pathKey);
    await prefs.setString(pathKey, dest);
    await prefs.setString(modeKey, MediaMode.custom.name);
    if (old != null && old != dest) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    changes.value++;
    return true;
  }
}
