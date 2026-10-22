import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_theme.dart';
import '../widgets/video_banner.dart';
import '../widgets/glass_card.dart';
import '../widgets/prayer_weather_card.dart';
import '../widgets/app_header_bar.dart';
import '../theme/app_icons.dart';
import '../theme/app_style.dart';
import '../services/overlay_service.dart';
import '../widgets/status_hero_card.dart';
import '../widgets/metric_bar_card.dart';
import '../widgets/ping_history_card.dart';
import '../models/server_config.dart';
import '../models/ram_metrics.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/settings_store.dart';
import '../services/notification_service.dart';

final _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

class DashboardScreen extends StatefulWidget {
  final ApiService api;
  final SocketService socket;
  final ServerConfig config;

  const DashboardScreen({
    super.key,
    required this.api,
    required this.socket,
    required this.config,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final _cpuHistory = Queue<double>();
  final _ramHistory = Queue<double>();
  final _diskHistory = Queue<double>();
  static const _maxPoints = 120; // 120 × 3 dtk = 6 menit terakhir
  static const _maxPingTicks = 40;

  Map<String, dynamic>? _latest;
  DateTime? _uptimeStart;
  String _uptimeDisplay = '--:--:--';
  SocketConnState _connState = SocketConnState.connecting;
  final List<bool?> _pingTicks = [];

  Map<String, dynamic>? _powerSummary;
  Map<String, dynamic>? _networkSummary;
  bool _powerLoadFailed = false;
  bool _networkLoadFailed = false;

  StreamSubscription? _metricsSub;
  StreamSubscription? _stateSub;
  Timer? _summaryTimer;
  Timer? _pingTickTimer;
  Timer? _uptimeTimer;
  Timer? _topTimer;

  Map<String, dynamic>?
      _spec; // spesifikasi server (apa adanya dari /system/spec)
  Map<String, dynamic>? _top; // proses terberat + direktori terbesar
  bool _foreground = true;

  double _tempThresholdC = 70.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _loadSpec();
    _loadHistory();

    _metricsSub = widget.socket.metricsStream.listen(_onMetrics);
    _stateSub = widget.socket.stateStream.listen(_onConnState);

    // Uptime ticker tiap detik
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _uptimeDisplay = _calcUptime());
    });

    // Ping tick tiap 3 detik
    _pingTickTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _pingTicks.add(_connState == SocketConnState.connected);
        if (_pingTicks.length > _maxPingTicks) _pingTicks.removeAt(0);
      });
    });

    _refreshSummaries();
    _summaryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_foreground) _refreshSummaries();
    });

    // Proses terberat realtime (payload ~1KB) — berhenti saat app di background
    _refreshTop();
    _topTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_foreground) _refreshTop();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refreshTop();
      _loadHistory(); // isi ulang grafik yang terlewat saat di background
    }
  }

  Future<void> _loadSpec() async {
    try {
      final spec = await widget.api.getSpec();
      if (mounted) setState(() => _spec = spec);
    } catch (_) {
      /* kartu spek menampilkan '--' */
    }
  }

  /// Isi grafik dengan 6 menit terakhir dari SERVER (bukan mulai kosong saat app dibuka).
  Future<void> _loadHistory() async {
    try {
      final h = await widget.api.getMetricsHistory(minutes: 6);
      List<double> col(String k) => ((h[k] as List?) ?? const [])
          .map((e) => (e as num?)?.toDouble() ?? 0.0)
          .toList();
      final cpu = col('cpu'), ram = col('ram'), disk = col('disk');
      if (!mounted) return;
      setState(() {
        _cpuHistory
          ..clear()
          ..addAll(cpu);
        _ramHistory
          ..clear()
          ..addAll(ram);
        _diskHistory
          ..clear()
          ..addAll(disk);
        while (_cpuHistory.length > _maxPoints) _cpuHistory.removeFirst();
        while (_ramHistory.length > _maxPoints) _ramHistory.removeFirst();
        while (_diskHistory.length > _maxPoints) _diskHistory.removeFirst();
      });
    } catch (_) {
      /* grafik tetap terisi dari WebSocket */
    }
  }

  Future<void> _refreshTop() async {
    try {
      final t = await widget.api.getTop();
      if (mounted) setState(() => _top = t);
    } catch (_) {
      /* biarkan data terakhir */
    }
  }

  Future<void> _loadSettings() async {
    final s = SettingsStore();
    final t = await s.getCpuTempThreshold();
    if (mounted) setState(() => _tempThresholdC = t);
  }

  void _onConnState(SocketConnState s) {
    if (!mounted) return;
    setState(() {
      _connState = s;
      if (s == SocketConnState.connected) _uptimeStart ??= DateTime.now();
      if (s == SocketConnState.disconnected) _uptimeStart = null;
    });
  }

  void _onMetrics(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _latest = data;
      _push(_cpuHistory, (data['cpu']?['usagePercent'] ?? 0).toDouble());
      _push(_ramHistory, (data['ram']?['usedPercent'] ?? 0).toDouble());
      _push(_diskHistory, (data['disk']?['usedPercent'] ?? 0).toDouble());
    });
    _checkCpuTemp(data);
  }

  void _push(Queue<double> q, double v) {
    q.addLast(v);
    if (q.length > _maxPoints) q.removeFirst();
  }

  Future<void> _refreshSummaries() async {
    try {
      final p = await widget.api.getPowerSummary();
      if (mounted)
        setState(() {
          _powerSummary = p['data'];
          _powerLoadFailed = false;
        });
      _checkPowerThreshold(p['data']);
    } catch (_) {
      if (mounted) setState(() => _powerLoadFailed = true);
    }
    try {
      final n = await widget.api.getNetworkSummary();
      if (mounted)
        setState(() {
          _networkSummary = n['data'];
          _networkLoadFailed = false;
        });
      _checkBandwidthThreshold(n['data']);
    } catch (_) {
      if (mounted) setState(() => _networkLoadFailed = true);
    }
  }

  Future<void> _checkCpuTemp(Map<String, dynamic> data) async {
    final t = (data['cpu']?['tempC'] as num?)?.toDouble() ?? 0;
    if (t <= 0 || t < _tempThresholdC) return;
    final s = SettingsStore();
    if (!await s.getAlertNotifEnabled()) return;
    if (await s.shouldNotifyCpuTempToday()) {
      await NotificationService.instance.showCpuOverheat(
        widget.config.displayName,
        t,
      );
    }
  }

  Future<void> _checkPowerThreshold(Map<String, dynamic>? data) async {
    if (data == null) return;
    final s = SettingsStore();
    final lim = await s.getPowerThresholdRp();
    if (lim <= 0) return;
    final cost = (data['monthTotalCostRp'] ?? 0).toDouble();
    if (cost >= lim && await s.shouldNotifyPowerThresholdToday()) {
      await NotificationService.instance.showThresholdAlert(
        title: '⚡ Ambang Batas Listrik',
        body:
            '${widget.config.displayName}: ${_rupiah.format(cost)} ≥ ${_rupiah.format(lim)}',
        id: 99003,
      );
    }
  }

  Future<void> _checkBandwidthThreshold(Map<String, dynamic>? data) async {
    if (data == null) return;
    final s = SettingsStore();
    final lim = await s.getBandwidthThresholdGB();
    if (lim <= 0) return;
    final gb = (data['monthGB'] ?? 0).toDouble();
    if (gb >= lim && await s.shouldNotifyBandwidthThresholdToday()) {
      await NotificationService.instance.showThresholdAlert(
        title: '📶 Ambang Batas Bandwidth',
        body:
            '${widget.config.displayName}: ${gb.toStringAsFixed(1)} GB ≥ ${lim.toStringAsFixed(0)} GB',
        id: 99004,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _topTimer?.cancel();
    _metricsSub?.cancel();
    _stateSub?.cancel();
    _summaryTimer?.cancel();
    _pingTickTimer?.cancel();
    _uptimeTimer?.cancel();
    super.dispose();
  }

  String _calcUptime() {
    if (_uptimeStart == null) return '--:--:--';
    final d = DateTime.now().difference(_uptimeStart!);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  String? _ramSublabel() {
    final r = _latest?['ram'] as Map?;
    if (r == null) return null;
    final used = r['usedMB'] ?? r['usedGB'];
    final total = r['totalMB'] ?? r['totalGB'];
    if (used == null || total == null) return null;
    final unit = r['usedMB'] != null ? 'MB' : 'GB';
    return '$used$unit / $total$unit · sisa ${RamMetrics.freeLabel(r)}';
  }

  double _tempC() => (_latest?['cpu']?['tempC'] as num?)?.toDouble() ?? 0;

  Color _tempColor(double t) {
    if (t <= 0) return AppColors.textSecondary;
    if (t < 50) return AppColors.neonGreen;
    if (t < _tempThresholdC * 0.85) return AppColors.neonGold;
    return AppColors.roseRed;
  }

  // ── Reconnect ──────────────────────────────────────────────────────────────
  void _reconnect() {
    widget.socket.disconnect();
    Future.delayed(
      const Duration(milliseconds: 300),
      () => widget.socket.connect(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = _connState == SocketConnState.connected
        ? true
        : (_connState == SocketConnState.connecting ? null : false);
    final pingDrops = _pingTicks.where((t) => t == false).length;
    final tempC = _tempC();

    return Column(
      children: [
        AppHeaderBar(
          title: widget.config.displayName.toUpperCase(),
          subtitle: 'MONITOR',
          iconWidget: AppHeaderBar.svgIcon(
            AppIcons.dashboard,
            online == true ? AppColors.neonGreen : AppColors.roseRed,
          ),
          accent: online == true ? AppColors.neonGreen : AppColors.roseRed,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!Platform.isWindows)
                IconButton(
                  onPressed: _goBubble,
                  icon: const Icon(
                    Icons.bubble_chart_rounded,
                    color: AppColors.neonCyan,
                    size: 22,
                  ),
                  tooltip: 'Jadikan tombol bulat',
                ),
              IconButton(
                onPressed: _refreshSummaries,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshSummaries,
            color: AppColors.neonCyan,
            backgroundColor: AppColors.bgBottom,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _specCard(),
                const SizedBox(height: 14),
                _resourceCard(),
                const SizedBox(height: 14),
                const VideoBanner(),
                const SizedBox(height: 14),

                // Status card dengan reconnect button
                StatusHeroCard(
                  online: online,
                  connState: _connState,
                  onReconnect: _reconnect,
                ),
                const SizedBox(height: 14),

                // Stat tiles (Session / CPU Temp / Ping Drops)
                _statTileRow(pingDrops, tempC),
                const SizedBox(height: 16),

                // CPU
                MetricBarCard(
                  icon: Icons.memory_rounded,
                  label: 'CPU USAGE',
                  percent: (_latest?['cpu']?['usagePercent'] ?? 0).toDouble(),
                  history: _cpuHistory.toList(),
                  color: AppColors.roseRed,
                ),
                _coreRow(),
                const SizedBox(height: 14),

                // RAM — real data, null-safe
                MetricBarCard(
                  icon: Icons.developer_board,
                  label: 'RAM USAGE',
                  sublabel: _ramSublabel(),
                  percent: (_latest?['ram']?['usedPercent'] ?? 0).toDouble(),
                  history: _ramHistory.toList(),
                  color: AppColors.neonCyan,
                ),
                const SizedBox(height: 14),

                // Disk
                MetricBarCard(
                  icon: Icons.storage_rounded,
                  label: 'DISK USAGE',
                  percent: (_latest?['disk']?['usedPercent'] ?? 0).toDouble(),
                  history: _diskHistory.toList(),
                  color: AppColors.neonGold,
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Grafik = 6 menit terakhir dari server (interval 3 dtk)',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Proses & direktori terberat
                _topCard(),
                const SizedBox(height: 16),

                // Prayer/Weather
                const PrayerWeatherCard(),
                const SizedBox(height: 16),

                // Listrik (real dari powerstat)
                _powerCard(),
                const SizedBox(height: 16),

                // Bandwidth (real dari vnstat)
                _networkCard(),
                const SizedBox(height: 16),

                // Ping history
                PingHistoryCard(ticks: _pingTicks),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _goBubble() async {
    if (Platform.isWindows) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!await OverlayService.requestPermission()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Izin "Tampil di atas aplikasi lain" diperlukan'),
        ),
      );
      return;
    }
    final ok = await OverlayService.showBubble(widget.config);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Gagal menampilkan tombol bulat')),
      );
      return;
    }
    await OverlayService.goHome();
  }

  String _powerSourceLabel(String? src) {
    if (src == null || src == 'none') return 'belum ada data';
    if (src == 'powerstat') return 'powerstat (RAPL, ukur nyata)';
    if (src.startsWith('meter:'))
      return 'colokan pintar ${src.substring(6)} (ukur nyata)';
    if (src == 'estimate')
      return 'ESTIMASI dari beban CPU — tidak ada sensor daya';
    return src;
  }

  // ── Ringkasan sumber daya: sisa RAM & disk, listrik (W, kWh), jaringan ───────
  Widget _resourceCard() {
    double d(dynamic x) => (x as num?)?.toDouble() ?? 0;
    final ram = (_latest?['ram'] as Map?) ?? const {};
    final disk = (_latest?['disk'] as Map?) ?? const {};
    final net = (_latest?['network'] as Map?) ?? const {};
    final pw = (_latest?['power'] as Map?) ?? const {};
    final ps = _powerSummary;
    final watts = (pw['currentWatts'] ?? ps?['currentWatts']) as num?;
    final src = (pw['source'] ?? ps?['source'])?.toString();
    final estimate = src == 'estimate';
    final swapTotal = (ram['swapTotalMB'] as num?)?.toInt() ?? 0;

    String rate(dynamic bytes) {
      final b = d(bytes);
      return b >= 1048576
          ? '${(b / 1048576).toStringAsFixed(1)} MB/s'
          : '${(b / 1024).toStringAsFixed(0)} KB/s';
    }

    Widget tile(
      IconData icon,
      Color c,
      String title,
      String value,
      String sub,
    ) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(AppStyleKit.isNeo ? 10 : 12),
              border: Border.all(color: c.withOpacity(0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: c, size: 14),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: c,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        );

    return GlassCard(
      glowColor: AppColors.neonOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SUMBER DAYA SERVER',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              tile(
                Icons.bolt_rounded,
                AppColors.neonOrange,
                'DAYA',
                watts == null ? '-- W' : '${watts.toStringAsFixed(1)} W',
                _powerSourceLabel(src),
              ),
              const SizedBox(width: 8),
              tile(
                Icons.electric_meter_rounded,
                AppColors.neonGold,
                'LISTRIK',
                ps == null
                    ? '-- kWh'
                    : '${d(ps['todayKwh']).toStringAsFixed(3)} kWh',
                ps == null
                    ? 'memuat…'
                    : 'hari ini · bulan ${d(ps['monthKwh']).toStringAsFixed(2)} kWh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              tile(
                Icons.developer_board,
                AppColors.neonCyan,
                'SISA RAM',
                RamMetrics.freeLabel(ram),
                RamMetrics.totalMb(ram) == null
                    ? ''
                    : 'dari ${RamMetrics.totalMb(ram)!.round()} MB · terpakai ${d(ram['usedPercent']).toStringAsFixed(0)}%',
              ),
              const SizedBox(width: 8),
              tile(
                Icons.storage_rounded,
                AppColors.neonGreen,
                'SISA DISK',
                disk['freeGB'] == null
                    ? '-- GB'
                    : '${d(disk['freeGB']).toStringAsFixed(1)} GB',
                disk['totalGB'] == null
                    ? ''
                    : 'dari ${d(disk['totalGB']).toStringAsFixed(1)} GB · ${disk['mount'] ?? '/'}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              tile(
                Icons.swap_vert_rounded,
                AppColors.roseRed,
                'JARINGAN',
                '↓ ${rate(net['rxBytesPerSec'])}',
                '↑ ${rate(net['txBytesPerSec'])}',
              ),
              const SizedBox(width: 8),
              tile(
                Icons.memory_rounded,
                AppColors.neonCyan,
                'SWAP',
                swapTotal == 0 ? 'tidak ada' : '${ram['swapUsedMB'] ?? 0} MB',
                swapTotal == 0 ? 'swap tidak aktif' : 'dari $swapTotal MB',
              ),
            ],
          ),
          if (estimate)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Server ini belum punya sensor daya (RAPL/colokan pintar), jadi watt & kWh hanya estimasi. '
                'Pasang powerstat (CPU Intel/AMD) atau isi POWER_METER_URL di agent untuk ukuran nyata.',
                style: TextStyle(
                  color: AppColors.neonGold,
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Spesifikasi server (apa adanya dari server, tanpa diubah) ─────────────
  Widget _specCard() {
    final sys = (_spec?['system'] as Map?)?.cast<String, dynamic>();
    String v(dynamic x) =>
        (x == null || x.toString().isEmpty) ? '--' : x.toString();
    final os = sys == null
        ? '--'
        : [
            sys['osDistro'],
            sys['osRelease'],
            if (sys['osCodename'] != null) '(${sys['osCodename']})',
          ].where((e) => e != null && e.toString().isNotEmpty).join(' ');
    final cores = sys == null
        ? '--'
        : '${v(sys['cpuCores'])} core (${v(sys['cpuPhysicalCores'])} fisik)';
    final ghz = (sys?['cpuSpeedGHz'] as num?) == null
        ? ''
        : ' · ${(sys!['cpuSpeedGHz'] as num).toStringAsFixed(2)} GHz';
    final t = _tempC();
    final up = (_latest?['uptimeSeconds'] as num?)?.toInt();
    String upText() {
      if (up == null) return '--';
      final d = Duration(seconds: up);
      return '${d.inDays}h ${d.inHours % 24}j ${d.inMinutes % 60}m';
    }

    final localIp = _spec?['localIp'];
    final publicIp = _spec?['publicIp'];

    return GlassCard(
      glowColor: AppColors.neonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dns_rounded,
                color: AppColors.neonCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v(sys?['hostname']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.thermostat_rounded, color: _tempColor(t), size: 18),
              const SizedBox(width: 2),
              Text(
                t > 0 ? '${t.toStringAsFixed(1)}°C' : '--',
                style: TextStyle(
                  color: _tempColor(t),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _specLine('OS', '$os · ${v(sys?['osArch'])}'),
          _specLine('Kernel', v(sys?['osKernel'])),
          _specLine('CPU', '${v(sys?['cpuModel'])}$ghz'),
          _specLine('Core', cores),
          _specLine('RAM', sys == null ? '--' : '${v(sys['totalRamGB'])} GB'),
          if (sys?['model'] != null)
            _specLine(
              'Mesin',
              '${v(sys?['manufacturer'])} ${v(sys?['model'])}'.trim(),
            ),
          _specLine('Uptime', upText()),
          _specLine('IP lokal', v(localIp)),
          _specLine('IP publik', v(publicIp)),
        ],
      ),
    );
  }

  Widget _specLine(String k, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(
                k,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                val,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      );

  // ── Persentase per core CPU + load average (data asli dari server) ─────────
  Widget _coreRow() {
    final cpu = _latest?['cpu'] as Map?;
    final cores = ((cpu?['perCore'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final la = ((cpu?['loadAvg'] as List?) ?? const [])
        .map((e) => (e as num).toStringAsFixed(2))
        .toList();
    if (cores.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < cores.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.roseRed.withOpacity(
                  0.10 + 0.25 * (cores[i] / 100),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'C$i ${cores[i]}%',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                ),
              ),
            ),
          if (la.length == 3)
            Text(
              'load ${la.join(' / ')}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  // ── Proses terberat CPU / RAM + direktori terbesar ─────────────────────────
  Widget _topCard() {
    List<Map<String, dynamic>> rows(String k) =>
        ((_top?[k] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
    final byCpu = rows('byCpu'), byMem = rows('byMem');
    final dirsMap = (_top?['dirs'] as Map?)?.cast<String, dynamic>();
    final dirs = ((dirsMap?['items'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final computing = dirsMap?['computing'] == true;
    final updatedAt = (dirsMap?['updatedAt'] as num?)?.toInt() ?? 0;
    final maxGb = dirs.isEmpty
        ? 1.0
        : dirs
            .map((d) => (d['gb'] as num).toDouble())
            .reduce((a, b) => a > b ? a : b);

    Widget title(String t, IconData i, Color c, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Row(
            children: [
              Icon(i, color: c, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t,
                  style: TextStyle(
                    color: c,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        );

    return GlassCard(
      glowColor: AppColors.neonOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(
            'PROSES TERBERAT · CPU',
            Icons.memory_rounded,
            AppColors.roseRed,
          ),
          if (byCpu.isEmpty)
            const Text(
              'Memuat…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          for (final p in byCpu)
            _procRow(
              '${p['name']}',
              '${(p['cpu'] as num).toStringAsFixed(1)}%',
              (p['cpu'] as num).toDouble() / 100,
              AppColors.roseRed,
            ),
          title(
            'PROSES TERBESAR · RAM',
            Icons.developer_board,
            AppColors.neonCyan,
          ),
          for (final p in byMem)
            _procRow(
              '${p['name']}',
              '${p['memMB']} MB',
              (p['memPct'] as num).toDouble() / 100,
              AppColors.neonCyan,
            ),
          title(
            'STORAGE TERBESAR',
            Icons.storage_rounded,
            AppColors.neonGold,
            trailing: computing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.neonGold,
                    ),
                  )
                : InkWell(
                    onTap: () async {
                      try {
                        await widget.api.refreshTopDirs();
                      } catch (_) {}
                      _refreshTop();
                    },
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: AppColors.neonGold,
                      size: 18,
                    ),
                  ),
          ),
          if (dirs.isEmpty)
            Text(
              computing
                  ? 'Menghitung ukuran direktori…'
                  : 'Belum ada data (dihitung di background tiap 10 menit).',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          for (final d in dirs)
            _procRow(
              '${d['path']}',
              '${(d['gb'] as num).toStringAsFixed(1)} GB',
              (d['gb'] as num).toDouble() / maxGb,
              AppColors.neonGold,
            ),
          if (updatedAt > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Direktori dihitung ${DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(updatedAt)).inMinutes} menit lalu (du tidak bisa realtime)',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _procRow(String name, String value, double frac, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac.isNaN ? 0 : frac.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 66,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stat tile row ──────────────────────────────────────────────────────────
  Widget _statTileRow(int pingDrops, double tempC) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _statTile(
              Icons.timer_outlined,
              AppColors.neonCyan,
              _uptimeDisplay,
              'SESSION',
              mono: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statTile(
              Icons.thermostat_rounded,
              _tempColor(tempC),
              tempC > 0 ? '${tempC.toStringAsFixed(1)}°C' : '--°C',
              'CPU TEMP',
              alerting: tempC >= _tempThresholdC,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statTile(
              pingDrops > 0 ? Icons.wifi_off_rounded : Icons.wifi_rounded,
              pingDrops > 5 ? AppColors.roseRed : AppColors.neonOrange,
              '$pingDrops',
              'PING DROPS',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(
    IconData icon,
    Color color,
    String value,
    String label, {
    bool mono = false,
    bool alerting = false,
  }) {
    return NeonCornerCard(
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: mono
                  ? AppTheme.rajdhaniSemiBold.copyWith(
                      color: color,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    )
                  : AppTheme.rajdhaniSemiBold.copyWith(
                      color: color,
                      fontSize: 17,
                    ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTheme.chakraPetch.copyWith(
              color: AppColors.textSecondary,
              fontSize: 8.5,
              letterSpacing: 0.8,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Power card — data dari powerstat (bukan estimasi) ─────────────────────
  Widget _powerCard() {
    final s = _powerSummary;
    if (s == null) {
      return NeonCornerCard(
        color: AppColors.neonOrange,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Konsumsi Listrik',
              style: AppTheme.rajdhaniSemiBold.copyWith(
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            if (!_powerLoadFailed)
              Text(
                'Mengambil data listrik dari server…',
                style: AppTheme.rajdhani.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              )
            else
              Text(
                'Tidak dapat memuat data listrik server.',
                style: AppTheme.rajdhani.copyWith(
                  color: AppColors.roseRed,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      );
    }

    return NeonCornerCard(
      color: AppColors.neonOrange,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Konsumsi Listrik',
                style: AppTheme.rajdhaniSemiBold.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.neonOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${s['currentWatts'] ?? '--'} W · ${s['source'] ?? 'Server'}',
                  style: AppTheme.rajdhani.copyWith(
                    color: AppColors.neonOrange,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _periodTile(
                  'Hari',
                  '${s['todayKwh']} kWh',
                  _rupiah.format(s['todayCostRp']),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _periodTile(
                  'Minggu',
                  '${s['weekKwh']} kWh',
                  _rupiah.format(s['weekCostRp']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _periodTile(
                  'Bulan',
                  '${s['monthKwh']} kWh',
                  _rupiah.format(s['monthElectricityCostRp']),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _periodTile(
                  'Tahun',
                  '${s['yearKwh']} kWh',
                  _rupiah.format(s['yearCostRp']),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.glassBorder, height: 24),
          _costRow(
            'Internet / bulan',
            _rupiah.format(s['monthlyInternetCostRp']),
          ),
          _costRow(
            'Total / bulan',
            _rupiah.format(s['monthTotalCostRp']),
            bold: true,
          ),
          if ((s['history'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: _historyChart(s['history'], 'kwh', AppColors.neonOrange),
            ),
          ],
        ],
      ),
    );
  }

  // ── Network card — data dari vnstat (bukan estimasi) ─────────────────────
  Widget _networkCard() {
    final s = _networkSummary;
    if (s == null) {
      return NeonCornerCard(
        color: AppColors.neonCyan,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Penggunaan Bandwidth',
              style: AppTheme.rajdhaniSemiBold.copyWith(
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            if (!_networkLoadFailed)
              Text(
                'Mengambil data jaringan dari server (vnstat)…',
                style: AppTheme.rajdhani.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              )
            else
              Text(
                'Tidak dapat memuat data vnstat server.',
                style: AppTheme.rajdhani.copyWith(
                  color: AppColors.roseRed,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      );
    }

    return NeonCornerCard(
      color: AppColors.neonCyan,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Penggunaan Bandwidth',
                style: AppTheme.rajdhaniSemiBold.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
              ),
              if (s['source'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.neonCyan.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s['source'],
                    style: AppTheme.rajdhani.copyWith(
                      color: AppColors.neonCyan,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _periodTile('Hari', '${s['todayGB']} GB', null)),
              const SizedBox(width: 8),
              Expanded(child: _periodTile('Minggu', '${s['weekGB']} GB', null)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _periodTile('Bulan', '${s['monthGB']} GB', null)),
              const SizedBox(width: 8),
              Expanded(child: _periodTile('Tahun', '${s['yearGB']} GB', null)),
            ],
          ),
          if ((s['dailyHistory'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: _historyChart(s['dailyHistory'], 'gb', AppColors.neonCyan),
            ),
          ] else if ((s['history'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: _historyChart(s['history'], 'gb', AppColors.neonCyan),
            ),
          ],
          if (_networkUsageWidgets(s).isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: _networkUsageWidgets(s)),
          ],
        ],
      ),
    );
  }

  List<Widget> _networkUsageWidgets(Map<String, dynamic> s) {
    final downloadGb = _networkStatGb(s, _downloadKeys);
    final uploadGb = _networkStatGb(s, _uploadKeys);
    if (downloadGb == null && uploadGb == null) return [];

    return [
      Expanded(child: _periodTile('Download', _formatGb(downloadGb), null)),
      const SizedBox(width: 8),
      Expanded(child: _periodTile('Upload', _formatGb(uploadGb), null)),
    ];
  }

  static const List<String> _downloadKeys = [
    'todayDownloadGB',
    'todayRxGB',
    'downloadGB',
    'rxGB',
    'todayDownloadBytes',
    'todayRxBytes',
    'downloadBytes',
    'rxBytes',
  ];

  static const List<String> _uploadKeys = [
    'todayUploadGB',
    'todayTxGB',
    'uploadGB',
    'txGB',
    'todayUploadBytes',
    'todayTxBytes',
    'uploadBytes',
    'txBytes',
  ];

  double? _networkStatGb(Map<String, dynamic> s, List<String> keys) {
    for (final key in keys) {
      if (!s.containsKey(key)) continue;
      final value = s[key];
      if (value is num) {
        return key.toLowerCase().endsWith('bytes')
            ? value.toDouble() / 1024 / 1024 / 1024
            : value.toDouble();
      }
      if (value is String && value.isNotEmpty) {
        final normalized =
            value.replaceAll(RegExp('[^0-9.,-]'), '').replaceAll(',', '.');
        final parsed = double.tryParse(normalized);
        if (parsed != null) {
          return key.toLowerCase().endsWith('bytes')
              ? parsed / 1024 / 1024 / 1024
              : parsed;
        }
      }
    }
    return null;
  }

  String _formatGb(double? value) {
    if (value == null) return '-- GB';
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} GB';
  }

  Widget _historyChart(List history, String field, Color color) {
    final spots = history.asMap().entries.map((e) {
      final v = (e.value[field] as num?)?.toDouble() ?? 0;
      return FlSpot(e.key.toDouble(), v);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: 0,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodTile(String label, String value, String? costRp) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.chakraPetch.copyWith(
              color: AppColors.textSecondary,
              fontSize: 9.5,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.rajdhaniSemiBold.copyWith(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
          if (costRp != null)
            Text(
              costRp,
              style: AppTheme.rajdhani.copyWith(
                color: AppColors.neonGreen,
                fontSize: 10.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _costRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTheme.rajdhani.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style:
                (bold ? AppTheme.rajdhaniSemiBold : AppTheme.rajdhani).copyWith(
              color: bold ? AppColors.neonGreen : AppColors.textPrimary,
              fontSize: bold ? 16 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
