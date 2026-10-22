import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../services/media_prefs.dart';
import '../services/settings_store.dart';

/// Auto-playing, looping, muted banner for the top of the Dashboard.
/// Falls back to a neon gradient placeholder if assets/video/banner_video.mp4
/// hasn't been supplied yet, so the app never crashes on a missing asset.
class VideoBanner extends StatefulWidget {
  const VideoBanner({super.key});

  @override
  State<VideoBanner> createState() => _VideoBannerState();
}

class _VideoBannerState extends State<VideoBanner> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _off = false;
  int _loadToken = 0;   // cegah hasil load lama menimpa load yang lebih baru

  @override
  void initState() {
    super.initState();
    MediaPrefs.changes.addListener(_load);
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final mode = await MediaPrefs.bannerMode();
    final old = _controller;
    if (mounted) {
      setState(() {
        _controller = null;
        _failed = false;
        _off = mode == MediaMode.off;
      });
    }
    await old?.dispose();
    if (mode == MediaMode.off) return;

    final path = mode == MediaMode.custom ? await MediaPrefs.bannerPath() : null;
    final controller = path != null
        ? VideoPlayerController.file(File(path))
        : VideoPlayerController.asset('assets/video/banner_video.mp4');
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (await SettingsStore().getBannerAutoplay()) await controller.play();
      if (!mounted || token != _loadToken) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted && token == _loadToken) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    MediaPrefs.changes.removeListener(_load);
    _loadToken++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_off) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: AppTheme.glassDecoration(radius: 20, glow: AppColors.neonOrange, glowStrength: 0.28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A0F00), AppColors.bgBottom, Color(0xFF001A1F)],
                  ),
                ),
                child: Center(
                  child: Text(
                    _failed ? 'RFPROJECT // RFMONITOR' : 'Loading banner…',
                    style: AppTheme.orbitron.copyWith(color: AppColors.neonOrange, letterSpacing: 3, fontSize: 13),
                  ),
                ),
              ),
            // Bottom gradient so any overlaid label text stays legible.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.bgTop.withOpacity(0.55)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
