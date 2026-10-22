import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../theme/app_icons.dart';
import '../widgets/glass_card.dart';
import '../widgets/log_viewer_sheet.dart';
import '../widgets/neon_status_dot.dart';
import '../widgets/add_server_dialog.dart';
import '../models/server_config.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/server_endpoint_resolver.dart';

class ServerScreen extends StatefulWidget {
  final VoidCallback onProfileChanged;
  const ServerScreen({super.key, required this.onProfileChanged});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _storage = StorageService();
  List<ServerConfig> _profiles = [];
  int _activeIndex = 0;
  final Map<String, bool?> _online = {};
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pingAll());
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final profiles = await _storage.loadProfiles();
    final active = await _storage.getActiveProfileIndex();
    setState(() {
      _profiles = profiles;
      _activeIndex = active.clamp(0, profiles.isEmpty ? 0 : profiles.length - 1);
    });
    _pingAll();
  }

  Future<void> _pingAll() async {
    for (final p in _profiles) {
      ServerEndpointResolver.selectReachable(p).then((selected) {
        if (mounted) setState(() => _online[p.id] = selected != null);
      });
    }
  }

  Future<void> _addServer() async {
    final config = await showAddServerDialog(context);
    if (config == null) return;
    final updated = [..._profiles, config];
    await _storage.saveProfiles(updated);
    await _storage.setActiveProfileIndex(updated.length - 1);
    await _load();
    widget.onProfileChanged();
  }

  Future<void> _editServer(int index) async {
    final config = await showAddServerDialog(context, existing: _profiles[index]);
    if (config == null) return;
    final updated = [..._profiles];
    updated[index] = config;
    await _storage.saveProfiles(updated);
    await _load();
    if (index == _activeIndex) widget.onProfileChanged();
  }

  Future<void> _switchTo(int index) async {
    await _storage.setActiveProfileIndex(index);
    setState(() => _activeIndex = index);
    widget.onProfileChanged();
  }

  Future<void> _removeProfile(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.roseRed.withOpacity(0.5)),
        ),
        title: const Text('Hapus Server?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Server "${_profiles[index].displayName}" akan dihapus.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.roseRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final updated = [..._profiles]..removeAt(index);
    await _storage.saveProfiles(updated);
    if (_activeIndex >= updated.length) {
      await _storage.setActiveProfileIndex(updated.isEmpty ? 0 : updated.length - 1);
    }
    await _load();
    widget.onProfileChanged();
  }

  Future<void> _showSpec(ServerConfig config) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SpecSheet(config: config),
    );
  }

  Future<void> _showGenericLogs() async {
    showLogViewer(context, api: ApiService(_profiles[_activeIndex]), type: 'generic', name: 'ALL LOGS');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header dengan logo server yang proper
        _ServerHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.neonCyan,
            backgroundColor: AppColors.bgBottom,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Server List',
                      style: AppTheme.orbitron.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _addServer,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Server'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonCyan.withOpacity(0.15),
                        foregroundColor: AppColors.neonCyan,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.neonCyan.withOpacity(0.4)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_profiles.isEmpty)
                  GlassCard(
                    glowColor: AppColors.neonGold,
                    child: Column(
                      children: [
                        const Icon(Icons.dns_outlined, color: AppColors.textSecondary, size: 40),
                        const SizedBox(height: 10),
                        const Text(
                          'Belum ada server.',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap "+ Add Server" untuk menambahkan.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ..._profiles.asMap().entries.map((e) => _serverTile(e.key, e.value)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _serverTile(int index, ServerConfig config) {
    final active = index == _activeIndex;
    final online = _online[config.id];
    final borderColor = active
        ? AppColors.neonCyan
        : (online == false ? AppColors.roseRed : AppColors.glassBorder);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _switchTo(index),
        child: Container(
          decoration: BoxDecoration(
            color: active
                ? AppColors.neonCyan.withOpacity(0.06)
                : AppColors.glassBase,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: active ? 1.4 : 1),
            boxShadow: active
                ? [BoxShadow(color: AppColors.neonCyan.withOpacity(0.2), blurRadius: 20, spreadRadius: -4)]
                : [],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NeonStatusDot(online: online),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.displayName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          config.baseUrl,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (active)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.neonCyan.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.neonCyan.withOpacity(0.4)),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(color: AppColors.neonCyan, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _iconBtn(Icons.memory_rounded, 'Spec', () => _showSpec(config), AppColors.neonCyan),
                  const SizedBox(width: 8),
                  _iconBtn(Icons.edit_outlined, 'Edit', () => _editServer(index), AppColors.neonGold),
                  const SizedBox(width: 8),
                  _iconBtn(Icons.delete_outline_rounded, 'Hapus', () => _removeProfile(index), AppColors.roseRed),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap, Color color) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 11)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

// Header dengan logo server SVG yang proper
class _ServerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Logo server yang lebih proper dari icons.hub
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.neonCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.neonCyan.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(color: AppColors.neonCyan.withOpacity(0.25), blurRadius: 12),
              ],
            ),
            child: SizedBox(
              width: 26,
              height: 26,
              child: SvgPicture.string(
                AppIcons.server,
                colorFilter: const ColorFilter.mode(AppColors.neonCyan, BlendMode.srcIn),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MULTI-SERVER',
                style: AppTheme.orbitron.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'CONNECTIONS',
                style: AppTheme.chakraPetch.copyWith(
                  color: AppColors.neonCyan,
                  fontSize: 11,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ========== SPEC SHEET ==========
class _SpecSheet extends StatefulWidget {
  final ServerConfig config;
  const _SpecSheet({required this.config});

  @override
  State<_SpecSheet> createState() => _SpecSheetState();
}

class _SpecSheetState extends State<_SpecSheet> {
  Map<String, dynamic>? _spec;
  Map<String, dynamic>? _uptime;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ApiService(widget.config);
      final results = await Future.wait([api.getSpec(), api.getUptime()]);
      if (mounted) {
        setState(() {
          _spec = results[0];
          _uptime = results[1]['data'];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _formatUptime(num seconds) {
    final d = Duration(seconds: seconds.toInt());
    return '${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0E1117),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.neonCyan.withOpacity(0.4)),
          ),
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: $_error', style: const TextStyle(color: AppColors.roseRed)),
                  ),
                )
              : _spec == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.neonCyan))
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.glassBorder,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.config.displayName,
                          style: AppTheme.orbitron.copyWith(
                            color: AppColors.neonCyan,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _section('System', [
                          _row('CPU Model', _spec!['system']['cpuModel']),
                          _row('CPU Cores', '${_spec!['system']['cpuPhysicalCores']} physical / ${_spec!['system']['cpuCores']} logical'),
                          _row('RAM', '${_spec!['system']['totalRamGB']} GB'),
                          _row('OS', '${_spec!['system']['osDistro']} (${_spec!['system']['osArch']})'),
                          _row('Kernel', _spec!['system']['osKernel']),
                          _row('Hostname', _spec!['system']['hostname']),
                          _row('IP Lokal', _formatServerIp(_spec)),
                          _row('IP Publik', _formatPublicIp(_spec)),
                          _row('Uptime', _uptime == null ? '--' : _formatUptime(_uptime!['uptimeSeconds'])),
                        ]),
                        const SizedBox(height: 16),
                        _section(
                          'Storage',
                          (_spec!['storage'] as List).map<Widget>((s) {
                            final name = s['name'] ?? s['device'] ?? '-';
                            final size = s['sizeGB'];
                            final type = s['type'] ?? '-';
                            if ((size as num) <= 0) return const SizedBox.shrink();
                            return _row(name, '$size GB · $type');
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        // Network interfaces
                        if ((_spec!['mounts'] as List?)?.isNotEmpty == true)
                          _section(
                            'Mount Points',
                            (_spec!['mounts'] as List).map<Widget>((m) {
                              return _row(
                                m['mount'] ?? m['fs'],
                                '${m['usedGB']}/${m['sizeGB']} GB (${m['usedPercent']}%)',
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 16),
                        // USB peripherals (keyboard, dll)
                        _section(
                          'USB / Perangkat Terhubung',
                          (_spec!['usbDevices'] as List?)?.isEmpty == true || _spec!['usbDevices'] == null
                              ? [const Text('Tidak ada perangkat USB terdeteksi.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))]
                              : (_spec!['usbDevices'] as List).map<Widget>((u) {
                                  return _row(
                                    u['name'] ?? 'Unknown',
                                    u['vendor'] ?? '-',
                                  );
                                }).toList(),
                        ),
                        const SizedBox(height: 16),
                        // External storage
                        _section(
                          'USB / Storage External',
                          (_spec!['blockDevices'] as List).where((b) => b['removable'] == true).isEmpty
                              ? [const Text('Tidak ada storage removable terdeteksi.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))]
                              : (_spec!['blockDevices'] as List)
                                  .where((b) => b['removable'] == true)
                                  .map<Widget>((b) => _row(
                                        b['label'] ?? b['name'],
                                        '${b['sizeGB']} GB · ${b['fsType'] ?? '-'} · ${b['mount'] ?? 'not mounted'}',
                                      ))
                                  .toList(),
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _section(String title, List<Widget> children) {
    final visible = children.where((w) => w is! SizedBox || (w as SizedBox).height != 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      glowColor: AppColors.neonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  String _formatServerIp(Map<String, dynamic>? spec) {
    if (spec == null) return '--';
    final candidates = <String>[];

    // Ambil ip4/ip6 secara spesifik dari tiap entry networkInterfaces —
    // JANGAN rekursif ke semua string (mac/iface/type ikut kebawa & bikin rusak tampilan).
    final ifaces = spec['networkInterfaces'] ?? spec['interfaces'] ?? spec['network'];
    if (ifaces is List) {
      for (final item in ifaces) {
        if (item is Map) {
          final ip4 = item['ip4'];
          final ip6 = item['ip6'];
          if (ip4 is String && ip4.isNotEmpty) candidates.add(ip4);
          if (ip6 is String && ip6.isNotEmpty) candidates.add(ip6);
        } else if (item is String && item.isNotEmpty) {
          candidates.add(item);
        }
      }
    }

    void addIfString(dynamic v) { if (v is String && v.isNotEmpty) candidates.add(v); }
    addIfString(spec['localIp']);
    addIfString(spec['ip']);
    if (spec['ips'] is List) {
      for (final v in spec['ips']) addIfString(v);
    }

    final localIps = candidates.where((ip) => RegExp(r'^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)').hasMatch(ip)).toList();
    if (localIps.isNotEmpty) return localIps.toSet().join(', ');
    return candidates.isNotEmpty ? candidates.toSet().join(', ') : '--';
  }

  String _formatPublicIp(Map<String, dynamic>? spec) {
    if (spec == null) return '--';
    final candidates = <String>[];

    void addIfString(dynamic v) { if (v is String && v.isNotEmpty) candidates.add(v); }
    addIfString(spec['publicIp']);
    addIfString(spec['externalIp']);
    addIfString(spec['wanIp']);
    addIfString(spec['public_ip']);
    addIfString(spec['external_ip']);
    addIfString(spec['wan_ip']);
    addIfString(spec['ip']);

    final filtered = candidates.where((ip) => !RegExp(r'^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)').hasMatch(ip)).toList();
    return filtered.isNotEmpty ? filtered.toSet().join(', ') : '--';
  }

  Widget _row(String? label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label ?? '-', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          Expanded(
            child: Text(
              value ?? '-',
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
