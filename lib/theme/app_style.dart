import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Tiga gaya UI yang bisa dipilih dari Settings.
///  - neo     : Neobrutalism 3D — garis tebal, bayangan keras bergeser (default)
///  - glass   : Glassmorphism — kaca buram, blur kuat, kilau lembut
///  - minimal : Minimalist — datar, garis tipis, tanpa glow
enum AppStyle { neo, glass, minimal }

extension AppStyleInfo on AppStyle {
  String get label {
    switch (this) {
      case AppStyle.neo:
        return 'Neo 3D';
      case AppStyle.glass:
        return 'Glassmorphism';
      case AppStyle.minimal:
        return 'Minimalist';
    }
  }

  String get description {
    switch (this) {
      case AppStyle.neo:
        return 'Garis tebal + bayangan keras 3D, berani dan tegas';
      case AppStyle.glass:
        return 'Kaca buram dengan blur dan kilau lembut';
      case AppStyle.minimal:
        return 'Datar, bersih, garis tipis, tanpa efek berlebihan';
    }
  }
}

/// Menyimpan & menyiarkan gaya UI aktif. Dibaca lewat [AppStyleKit].
class StyleController extends ChangeNotifier {
  StyleController._();
  static final StyleController instance = StyleController._();

  static const _key = 'ui_style';
  static const _lightModeKey = 'ui_light_mode';
  AppStyle _style = AppStyle.neo;
  bool _isLightMode = false;
  AppStyle get style => _style;
  bool get isLightMode => _isLightMode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      final loaded = AppStyle.values.firstWhere(
        (s) => s.name == v,
        orElse: () => AppStyle.neo,
      );
      final lightMode = prefs.getBool(_lightModeKey) ?? false;
      if (loaded != _style || lightMode != _isLightMode) {
        _style = loaded;
        _isLightMode = lightMode;
        notifyListeners();
      }
    } catch (_) {
      /* pakai default */
    }
  }

  Future<void> set(AppStyle s) async {
    if (s == _style) return;
    _style = s;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, s.name);
    } catch (_) {}
  }

  Future<void> setLightMode(bool enabled) async {
    if (enabled == _isLightMode) return;
    _isLightMode = enabled;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(
        _lightModeKey,
        enabled,
      );
    } catch (_) {}
  }

  /// Dipakai overlay (isolate lain): ganti gaya tanpa menulis ke storage.
  void applyName(String? name, {bool? lightMode}) {
    final s = AppStyle.values.firstWhere(
      (x) => x.name == name,
      orElse: () => _style,
    );
    final nextLightMode = lightMode ?? _isLightMode;
    if (s != _style || nextLightMode != _isLightMode) {
      _style = s;
      _isLightMode = nextLightMode;
      notifyListeners();
    }
  }
}

/// Pusat dekorasi semua gaya — kartu, badge, nav, background.
class AppStyleKit {
  AppStyleKit._();

  static AppStyle get current => StyleController.instance.style;
  static bool get isNeo => current == AppStyle.neo;
  static bool get isGlass => current == AppStyle.glass;
  static bool get isMinimal => current == AppStyle.minimal;

  // Palet Neo (varian gelap): garis krem tebal + permukaan gelap + aksen cerah.
  static const neoInk = Color(0xFFF4EDE0);
  static const neoSurface = Color(0xFF17171F);
  static const neoBg = Color(0xFF0D0D12);
  static const minimalBg = Color(0xFF0A0A0C);
  static const minimalSurface = Color(0xFF121216);
  static const lightBackground = Color(0xFFF2F4F7);

  static Color get scaffoldBg {
    if (StyleController.instance.isLightMode) return lightBackground;
    switch (current) {
      case AppStyle.neo:
        return neoBg;
      case AppStyle.glass:
        return AppColors.bgTop;
      case AppStyle.minimal:
        return minimalBg;
    }
  }

  static double radiusFor(AppStyle s, [double? requested]) {
    switch (s) {
      case AppStyle.neo:
        return 14;
      case AppStyle.glass:
        return requested ?? 22;
      case AppStyle.minimal:
        return 10;
    }
  }

  static double get blurSigma => isGlass ? 24 : 0;
  static ImageFilter get blurFilter =>
      ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);

  /// Dekorasi kartu untuk gaya [s] (dipakai juga oleh pratinjau di Settings).
  static BoxDecoration cardFor(AppStyle s, {Color? accent, double? radius}) {
    final r = BorderRadius.circular(radiusFor(s, radius));
    switch (s) {
      case AppStyle.neo:
        return BoxDecoration(
          color: neoSurface,
          borderRadius: r,
          border: Border.all(color: neoInk, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: accent ?? AppColors.neonGold,
              offset: const Offset(5, 5),
              blurRadius: 0,
            ),
          ],
        );
      case AppStyle.glass:
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.17),
              Colors.white.withOpacity(0.05),
            ],
          ),
          borderRadius: r,
          border: Border.all(color: Colors.white.withOpacity(0.30), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.38),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
            if (accent != null)
              BoxShadow(
                color: accent.withOpacity(0.20),
                blurRadius: 30,
                spreadRadius: -6,
              ),
          ],
        );
      case AppStyle.minimal:
        return BoxDecoration(
          color: minimalSurface,
          borderRadius: r,
          border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
        );
    }
  }

  static BoxDecoration card({Color? accent, double? radius}) =>
      cardFor(current, accent: accent, radius: radius);

  /// Badge ikon kecil di header tiap layar.
  static BoxDecoration badge(Color accent) {
    switch (current) {
      case AppStyle.neo:
        return BoxDecoration(
          color: neoSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: neoInk, width: 2.5),
          boxShadow: [
            BoxShadow(color: accent, offset: const Offset(4, 4), blurRadius: 0),
          ],
        );
      case AppStyle.glass:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [accent.withOpacity(0.34), accent.withOpacity(0.08)],
          ),
          border: Border.all(color: accent.withOpacity(0.7), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.42),
              blurRadius: 16,
              spreadRadius: -1,
            ),
            BoxShadow(color: accent.withOpacity(0.16), blurRadius: 32),
          ],
        );
      case AppStyle.minimal:
        return BoxDecoration(
          color: minimalSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withOpacity(0.55), width: 1),
        );
    }
  }

  /// Bentuk tombol Outlined/Filled sesuai gaya.
  static OutlinedBorder buttonShape() {
    switch (current) {
      case AppStyle.neo:
        return RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: neoInk, width: 2),
        );
      case AppStyle.glass:
        return const StadiumBorder();
      case AppStyle.minimal:
        return RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    }
  }
}

/// Dipasang di atas seluruh app: saat gaya berubah, semua widget di bawahnya
/// di-build ulang (state tetap terjaga: socket, timer, scroll, dll tidak hilang).
class StyleRebuilder extends StatefulWidget {
  final Widget child;
  const StyleRebuilder({super.key, required this.child});

  @override
  State<StyleRebuilder> createState() => _StyleRebuilderState();
}

class _StyleRebuilderState extends State<StyleRebuilder> {
  @override
  void initState() {
    super.initState();
    StyleController.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    StyleController.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Titik-titik halus (halftone) untuk latar Neo.
class DotGridPainter extends CustomPainter {
  final Color color;
  const DotGridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final pts = <Offset>[];
    for (double y = 12; y < size.height; y += 24) {
      for (double x = 12; x < size.width; x += 24) {
        pts.add(Offset(x, y));
      }
    }
    canvas.drawPoints(PointMode.points, pts, paint);
  }

  @override
  bool shouldRepaint(DotGridPainter old) => old.color != color;
}
