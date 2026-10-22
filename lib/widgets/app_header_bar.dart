import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../theme/app_style.dart';

/// Header bar setiap tab.
/// Title  → Orbitron Bold (HUD / heading)
/// Subtitle → Chakra Petch (sublabel / category)
/// Trailing text kecil → Rajdhani Regular
class AppHeaderBar extends StatelessWidget {
  final String   title;
  final String   subtitle;
  final IconData icon;
  final Widget?  iconWidget;
  final Color    accent;
  final Widget?  trailing;
  final VoidCallback? onBack;

  const AppHeaderBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon     = Icons.terminal_rounded,
    this.iconWidget,
    this.accent   = AppColors.neonOrange,
    this.trailing,
    this.onBack,
  });

  /// Helper: bikin iconWidget dari SVG string (lihat theme/app_icons.dart)
  /// yang di-tint sesuai warna aksen — dipakai di semua header layar supaya
  /// tiap section punya lambang sendiri (Dashboard/PM2/Service/dst),
  /// bukan cuma logo app generik.
  static Widget svgIcon(String svg, Color color, {double size = 22}) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.string(svg, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: [
        if (onBack != null) ...[
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.roseRed, size: 20),
            ),
          ),
          const SizedBox(width: 8),
        ],

        // Icon badge dengan neon glow
        Container(
          width: 46, height: 46,
          alignment: Alignment.center,
          decoration: AppStyleKit.badge(accent),
          child: iconWidget ?? Image.asset('assets/icon/app_icon.png', width: 22, height: 22),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title — Orbitron Bold (cyberpunk HUD look)
              Text(
                title,
                style: AppTheme.orbitron.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: AppStyleKit.isMinimal ? 1 : 2,
                ),
              ),
              // Subtitle — Chakra Petch (label/category)
              Text(
                subtitle,
                style: AppTheme.chakraPetch.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),

        if (trailing != null) trailing!,
      ]),
    );
  }
}
