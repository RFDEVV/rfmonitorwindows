import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_bottom_nav.dart';
import '../widgets/cyber_background.dart';
import '../models/server_config.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import '../services/overlay_service.dart';
import '../services/settings_store.dart';
import '../services/server_endpoint_resolver.dart';
import 'dashboard_screen.dart';
import 'pm2_screen.dart';
import 'service_screen.dart';
import 'power_screen.dart';
import 'server_screen.dart';
import 'speedtest_screen.dart';
import 'settings_screen.dart';
import 'file_manager_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  ServerConfig? _config;
  ServerConfig? _configuredConfig;
  ApiService? _api;
  SocketService? _socket;
  bool _loading = true;
  String? _loadError;
  bool _secureStorageCorrupted = false;
  StreamSubscription? _eventSub;
  StreamSubscription? _connSub;
  bool _downNotified = false;
  // Notifikasi "server terputus" HANYA boleh muncul saat app aktif di
  // foreground (sedang dibuka/dilihat). Saat di-background/minimize, hanya
  // notifikasi sholat & status service (PM2/docker/systemd) yang boleh
  // jalan bebas — supaya tidak ada spam "server down" berulang ketika HP
  // sedang tidak dipakai / app di-minimize.
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (Platform.isWindows) {
      if (state == AppLifecycleState.resumed) {
        unawaited(_refreshActiveEndpoint());
      }
    } else if (state == AppLifecycleState.resumed) {
      OverlayService.close(); // app dibuka lagi → tombol bulat disembunyikan
      unawaited(_refreshActiveEndpoint());
    } else if (state == AppLifecycleState.paused && _config != null) {
      final cfg = _config!;
      OverlayService.isAutoEnabled().then((on) {
        if (on) OverlayService.showBubble(cfg);
      });
    }
    if (_isForeground) {
      // Balik ke foreground → reset guard supaya kalau memang masih down,
      // notifikasi bisa muncul lagi (sekali), bukan dianggap sudah pernah.
      _downNotified = false;
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _secureStorageCorrupted = false;
      });
    }
    try {
      final storage = StorageService();
      final profiles = await storage.loadProfiles().timeout(
            const Duration(seconds: 8),
          );
      final activeIndex = await storage.getActiveProfileIndex().timeout(
            const Duration(seconds: 4),
          );
      final configuredConfig = profiles.isNotEmpty
          ? profiles[activeIndex.clamp(0, profiles.length - 1)]
          : null;
      final config = configuredConfig == null
          ? null
          : await ServerEndpointResolver.selectReachable(configuredConfig) ??
              configuredConfig;

      if (!mounted) return;
      setState(() {
        _configuredConfig = configuredConfig;
        _config = config;
        if (configuredConfig == null) _index = 7;
        if (config != null) {
          _api = ApiService(config);
          _socket = SocketService(config, _api!);
          _socket!.connect();
          _wireNotifications(config.displayName);
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint('Unable to load server profiles: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _secureStorageCorrupted = e is SecureStorageCorruptedException;
          _loadError = _secureStorageCorrupted
              ? 'Data konfigurasi terenkripsi rusak dan tidak bisa dibaca. Kamu bisa mencoba lagi atau menghapus data login yang rusak untuk mengatur ulang server.'
              : e.toString();
        });
      }
    }
  }

  Future<void> _refreshActiveEndpoint() async {
    final configured = _configuredConfig;
    if (configured == null) return;
    try {
      final selected =
          await ServerEndpointResolver.selectReachable(configured) ??
              configured;
      if (!mounted || selected.baseUrl == _config?.baseUrl) return;
      _socket?.dispose();
      setState(() {
        _config = selected;
        _api = ApiService(selected);
        _socket = SocketService(selected, _api!);
        _socket!.connect();
      });
      _wireNotifications(selected.displayName);
    } catch (error) {
      debugPrint('Unable to refresh preferred server endpoint: $error');
    }
  }

  Future<void> _recoverSecureStorage() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.bgBottom,
            title: const Text(
              'Atur ulang data aman?',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: const Text(
              'Profil server, kredensial SSH tersimpan, dan sidik jari host SSH di perangkat ini akan dihapus. Kamu perlu memasukkan ulang data tersebut.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Hapus dan atur ulang',
                  style: TextStyle(color: AppColors.roseRed),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await StorageService().clearUnreadableProfileData();
      if (!mounted) return;
      setState(() => _secureStorageCorrupted = false);
      await _load();
    } catch (error) {
      debugPrint('Unable to reset unreadable secure storage: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Pemulihan gagal: $error. Coba mulai ulang aplikasi.';
        });
      }
    }
  }

  void _wireNotifications(String serverName) {
    _eventSub?.cancel();
    _connSub?.cancel();
    _downNotified = false;

    _eventSub = _socket?.eventStream.listen((event) async {
      // Event 'speedtest_progress' lewat channel yang sama (untuk update
      // jarum speedometer realtime) — JANGAN diproses sebagai event
      // service, atau bisa spam notifikasi palsu tiap ~200ms saat speedtest.
      if (event['kind'] == 'speedtest_progress') return;
      final settings = SettingsStore();
      if (await settings.getAlertNotifEnabled()) {
        await NotificationService.instance.showServiceEvent(event);
      }
    });

    _connSub = _socket?.stateStream.listen((state) async {
      final settings = SettingsStore();
      if (!await settings.getAlertNotifEnabled()) return;
      // Notif "server terputus" cuma boleh muncul di foreground — di
      // background/minimize, biarkan senyap (service/PM2 notif tetap jalan
      // bebas lewat _eventSub di atas, tidak digate lifecycle).
      if (state == SocketConnState.disconnected &&
          !_downNotified &&
          _isForeground) {
        _downNotified = true;
        await NotificationService.instance.showServerDown(serverName);
      } else if (state == SocketConnState.connected) {
        _downNotified = false;
      }
    });

    // Prime the prayer-notification schedule once a server context exists.
    SettingsStore().getPrayerNotifEnabled().then((enabled) {
      if (enabled) NotificationService.instance.scheduleUpcomingPrayers();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSub?.cancel();
    _connSub?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _onProfileChanged() async {
    _socket?.dispose();
    setState(() => _loading = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CyberBackground(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.neonCyan),
        ),
      );
    }

    if (_loadError != null) {
      return CyberBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.roseRed,
                  size: 40,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Gagal memuat konfigurasi tersimpan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Coba lagi'),
                ),
                if (_secureStorageCorrupted) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _recoverSecureStorage,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Pulihkan data tersimpan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.roseRed,
                      side: const BorderSide(color: AppColors.roseRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (_config == null || _api == null || _socket == null) {
      final initialScreen = _index == 4
          ? ServerScreen(onProfileChanged: _onProfileChanged)
          : const SettingsScreen(firstRun: true);
      return _buildResponsiveShell(initialScreen);
    }

    final screens = [
      DashboardScreen(api: _api!, socket: _socket!, config: _config!),
      Pm2Screen(api: _api!),
      ServiceScreen(api: _api!),
      PowerScreen(api: _api!),
      ServerScreen(onProfileChanged: _onProfileChanged),
      FileManagerScreen(config: _config!),
      SpeedtestScreen(api: _api!, socket: _socket),
      SettingsScreen(firstRun: false, onProfileChanged: _onProfileChanged),
    ];

    return _buildResponsiveShell(screens[_index]);
  }

  Widget _buildResponsiveShell(Widget screen) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideNavigation =
            Platform.isWindows && constraints.maxWidth >= 900;
        final content = Platform.isWindows
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: screen,
                ),
              )
            : screen;
        return Scaffold(
          extendBody: !useSideNavigation,
          body: Row(
            children: [
              if (useSideNavigation)
                GlassSideNav(
                  currentIndex: _index,
                  onTap: (index) => setState(() => _index = index),
                ),
              Expanded(
                child: CyberBackground(
                  child: SafeArea(child: content),
                ),
              ),
            ],
          ),
          bottomNavigationBar: useSideNavigation
              ? null
              : GlassBottomNav(
                  currentIndex: _index,
                  onTap: (index) => setState(() => _index = index),
                ),
        );
      },
    );
  }
}
