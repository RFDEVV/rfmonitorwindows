import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _prayerNotifKey = 'settings_prayer_notif_enabled';
  static const _alertNotifKey = 'settings_alert_notif_enabled';
  static const _bannerAutoplayKey = 'settings_banner_autoplay';
  static const _powerThresholdKey = 'settings_power_threshold_rp';
  static const _bandwidthThresholdKey = 'settings_bandwidth_threshold_gb';
  static const _cpuTempThresholdKey = 'settings_cpu_temp_threshold_c'; // NEW
  static const _lastPowerNotifDayKey = 'settings_last_power_notif_day';
  static const _lastBandwidthNotifDayKey = 'settings_last_bandwidth_notif_day';
  static const _lastCpuTempNotifDayKey = 'settings_last_cpu_temp_notif_day'; // NEW

  // ---- Power threshold ----
  Future<double> getPowerThresholdRp() async =>
      (await SharedPreferences.getInstance()).getDouble(_powerThresholdKey) ?? 0;
  Future<void> setPowerThresholdRp(double v) async =>
      (await SharedPreferences.getInstance()).setDouble(_powerThresholdKey, v);

  // ---- Bandwidth threshold ----
  Future<double> getBandwidthThresholdGB() async =>
      (await SharedPreferences.getInstance()).getDouble(_bandwidthThresholdKey) ?? 0;
  Future<void> setBandwidthThresholdGB(double v) async =>
      (await SharedPreferences.getInstance()).setDouble(_bandwidthThresholdKey, v);

  // ---- CPU Temp threshold (NEW) ----
  Future<double> getCpuTempThreshold() async =>
      (await SharedPreferences.getInstance()).getDouble(_cpuTempThresholdKey) ?? 70.0;
  Future<void> setCpuTempThreshold(double v) async =>
      (await SharedPreferences.getInstance()).setDouble(_cpuTempThresholdKey, v);

  // ---- Throttle: 1x/hari per jenis ----
  Future<bool> shouldNotifyPowerThresholdToday() => _shouldNotifyToday(_lastPowerNotifDayKey);
  Future<bool> shouldNotifyBandwidthThresholdToday() => _shouldNotifyToday(_lastBandwidthNotifDayKey);
  Future<bool> shouldNotifyCpuTempToday() => _shouldNotifyToday(_lastCpuTempNotifDayKey); // NEW

  Future<bool> _shouldNotifyToday(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(key) == today) return false;
    await prefs.setString(key, today);
    return true;
  }

  // ---- Prayer & alert toggles ----
  Future<bool> getPrayerNotifEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_prayerNotifKey) ?? true;
  Future<void> setPrayerNotifEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_prayerNotifKey, v);

  Future<bool> getAlertNotifEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_alertNotifKey) ?? true;
  Future<void> setAlertNotifEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_alertNotifKey, v);

  Future<bool> getBannerAutoplay() async =>
      (await SharedPreferences.getInstance()).getBool(_bannerAutoplayKey) ?? true;
  Future<void> setBannerAutoplay(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_bannerAutoplayKey, v);
}
