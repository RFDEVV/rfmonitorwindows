import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/app_style.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_header_bar.dart';
import '../widgets/media_controls.dart';
import '../widgets/style_picker.dart';
import '../widgets/bubble_controls.dart';
import '../theme/app_icons.dart';
import '../services/settings_store.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool firstRun;
  final VoidCallback? onProfileChanged;
  const SettingsScreen({
    super.key,
    required this.firstRun,
    this.onProfileChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _agentInstallUrl =
      'https://raw.githubusercontent.com/RFDEVV/server-agent/main/install.sh';
  final _settings = SettingsStore();
  bool _prayerNotif = true;
  bool _alertNotif = true;
  bool _bannerAutoplay = true;
  final _powerThresholdCtrl = TextEditingController();
  final _bandwidthThresholdCtrl = TextEditingController();
  final _cpuTempCtrl = TextEditingController(); // NEW

  @override
  void initState() {
    super.initState();
    _loadToggles();
  }

  Future<void> _loadToggles() async {
    final prayer = await _settings.getPrayerNotifEnabled();
    final alert = await _settings.getAlertNotifEnabled();
    final banner = await _settings.getBannerAutoplay();
    final powerThreshold = await _settings.getPowerThresholdRp();
    final bandwidthThreshold = await _settings.getBandwidthThresholdGB();
    final cpuTemp = await _settings.getCpuTempThreshold(); // NEW
    if (mounted) {
      setState(() {
        _prayerNotif = prayer;
        _alertNotif = alert;
        _bannerAutoplay = banner;
        _powerThresholdCtrl.text =
            powerThreshold > 0 ? powerThreshold.toStringAsFixed(0) : '';
        _bandwidthThresholdCtrl.text =
            bandwidthThreshold > 0 ? bandwidthThreshold.toStringAsFixed(0) : '';
        _cpuTempCtrl.text = cpuTemp.toStringAsFixed(0); // NEW
      });
    }
  }

  @override
  void dispose() {
    _powerThresholdCtrl.dispose();
    _bandwidthThresholdCtrl.dispose();
    _cpuTempCtrl.dispose();
    super.dispose();
  }

  Future<void> _copyAgentInstallUrl() async {
    try {
      await Clipboard.setData(const ClipboardData(text: _agentInstallUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL installer Server Agent disalin.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyalin URL installer: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.firstRun) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              AppHeaderBar(
                title: 'SETUP',
                subtitle: 'MULAI MENGGUNAKAN RFMONITOR',
                iconWidget: AppHeaderBar.svgIcon(
                  AppIcons.settings,
                  AppColors.neonCyan,
                ),
                accent: AppColors.neonCyan,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    GlassCard(
                      glowColor: AppColors.neonCyan,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sambungkan server dalam 3 langkah',
                            style: AppTheme.orbitron.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '1. Pasang Server Agent di Linux.\n'
                            '2. Atur service yang boleh dikontrol pada file .env.\n'
                            '3. Buka menu Server di navigasi untuk menambahkan dan mengatur profil server.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      glowColor: AppColors.neonGreen,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1 · Install Agent dan service otomatis',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Gunakan server Linux dengan Node.js 18+ dan systemd. Tinjau script sebelum menjalankan:',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            'curl -fsSL $_agentInstallUrl -o install.sh\n'
                            'less install.sh\n'
                            'sudo bash install.sh',
                            style: const TextStyle(
                              color: AppColors.neonGreen,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _copyAgentInstallUrl,
                              icon: const Icon(Icons.copy_rounded, size: 17),
                              label: const Text('Salin URL installer'),
                            ),
                          ),
                          const Text(
                            'Agent berjalan sebagai service systemd bernama rfmonitor-agent. Status: sudo systemctl status rfmonitor-agent. Log: sudo journalctl -u rfmonitor-agent -f.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      glowColor: AppColors.neonGold,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '2 · Atur .env dan kontrol service',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Edit konfigurasi di server dengan: sudo nano /opt/rfmonitor-agent/.env. Daftar service tetap dideteksi otomatis; allowlist berikut hanya menentukan service mana yang menampilkan tombol Start/Stop/Restart. Jika kosong, semua service tetap terlihat dan tidak ada tombol kontrol.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const SelectableText(
                            'ALLOWED_PM2_APPS=nama-app-1,nama-app-2\n'
                            'ALLOWED_DOCKER_CONTAINERS=container-1\n'
                            'ALLOWED_SYSTEMD_SERVICES=nginx.service',
                            style: TextStyle(
                              color: AppColors.neonGold,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Kosongkan allowlist service agar hanya monitoring/log yang tersedia. Setelah edit .env, jalankan ulang helper sudoers untuk systemd sesuai README, lalu: sudo systemctl restart rfmonitor-agent. Jangan publikasikan API_KEY atau JWT_SECRET.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      glowColor: AppColors.neonCyan,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '3 · Tambah dan konfigurasi server',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Gunakan menu Server pada navigasi bawah untuk menambah, mengedit, memilih, atau menghapus profil. Masukkan alamat Agent (contoh http://192.168.1.10:4200), API_KEY dari /opt/rfmonitor-agent/.env, serta alamat Local/Tailscale. Kredensial SSH untuk File Manager tetap diatur pada koneksi SSH.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Panduan lengkap tersedia di README repository server-agent. File Manager dan terminal SSH terhubung langsung melalui LAN/Tailscale, bukan melalui Server Agent.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          AppHeaderBar(
            title: 'SETTINGS',
            subtitle: 'PREFERENCES',
            iconWidget: AppHeaderBar.svgIcon(
              AppIcons.settings,
              AppColors.neonGold,
            ),
            accent: AppColors.neonGold,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                // Notifikasi
                const _SectionLabel('Notifikasi & Tampilan'),
                const SizedBox(height: 8),
                GlassCard(
                  glowColor: AppColors.neonGold,
                  child: Column(
                    children: [
                      _switchTile(
                        Icons.mosque_rounded,
                        'Notifikasi Waktu Sholat (Azan)',
                        _prayerNotif,
                        (v) async {
                          setState(() => _prayerNotif = v);
                          await _settings.setPrayerNotifEnabled(v);
                          if (v)
                            await NotificationService.instance
                                .scheduleUpcomingPrayers();
                        },
                      ),
                      const Divider(color: AppColors.glassBorder, height: 20),
                      _switchTile(
                        Icons.notifications_active_outlined,
                        'Notifikasi Server Down / PM2 Stopped / Overheat',
                        _alertNotif,
                        (v) async {
                          setState(() => _alertNotif = v);
                          await _settings.setAlertNotifEnabled(v);
                        },
                      ),
                      const Divider(color: AppColors.glassBorder, height: 20),
                      _switchTile(
                        Icons.play_circle_outline_rounded,
                        'Autoplay Video Banner (Dashboard)',
                        _bannerAutoplay,
                        (v) async {
                          setState(() => _bannerAutoplay = v);
                          await _settings.setBannerAutoplay(v);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Ambang batas
                const _SectionLabel('Ambang Batas Notifikasi'),
                const SizedBox(height: 4),
                const Text(
                  'Kosongkan untuk menonaktifkan. Notifikasi maksimal 1x/hari per jenis.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  glowColor: AppColors.neonOrange,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _thresholdField(
                        _powerThresholdCtrl,
                        'Batas Biaya Listrik / Bulan (Rp)',
                        Icons.electric_bolt_rounded,
                        () async {
                          await _settings.setPowerThresholdRp(
                            double.tryParse(_powerThresholdCtrl.text) ?? 0,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _thresholdField(
                        _bandwidthThresholdCtrl,
                        'Batas Bandwidth / Bulan (GB)',
                        Icons.wifi_rounded,
                        () async {
                          await _settings.setBandwidthThresholdGB(
                            double.tryParse(_bandwidthThresholdCtrl.text) ?? 0,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // NEW: CPU Temp threshold
                      _thresholdField(
                        _cpuTempCtrl,
                        'Batas Suhu CPU (°C, default 70)',
                        Icons.thermostat_rounded,
                        () async {
                          await _settings.setCpuTempThreshold(
                            double.tryParse(_cpuTempCtrl.text) ?? 70.0,
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Asset media
                const _SectionLabel('Tampilan UI'),
                const SizedBox(height: 8),
                const StylePicker(),
                const SizedBox(height: 4),
                _switchTile(
                  Icons.brightness_6_rounded,
                  'Mode terang',
                  StyleController.instance.isLightMode,
                  (enabled) => StyleController.instance.setLightMode(enabled),
                ),
                const SizedBox(height: 14),
                if (Platform.isWindows) ...[
                  const _SectionLabel('Overlay'),
                  const SizedBox(height: 8),
                  const GlassCard(
                    glowColor: AppColors.neonCyan,
                    child: Text(
                      'Fitur overlay dinonaktifkan pada versi Windows.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else ...[
                  const _SectionLabel('Tombol Bulat (Overlay)'),
                  const SizedBox(height: 8),
                  const BubbleControls(),
                ],
                const SizedBox(height: 20),
                const _SectionLabel('Setup Server Agent'),
                const SizedBox(height: 8),
                GlassCard(
                  glowColor: AppColors.neonCyan,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jalankan pada server Linux dengan Node.js 18+ dan systemd. Installer membuat konfigurasi rahasia dan service otomatis. URL ini mengunduh installer langsung dari repository GitHub RFDEVV/server-agent.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        _agentInstallUrl,
                        style: const TextStyle(
                          color: AppColors.neonCyan,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _copyAgentInstallUrl,
                          icon: const Icon(Icons.copy_rounded, size: 17),
                          label: const Text('Salin URL installer'),
                        ),
                      ),
                      const Divider(color: AppColors.glassBorder),
                      const Text(
                        'Di terminal server:\n'
                        'curl -fsSL $_agentInstallUrl -o install.sh\n'
                        'less install.sh\n'
                        'sudo bash install.sh\n\n'
                        'Setelah selesai, baca API_KEY dari /opt/rfmonitor-agent/.env lalu masukkan ke profil server di aplikasi. Jangan bagikan API_KEY/JWT_SECRET. File Manager dan SSH tetap memakai koneksi SFTP/SSH privat, bukan Server Agent.',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          height: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Background & Video'),
                const SizedBox(height: 8),
                const MediaControls(),
                const SizedBox(height: 20),
                const _SectionLabel('Kostumisasi Aset Media'),
                const SizedBox(height: 8),
                GlassCard(
                  glowColor: AppColors.neonCyan,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Ganti file berikut lalu rebuild aplikasi untuk tampilan custom:',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 10),
                      _AssetRow(
                        path: 'assets/icon/app_icon.png',
                        label: 'App Icon',
                      ),
                      _AssetRow(
                        path: 'assets/video/splash_video.mp4',
                        label: 'Splash Video',
                      ),
                      _AssetRow(
                        path: 'assets/video/banner_video.mp4',
                        label: 'Dashboard Banner Video',
                      ),
                      _AssetRow(
                        path: 'assets/images/cyber_bg.png',
                        label: 'App Background',
                      ),
                      _AssetRow(
                        path: 'assets/images/prayer_bg.jpg',
                        label: 'Jadwal Sholat Background',
                      ),
                      _AssetRow(
                        path: 'assets/audio/azan_custom.mp3',
                        label: 'Azan Notif Sound',
                      ),
                      _AssetRow(
                        path: 'android/app/src/main/res/raw/azan_custom.mp3',
                        label: 'Azan Sound (Android raw)',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Server management (add / edit / remove / switch active) ada di tab Server.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.neonGold,
        ),
      ],
    );
  }

  Widget _thresholdField(
    TextEditingController ctrl,
    String label,
    IconData icon,
    Future<void> Function() onSave,
  ) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.textPrimary),
      onChanged: (_) => onSave(),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.neonOrange),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final String path;
  final String label;
  const _AssetRow({required this.path, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.folder_open, size: 14, color: AppColors.neonCyan),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label\n',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: path,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontFamily: 'Rajdhani',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
