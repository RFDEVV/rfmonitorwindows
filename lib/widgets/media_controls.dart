import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/media_prefs.dart';
import 'glass_card.dart';

/// Kartu pengaturan: ganti / hapus / kembalikan default untuk video banner
/// dashboard dan background aplikasi — langsung dari app, tanpa rebuild.
class MediaControls extends StatefulWidget {
  const MediaControls({super.key});

  @override
  State<MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<MediaControls> {
  MediaMode _banner = MediaMode.standard;
  MediaMode _bg = MediaMode.standard;
  MediaMode _prayer = MediaMode.standard;
  MediaMode _splash = MediaMode.standard;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final b = await MediaPrefs.bannerMode();
    final g = await MediaPrefs.bgMode();
    final p = await MediaPrefs.prayerMode();
    final s = await MediaPrefs.splashMode();
    if (mounted) {
      setState(() {
        _banner = b;
        _bg = g;
        _prayer = p;
        _splash = s;
      });
    }
  }

  Future<void> _run(Future<Object?> Function() job, {String? okMsg}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await job();
      if (okMsg != null && r != false && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(MediaMode m) => switch (m) {
        MediaMode.standard => 'Bawaan',
        MediaMode.custom => 'Pilihan kamu',
        MediaMode.off => 'Dimatikan',
      };

  Widget _row(String title, IconData icon, MediaMode mode, VoidCallback pick,
      VoidCallback off, VoidCallback reset) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppColors.neonCyan, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600))),
          Text(_label(mode),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11.5)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
              onPressed: _busy ? null : pick,
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              label: const Text('Ganti')),
          OutlinedButton.icon(
            onPressed: _busy || mode == MediaMode.off ? null : off,
            icon: const Icon(Icons.hide_image_outlined, size: 16),
            label: const Text('Hapus'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.roseRed),
          ),
          TextButton(
              onPressed: _busy || mode == MediaMode.standard ? null : reset,
              child: const Text('Default')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glowColor: AppColors.neonCyan,
      child: Column(children: [
        _row(
            'Video Splash Screen',
            Icons.slideshow_rounded,
            _splash,
            () =>
                _run(MediaPrefs.pickSplashVideo, okMsg: 'Video splash diganti'),
            () => _run(() => MediaPrefs.setSplashMode(MediaMode.off),
                okMsg: 'Video splash dimatikan'),
            () => _run(() => MediaPrefs.setSplashMode(MediaMode.standard),
                okMsg: 'Kembali ke video splash bawaan')),
        const Divider(color: AppColors.glassBorder, height: 14),
        _row(
            'Video Banner Dashboard',
            Icons.movie_outlined,
            _banner,
            () => _run(MediaPrefs.pickBanner, okMsg: 'Video banner diganti'),
            () => _run(() => MediaPrefs.setBannerMode(MediaMode.off),
                okMsg: 'Video banner dihapus'),
            () => _run(() => MediaPrefs.setBannerMode(MediaMode.standard),
                okMsg: 'Kembali ke video bawaan')),
        const Divider(color: AppColors.glassBorder, height: 14),
        _row(
            'Background Aplikasi',
            Icons.wallpaper_rounded,
            _bg,
            () => _run(MediaPrefs.pickBackground, okMsg: 'Background diganti'),
            () => _run(() => MediaPrefs.setBgMode(MediaMode.off),
                okMsg: 'Background dihapus'),
            () => _run(() => MediaPrefs.setBgMode(MediaMode.standard),
                okMsg: 'Kembali ke background bawaan')),
        const Divider(color: AppColors.glassBorder, height: 14),
        _row(
            'Background Kartu Waktu Sholat',
            Icons.mosque_outlined,
            _prayer,
            () => _run(MediaPrefs.pickPrayerBackground,
                okMsg: 'Background kartu sholat diganti'),
            () => _run(() => MediaPrefs.setPrayerMode(MediaMode.off),
                okMsg: 'Background kartu sholat dihapus'),
            () => _run(() => MediaPrefs.setPrayerMode(MediaMode.standard),
                okMsg: 'Kembali ke background bawaan')),
      ]),
    );
  }
}
