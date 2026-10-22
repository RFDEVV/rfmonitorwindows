import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../services/overlay_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

/// Pengaturan tombol bulat melayang (overlay di atas aplikasi lain) — Android.
class BubbleControls extends StatefulWidget {
  const BubbleControls({super.key});

  @override
  State<BubbleControls> createState() => _BubbleControlsState();
}

class _BubbleControlsState extends State<BubbleControls> {
  bool _auto = false;
  bool _perm = false;
  bool _busy = false;
  double _bubbleSize = OverlayService.defaultBubbleSize;
  double _panelScale = OverlayService.defaultPanelScale;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!Platform.isAndroid) return;
    final a = await OverlayService.isAutoEnabled();
    final p = await OverlayService.hasPermission();
    final size = await OverlayService.bubbleSize();
    final panelScale = await OverlayService.panelScale();
    if (mounted) {
      setState(() {
        _auto = a;
        _perm = p;
        _bubbleSize = size;
        _panelScale = panelScale;
      });
    }
  }

  void _snack(String m) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _askPermission() async {
    setState(() => _busy = true);
    final ok = await OverlayService.requestPermission();
    await _refresh();
    if (mounted) setState(() => _busy = false);
    if (!ok)
      _snack(
          'Izin belum diberikan — aktifkan "Tampil di atas aplikasi lain" untuk RFMonitor');
  }

  Future<void> _bubbleNow() async {
    setState(() => _busy = true);
    try {
      if (!await OverlayService.requestPermission()) {
        _snack('Izin "Tampil di atas aplikasi lain" diperlukan');
        return;
      }
      final st = StorageService();
      final list = await st.loadProfiles();
      if (list.isEmpty) {
        _snack('Tambahkan server dulu');
        return;
      }
      final idx = await st.getActiveProfileIndex();
      final ok =
          await OverlayService.showBubble(list[idx.clamp(0, list.length - 1)]);
      if (!ok) {
        _snack('Gagal menampilkan tombol bulat');
        return;
      }
      await OverlayService.goHome();
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const GlassCard(
        glowColor: AppColors.neonCyan,
        child: Text('Tombol bulat melayang hanya tersedia di Android.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
      );
    }
    return GlassCard(
      glowColor: AppColors.neonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _auto,
            onChanged: _busy
                ? null
                : (v) async {
                    if (v && !await OverlayService.requestPermission()) {
                      _snack('Izin overlay diperlukan');
                      return;
                    }
                    await OverlayService.setAutoEnabled(v);
                    _refresh();
                  },
            activeColor: AppColors.neonCyan,
            title: const Text('Muncul otomatis saat app ditinggalkan',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Tombol bulat tampil di atas aplikasi lain, hilang saat app dibuka',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ),
          Row(children: [
            Icon(
                _perm
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 16,
                color: _perm ? AppColors.neonGreen : AppColors.neonGold),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  _perm
                      ? 'Izin "Tampil di atas aplikasi lain" aktif'
                      : 'Izin overlay belum diberikan',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11.5)),
            ),
            if (!_perm)
              TextButton(
                  onPressed: _busy ? null : _askPermission,
                  child: const Text('Beri izin')),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _bubbleNow,
              icon: const Icon(Icons.bubble_chart_rounded),
              label: const Text('Jadikan tombol bulat sekarang'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.neonCyan,
                  foregroundColor: Colors.black),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.open_in_full_rounded,
                color: AppColors.neonCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Ukuran tombol',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_bubbleSize.round()} dp',
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _bubbleSize,
            min: OverlayService.minBubbleSize,
            max: OverlayService.maxBubbleSize,
            divisions: 6,
            label: '${_bubbleSize.round()} dp',
            activeColor: AppColors.neonCyan,
            onChanged: (value) => setState(() => _bubbleSize = value),
            onChangeEnd: OverlayService.setBubbleSize,
          ),
          Row(
            children: [
              const Icon(
                Icons.dashboard_customize_rounded,
                color: AppColors.neonCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Ukuran panel overlay',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(_panelScale * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _panelScale,
            min: OverlayService.minPanelScale,
            max: OverlayService.maxPanelScale,
            divisions: 5,
            label: '${(_panelScale * 100).round()}%',
            activeColor: AppColors.neonCyan,
            onChanged: (value) => setState(() => _panelScale = value),
            onChangeEnd: OverlayService.setPanelScale,
          ),
          const Text(
            'Ketuk pegangan panah untuk membuka tombol bulat. Seret pegangan atau ikon untuk memindahkannya; panel dapat digeser dari ikon pegangan di bagian atas.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '1× ketuk: kotak kecil (CPU, RAM, disk, suhu, core)\n'
            '2× ketuk: PM2 + service\n'
            '3× ketuk: terminal SSH (layar penuh)\n'
            'Tekan lama: kembali ke tampilan app',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}
