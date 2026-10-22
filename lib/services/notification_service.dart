import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'prayer_service.dart';

/// Local push notifications: prayer-time azan alerts + instant alerts for
/// server-down / PM2-stopped / CPU-overheat events pushed over the socket.
/// Everything here is on-device only - no FCM/cloud dependency required.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _prayerChannel = AndroidNotificationChannel(
    'rfmonitor_prayer',
    'Jadwal Sholat',
    description: 'Notifikasi waktu sholat & azan',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('azan_custom'),
    playSound: true,
  );

  static const _alertChannel = AndroidNotificationChannel(
    'rfmonitor_alerts',
    'Server Alerts',
    description: 'Server down, PM2 stopped, CPU overheat',
    importance: Importance.max,
    playSound: true,
  );

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_prayerChannel);
    await androidImpl?.createNotificationChannel(_alertChannel);
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Schedules today's remaining (and tomorrow's, so there's always a full
  /// set queued) prayer notifications. Safe to call repeatedly - it clears
  /// previously scheduled prayer alerts first so times never double-fire.
  Future<void> scheduleUpcomingPrayers() async {
    await init();
    final now = DateTime.now();
    final scheduledIds = <int>[];

    for (final dayOffset in [0, 1]) {
      final day = now.add(Duration(days: dayOffset));
      final times = PrayerTimes.forDay(date: day);
      for (final entry in times.entries) {
        if (entry.key == 'Sunrise') continue; // not a prayer time itself
        final scheduled = tz.TZDateTime.from(entry.value, tz.local);
        if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) continue;
        scheduledIds.add(scheduled.millisecondsSinceEpoch ~/ 1000);
      }
    }

    for (final id in scheduledIds) {
      await _plugin.cancel(id);
    }

    for (final dayOffset in [0, 1]) {
      final day = now.add(Duration(days: dayOffset));
      final times = PrayerTimes.forDay(date: day);
      for (final entry in times.entries) {
        if (entry.key == 'Sunrise') continue;
        final scheduled = tz.TZDateTime.from(entry.value, tz.local);
        if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) continue;
        final notificationId = scheduled.millisecondsSinceEpoch ~/ 1000;
        await _plugin.zonedSchedule(
          notificationId,
          'Waktu ${entry.key} Tiba',
          'Jadwal Sholat Klaten, Jawa Tengah',
          scheduled,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'rfmonitor_prayer',
              'Jadwal Sholat',
              channelDescription: 'Notifikasi waktu sholat & azan',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              sound: RawResourceAndroidNotificationSound('azan_custom'),
              playSound: true,
              largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: null,
        );
      }
    }
  }

  Future<void> showServiceEvent(Map<String, dynamic> event) async {
    await init();
    final name = event['name'] ?? 'service';
    final status = event['status'] ?? 'unknown';
    final isDown = status == 'stopped' || status == 'errored';
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      isDown ? '⚠️ $name $status' : '✅ $name $status',
      isDown ? 'Service "$name" is now $status.' : 'Service "$name" recovered ($status).',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rfmonitor_alerts',
          'Server Alerts',
          channelDescription: 'Server down, PM2 stopped, CPU overheat',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      ),
    );
  }

  Future<void> showServerDown(String serverName) async {
    await init();
    await _plugin.show(
      99001,
      '🔴 $serverName is unreachable',
      'Realtime connection lost. RFMonitor will keep retrying.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rfmonitor_alerts',
          'Server Alerts',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      ),
    );
  }

  Future<void> showCpuOverheat(String serverName, double tempC) async {
    await init();
    await _plugin.show(
      99002,
      '🌡️ $serverName CPU Overheat',
      'CPU temperature reached ${tempC.toStringAsFixed(1)}°C.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rfmonitor_alerts',
          'Server Alerts',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      ),
    );
  }

  /// Fired once per day when monthly electricity cost or bandwidth usage
  /// crosses the threshold the user set in Settings.
  Future<void> showThresholdAlert({required String title, required String body, int id = 99003}) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rfmonitor_alerts',
          'Server Alerts',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      ),
    );
  }
}