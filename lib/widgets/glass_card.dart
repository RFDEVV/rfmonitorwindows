import 'package:flutter/material.dart';
import '../theme/app_style.dart';

/// Kartu universal. Tampilannya mengikuti gaya UI aktif:
/// Neo 3D (garis tebal + bayangan keras), Glassmorphism (blur + kaca), Minimalist (datar).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? glowColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: AppStyleKit.card(accent: glowColor, radius: radius),
      child: child,
    );
    if (!AppStyleKit.isGlass) return box;   // tidak ada blur → tidak perlu clip (bayangan tetap utuh)

    final r = AppStyleKit.radiusFor(AppStyle.glass, radius);
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(filter: AppStyleKit.blurFilter, child: box),
    );
  }
}
