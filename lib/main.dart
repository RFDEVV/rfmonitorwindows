import 'dart:io';

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'theme/app_style.dart';
import 'screens/splash_screen.dart';
import 'overlay/overlay_app.dart';
import 'services/overlay_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    await OverlayService.close();
  }
  await StyleController.instance.load();
  runApp(const RfMonitorApp());
}

/// Entry point jendela overlay (tombol bulat di atas app lain). Dipanggil oleh
/// plugin flutter_overlay_window di engine terpisah.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

class RfMonitorApp extends StatelessWidget {
  const RfMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Saat gaya diganti, ThemeData ikut berganti dan seluruh UI di-build ulang
    // (StyleRebuilder) tanpa menghilangkan state.
    return ListenableBuilder(
      listenable: StyleController.instance,
      builder: (context, _) => MaterialApp(
        title: 'RFMonitor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeFor(
          StyleController.instance.style,
          lightMode: StyleController.instance.isLightMode,
        ),
        builder: (context, child) =>
            StyleRebuilder(child: child ?? const SizedBox.shrink()),
        home: const SplashScreen(),
      ),
    );
  }
}
