import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_style.dart';

/// Design tokens — Cyberpunk Neon Glow
/// Font body: Rajdhani Regular (sesuai referensi gambar)
/// Semua teks sekarang wajib memakai font lokal Rajdhani
class AppColors {
  static const bgTop = Color(0xFF08080A);
  static const bgBottom = Color(0xFF101216);
  static const glassBase = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);

  static const neonOrange = Color(0xFFFF5E00);
  static const neonGold = Color(0xFFFFB700);
  static const neonCyan = Color(0xFF00E5FF);
  static const neonGreen = Color(0xFF00FF66);
  static const roseRed = Color(0xFFFF2A6D);

  // aliases
  static const neonEmerald = neonGreen;
  static const amberGold = neonGold;

  static const textPrimary = Color(0xFFF5F6FA);
  static const textSecondary = Color(0xFF9BA3B4);
}

class AppTheme {
  static ThemeData get dark => themeFor(
        StyleController.instance.style,
        lightMode: StyleController.instance.isLightMode,
      );

  static ThemeData themeFor(AppStyle style, {bool lightMode = false}) {
    final bg = style == AppStyle.neo
        ? AppStyleKit.neoBg
        : style == AppStyle.minimal
            ? AppStyleKit.minimalBg
            : AppColors.bgTop;
    final surface = style == AppStyle.neo
        ? AppStyleKit.neoSurface
        : style == AppStyle.minimal
            ? AppStyleKit.minimalSurface
            : AppColors.bgBottom;

    final base = ThemeData(
      brightness: lightMode ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: lightMode
          ? ColorScheme.light(
              primary: AppColors.neonCyan,
              secondary: AppColors.neonOrange,
              error: AppColors.roseRed,
              surface: surface,
            )
          : ColorScheme.dark(
              primary: AppColors.neonCyan,
              secondary: AppColors.neonOrange,
              error: AppColors.roseRed,
              surface: surface,
            ),
      fontFamily: 'Rajdhani',
      useMaterial3: true,
    );

    final bodyFont = base.textTheme.apply(fontFamily: 'Rajdhani');
    final shape = _buttonShapeFor(style);

    return base.copyWith(
      textTheme: bodyFont.copyWith(
        bodyMedium: bodyFont.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: bodyFont.bodySmall?.copyWith(color: AppColors.textSecondary),
        titleLarge: const TextStyle(
          fontFamily: 'Rajdhani',
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: const TextStyle(
          fontFamily: 'Rajdhani',
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: shape),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: style == AppStyle.neo
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppStyleKit.neoInk, width: 2.5),
              )
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  style == AppStyle.minimal ? 10 : 22,
                ),
              ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: bodyFont.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: style == AppStyle.neo
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppStyleKit.neoInk, width: 2),
              )
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static OutlinedBorder _buttonShapeFor(AppStyle style) {
    switch (style) {
      case AppStyle.neo:
        return RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
      case AppStyle.glass:
        return const StadiumBorder();
      case AppStyle.minimal:
        return RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    }
  }

  // ── Font shortcuts ────────────────────────────────────────────────────────
  /// Orbitron Bold — heading / HUD besar
  static TextStyle get orbitron =>
      const TextStyle(fontFamily: 'Rajdhani', fontWeight: FontWeight.w700);

  /// Rajdhani Regular — body, nilai utama (sesuai referensi)
  static TextStyle get rajdhani =>
      const TextStyle(fontFamily: 'Rajdhani', fontWeight: FontWeight.w400);

  /// Rajdhani SemiBold — nilai angka (lebih terbaca)
  static TextStyle get rajdhaniSemiBold =>
      const TextStyle(fontFamily: 'Rajdhani', fontWeight: FontWeight.w600);

  /// Chakra Petch — label/sublabel/subtext
  static TextStyle get chakraPetch =>
      const TextStyle(fontFamily: 'Rajdhani', fontWeight: FontWeight.w400);

  // ── Decorations ───────────────────────────────────────────────────────────
  /// Dekorasi kartu sesuai gaya aktif (nama dipertahankan agar kode lama tetap jalan).
  static BoxDecoration glassDecoration({
    double radius = 20,
    Color? glow,
    double glowStrength = 0.35,
  }) {
    return AppStyleKit.card(accent: glow, radius: radius);
  }

  static BoxDecoration get backgroundGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, Color(0xFF0C0D11), AppColors.bgBottom],
          stops: [0.0, 0.55, 1.0],
        ),
      );

  static Widget backdropGlow(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -60,
            child: _glowOrb(AppColors.neonOrange, 220),
          ),
          Positioned(
            top: 120,
            right: -80,
            child: _glowOrb(AppColors.neonCyan, 260),
          ),
          Positioned(
            bottom: -60,
            left: MediaQuery.of(context).size.width * 0.3,
            child: _glowOrb(AppColors.neonGreen, 200),
          ),
        ],
      ),
    );
  }

  static Widget _glowOrb(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.16), Colors.transparent],
          ),
        ),
      );
}

final ImageFilter glassBlur = ImageFilter.blur(sigmaX: 18, sigmaY: 18);

// ── Neon Corner Glow Widget ────────────────────────────────────────────────────
/// Membungkus child dengan efek neon glow di pojok-pojok card.
/// Sesuai referensi: sudut card bercahaya neon samar.
class NeonCornerCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;

  const NeonCornerCard({
    super.key,
    required this.child,
    required this.color,
    this.radius = 18,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    if (!AppStyleKit.isGlass) {
      // Neo / Minimalist: kartu solid sesuai gaya (tanpa glow sudut)
      return Container(
        padding: padding,
        decoration: AppStyleKit.card(accent: color, radius: radius),
        child: child,
      );
    }
    return CustomPaint(
      painter: _NeonCornerPainter(color: color, radius: radius),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFF111418).withOpacity(0.78),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: color.withOpacity(0.32), width: 1.2),
        ),
        child: child,
      ),
    );
  }
}

class _NeonCornerPainter extends CustomPainter {
  final Color color;
  final double radius;
  _NeonCornerPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Top-left
    canvas.drawArc(
      Rect.fromLTWH(0, 0, radius * 2, radius * 2),
      3.14,
      0.5,
      false,
      paint,
    );
    // Top-right
    canvas.drawArc(
      Rect.fromLTWH(size.width - radius * 2, 0, radius * 2, radius * 2),
      4.71,
      0.5,
      false,
      paint,
    );
    // Bottom-left
    canvas.drawArc(
      Rect.fromLTWH(0, size.height - radius * 2, radius * 2, radius * 2),
      1.57,
      0.5,
      false,
      paint,
    );
    // Bottom-right
    canvas.drawArc(
      Rect.fromLTWH(
        size.width - radius * 2,
        size.height - radius * 2,
        radius * 2,
        radius * 2,
      ),
      0,
      0.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_NeonCornerPainter old) => old.color != color;
}
