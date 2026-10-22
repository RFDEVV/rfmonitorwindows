import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_style.dart';
import '../services/media_prefs.dart';

/// Full-app backdrop: optional assets/images/cyber_bg.png texture, layered
/// under the neon gradient + glow orbs. Renders correctly even before a
/// real background image is supplied.
class CyberBackground extends StatefulWidget {
  final Widget child;
  const CyberBackground({super.key, required this.child});

  @override
  State<CyberBackground> createState() => _CyberBackgroundState();
}

class _CyberBackgroundState extends State<CyberBackground> {
  MediaMode _mode = MediaMode.standard;
  String? _path;

  @override
  void initState() {
    super.initState();
    MediaPrefs.changes.addListener(_load);
    _load();
  }

  Future<void> _load() async {
    final m = await MediaPrefs.bgMode();
    final p = m == MediaMode.custom ? await MediaPrefs.bgPath() : null;
    if (mounted) setState(() { _mode = m; _path = p; });
  }

  @override
  void dispose() {
    MediaPrefs.changes.removeListener(_load);
    super.dispose();
  }

  Widget _image() {
    if (_mode == MediaMode.off) return const SizedBox.shrink();
    if (_mode == MediaMode.custom && _path != null) {
      return Image.file(File(_path!), fit: BoxFit.cover, cacheWidth: 1080, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    // Gambar bawaan hanya dipakai di gaya Glassmorphism
    if (!AppStyleKit.isGlass) return const SizedBox.shrink();
    return Image.asset('assets/images/cyber_bg.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }

  @override
  Widget build(BuildContext context) {
    final custom = _mode == MediaMode.custom && _path != null;
    Widget layer;
    if (AppStyleKit.isNeo) {
      layer = Stack(children: [
        Positioned.fill(child: Opacity(opacity: custom ? 0.35 : 1, child: _image())),
        const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: DotGridPainter(Color(0x14F4EDE0))))),
        // dua bidang warna datar ala poster neobrutalism
        Positioned(top: -70, right: -50, child: _flatBlob(AppColors.neonGold, 190)),
        Positioned(bottom: 90, left: -80, child: _flatBlob(AppColors.roseRed, 170)),
      ]);
    } else if (AppStyleKit.isMinimal) {
      layer = Positioned.fill(child: Opacity(opacity: custom ? 0.3 : 1, child: _image()));
    } else {
      layer = Stack(children: [
        Positioned.fill(child: Opacity(opacity: custom ? 0.45 : 0.18, child: _image())),
        Positioned.fill(child: AppTheme.backdropGlow(context)),
      ]);
    }
    return Container(
      color: AppStyleKit.scaffoldBg,
      child: Container(
        decoration: AppStyleKit.isGlass ? AppTheme.backgroundGradient : null,
        child: Stack(
          children: [
            if (layer is Positioned) layer else Positioned.fill(child: layer),
            widget.child,
          ],
        ),
      ),
    );
  }

  Widget _flatBlob(Color c, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.10)),
        ),
      );
}
