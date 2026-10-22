Put the real azan sound here as `azan_custom.mp3` (Android notification
sounds must live in res/raw, not the Flutter assets/ folder — that's why
this is a separate copy from assets/audio/azan_custom.mp3).
NotificationService references it by resource name (no extension):
RawResourceAndroidNotificationSound('azan_custom')
