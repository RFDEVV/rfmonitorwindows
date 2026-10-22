import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';
import '../theme/app_style.dart';

/// Sisi app utama untuk tombol bulat melayang (overlay di atas aplikasi lain).
/// Android saja. Jendela overlay berjalan di engine terpisah (lihat overlay/overlay_app.dart).
class OverlayService {
  OverlayService._();

  static Future<void> _operations = Future<void>.value();
  static const _prefKey = 'bubble_auto_enabled';
  static const _positionXKey = 'bubble_position_x';
  static const _positionYKey = 'bubble_position_y';
  static const _positionInitializedKey = 'bubble_position_initialized_v2';
  static const _freeDragInitializedKey = 'bubble_free_drag_initialized_v2';
  static const _bubbleSizeKey = 'bubble_size';
  static const _panelScaleKey = 'overlay_panel_scale';
  static const _screenWidthKey = 'bubble_screen_width';
  static const _screenHeightKey = 'bubble_screen_height';
  static const double defaultBubbleSize = 88;
  static const double minBubbleSize = 72;
  static const double maxBubbleSize = 108;
  static const double peekWidth = 30;
  static const double defaultPanelScale = 1;
  static const double minPanelScale = 0.75;
  static const double maxPanelScale = 1.25;

  static double peekWidthFor(double size) =>
      (size * 0.34).clamp(20, 36).toDouble();

  static Future<double> bubbleSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getDouble(_bubbleSizeKey) ?? defaultBubbleSize)
          .clamp(minBubbleSize, maxBubbleSize)
          .toDouble();
    } catch (_) {
      return defaultBubbleSize;
    }
  }

  static Future<double> screenWidth() async {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final view = views.first;
      final width = view.physicalSize.width / view.devicePixelRatio;
      if (width > 0) return width;
    }
    try {
      final stored =
          (await SharedPreferences.getInstance()).getDouble(_screenWidthKey);
      if (stored != null && stored > 0) return stored;
    } catch (_) {}
    return 0;
  }

  static Future<double> storedScreenWidth() async {
    try {
      final stored =
          (await SharedPreferences.getInstance()).getDouble(_screenWidthKey);
      if (stored != null && stored > 0) return stored;
    } catch (_) {}
    return 0;
  }

  static Future<double> screenHeight() async {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final view = views.first;
      final height = view.physicalSize.height / view.devicePixelRatio;
      if (height > 0) return height;
    }
    return storedScreenHeight();
  }

  static Future<double> storedScreenHeight() async {
    try {
      final stored =
          (await SharedPreferences.getInstance()).getDouble(_screenHeightKey);
      if (stored != null && stored > 0) return stored;
    } catch (_) {}
    return 0;
  }

  static Future<double> panelScale() async {
    try {
      return ((await SharedPreferences.getInstance())
                  .getDouble(_panelScaleKey) ??
              defaultPanelScale)
          .clamp(minPanelScale, maxPanelScale)
          .toDouble();
    } catch (_) {
      return defaultPanelScale;
    }
  }

  static Future<void> setPanelScale(double scale) async {
    final clamped = scale.clamp(minPanelScale, maxPanelScale).toDouble();
    try {
      await (await SharedPreferences.getInstance())
          .setDouble(_panelScaleKey, clamped);
    } catch (_) {}
    try {
      if (await isActive()) {
        await FlutterOverlayWindow.shareData(
          jsonEncode({'type': 'panel_scale', 'scale': clamped}),
        );
      }
    } catch (_) {}
  }

  static OverlayPosition? _defaultBubblePosition(double size) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    final view = views.first;
    final ratio = view.devicePixelRatio;
    if (ratio <= 0) return null;
    final width = view.physicalSize.width / ratio;
    final height = view.physicalSize.height / ratio;
    if (width <= 0 || height <= 0) return null;
    final safeWidth = width - size;
    final safeHeight = height - size;
    return OverlayPosition(
      (safeWidth / 2).clamp(0, double.infinity),
      (safeHeight / 2).clamp(0, double.infinity),
    );
  }

  static Future<void> setBubbleSize(double size) async {
    final clampedSize = size.clamp(minBubbleSize, maxBubbleSize).toDouble();
    try {
      await (await SharedPreferences.getInstance())
          .setDouble(_bubbleSizeKey, clampedSize);
    } catch (_) {}
    try {
      if (await isActive()) {
        await FlutterOverlayWindow.shareData(
          jsonEncode({'type': 'bubble_size', 'size': clampedSize}),
        );
      }
    } catch (_) {}
  }

  static Future<T> _runExclusive<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  /// Mode otomatis: tombol bulat muncul sendiri saat app di-minimize/ditinggalkan.
  static Future<bool> isAutoEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoEnabled(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefKey, v);
    } catch (_) {}
  }

  static Future<OverlayPosition?> _loadPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_positionXKey);
      final y = prefs.getDouble(_positionYKey);
      return x == null || y == null ? null : OverlayPosition(x, y);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePosition(OverlayPosition position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_positionXKey, position.x);
      await prefs.setDouble(_positionYKey, position.y);
    } catch (_) {}
  }

  static Future<bool> hasPermission() async {
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  /// Membuka halaman izin "Tampil di atas aplikasi lain" bila belum diberi.
  static Future<bool> requestPermission() async {
    try {
      if (await hasPermission()) return true;
      await FlutterOverlayWindow.requestPermission();
      return await hasPermission();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isActive() async {
    try {
      return await FlutterOverlayWindow.isActive();
    } catch (_) {
      return false;
    }
  }

  /// Tampilkan tombol bulat. Return false bila izin belum ada / gagal.
  static Future<bool> showBubble(ServerConfig config) =>
      _runExclusive(() => _showBubble(config));

  static Future<bool> _showBubble(ServerConfig config) async {
    try {
      if (!await hasPermission()) return false;
      final size = await bubbleSize();
      final displayWidth = await screenWidth();
      final displayHeight = await screenHeight();
      if (displayWidth > 0) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(_screenWidthKey, displayWidth);
          if (displayHeight > 0) {
            await prefs.setDouble(_screenHeightKey, displayHeight);
          }
        } catch (_) {}
      }
      var startPosition = await _loadPosition();
      var repositionedFromOldTopEdge = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final initialized = prefs.getBool(_positionInitializedKey) ?? false;
        if (!initialized) {
          if (startPosition == null || startPosition.y <= 1) {
            final defaultPosition = _defaultBubblePosition(size);
            if (defaultPosition != null) {
              startPosition = defaultPosition;
              repositionedFromOldTopEdge = true;
              await savePosition(defaultPosition);
              await prefs.setBool(_positionInitializedKey, true);
            }
          } else {
            await prefs.setBool(_positionInitializedKey, true);
          }
        }
      } catch (_) {}
      startPosition ??= _defaultBubblePosition(size);
      if (startPosition != null) {
        await savePosition(startPosition);
      }
      final active = await isActive();
      var freeDragInitialized = false;
      try {
        freeDragInitialized = (await SharedPreferences.getInstance())
                .getBool(_freeDragInitializedKey) ??
            false;
      } catch (_) {}
      if (active && !freeDragInitialized) {
        await FlutterOverlayWindow.closeOverlay().timeout(
          const Duration(seconds: 3),
        );
        final closeDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (await isActive()) {
          if (DateTime.now().isAfter(closeDeadline)) return false;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (active && freeDragInitialized) {
        if (repositionedFromOldTopEdge && startPosition != null) {
          if (await FlutterOverlayWindow.moveOverlay(startPosition) == false) {
            throw StateError('Gagal memindahkan tombol ke posisi awal');
          }
        }
        await FlutterOverlayWindow.shareData(
          jsonEncode({
            'type': 'activate',
            'config': config.toJson(),
            'style': StyleController.instance.style.name,
            'lightMode': StyleController.instance.isLightMode,
            'bubbleSize': size,
            'screenWidth': displayWidth,
            'screenHeight': displayHeight,
          }),
        );
        return true;
      }
      await FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        alignment: OverlayAlignment.topLeft,
        overlayTitle: 'RF Monitor',
        overlayContent: 'Tombol monitor melayang aktif',
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.none,
        startPosition: startPosition,
        height: size.round(),
        width: size.round(),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!await isActive()) {
        if (DateTime.now().isAfter(deadline)) return false;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      try {
        await (await SharedPreferences.getInstance())
            .setBool(_freeDragInitializedKey, true);
      } catch (_) {}
      await FlutterOverlayWindow.shareData(
        jsonEncode({
          'type': 'activate',
          'config': config.toJson(),
          'style': StyleController.instance.style.name,
          'lightMode': StyleController.instance.isLightMode,
          'bubbleSize': size,
          'screenWidth': displayWidth,
          'screenHeight': displayHeight,
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Kirim konfigurasi server + gaya UI ke jendela overlay (engine lain).
  static Future<void> pushConfig(ServerConfig c) async {
    try {
      await FlutterOverlayWindow.shareData(
        jsonEncode({
          'type': 'config',
          'config': c.toJson(),
          'style': StyleController.instance.style.name,
          'lightMode': StyleController.instance.isLightMode,
        }),
      );
    } catch (_) {}
  }

  static Future<void> close() => _runExclusive(_close);

  static Future<void> _close() async {
    try {
      if (await FlutterOverlayWindow.isActive()
          .timeout(const Duration(seconds: 2))) {
        await FlutterOverlayWindow.closeOverlay().timeout(
          const Duration(seconds: 2),
        );
      }
    } catch (_) {}
  }

  /// Pindahkan app ke latar belakang (layar utama) tanpa menutupnya.
  static Future<void> goHome() async {
    try {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.HOME',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (_) {}
  }
}
