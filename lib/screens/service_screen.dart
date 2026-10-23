import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/log_viewer_sheet.dart';
import '../widgets/app_header_bar.dart';
import '../theme/app_icons.dart';
import '../services/api_service.dart';

/// "Service" tab — auto-detects PM2 apps, Docker containers, and (opt-in)
/// systemd units from the agent's /services/list endpoint. No manual name
/// entry required; everything the agent reports just shows up here.
class ServiceScreen extends StatefulWidget {
  final ApiService api;
  const ServiceScreen({super.key, required this.api});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _services = [];
  bool _loading = true;
  String? _error;
  String? _busyKey;
  String _filter = 'all'; // all | pm2 | docker | systemd

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (mounted) {
      setState(() {
        if (showLoading) _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.api.getServicesList();
      if (!mounted) return;
      setState(() => _services = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _act(Map item, String action) async {
    if (_busyKey != null) return;
    final key = '${item['type']}:${item['name']}';
    setState(() => _busyKey = key);
    try {
      await widget.api.serviceAction(item['type'], item['name'], action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Perintah $action untuk ${item['name']} diterima Server Agent.',
            ),
          ),
        );
      }
      await _refresh(showLoading: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Perintah service gagal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _showLogs(Map item) async {
    showLogViewer(context,
        api: widget.api, type: item['type'], name: item['name']);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'online':
        return AppColors.neonGreen;
      case 'stopped':
        return AppColors.neonGold;
      default:
        return AppColors.roseRed;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'pm2':
        return AppColors.neonGreen;
      case 'docker':
        return AppColors.neonCyan;
      default:
        return AppColors.neonGold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'all'
        ? _services
        : _services.where((s) => s['type'] == _filter).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.neonCyan,
      backgroundColor: AppColors.bgBottom,
      child: Column(
        children: [
          AppHeaderBar(
            title: 'SERVICE CONTROL',
            subtitle: 'PM2 · DOCKER · SYSTEMD',
            iconWidget:
                AppHeaderBar.svgIcon(AppIcons.service, AppColors.neonGold),
            accent: AppColors.neonGold,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _filterChip('All', 'all'),
                  _filterChip('PM2', 'pm2'),
                  _filterChip('Docker', 'docker'),
                  _filterChip('systemd', 'systemd'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.neonCyan))
                : _error != null
                    ? ListView(padding: const EdgeInsets.all(24), children: [
                        Text('Error: $_error',
                            style: const TextStyle(color: AppColors.roseRed))
                      ])
                    : filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: const [
                                Text(
                                    'No services auto-detected yet. Configure ALLOWED_PM2_APPS / ALLOWED_SYSTEMD_SERVICES on the agent, or install Docker.',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)),
                              ])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _serviceCard(filtered[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.neonGold.withOpacity(0.18)
              : AppColors.glassBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.neonGold : AppColors.glassBorder),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? AppColors.neonGold : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _serviceCard(Map item) {
    final key = '${item['type']}:${item['name']}';
    final busy = _busyKey == key;
    final status = (item['status'] ?? 'unknown').toString();
    final controllable = item['controllable'] == true;
    return GlassCard(
      glowColor: _statusColor(status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: _typeColor(item['type']).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(item['type'].toString().toUpperCase(),
                    style: TextStyle(
                        color: _typeColor(item['type']),
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(item['name'] ?? '-',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(status,
                    style:
                        TextStyle(color: _statusColor(status), fontSize: 11)),
              ),
            ],
          ),
          if (item['detail'] != null) ...[
            const SizedBox(height: 6),
            Text(item['detail'],
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
          if (item['cpuPercent'] != null || item['memoryMB'] != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (item['cpuPercent'] != null)
                  _metaChip('CPU ${item['cpuPercent']}%'),
                if (item['memoryMB'] != null)
                  _metaChip('${item['memoryMB']} MB'),
                if (item['restarts'] != null)
                  _metaChip('${item['restarts']} restarts'),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (!controllable) ...[
            Text(
              'Status allowlist dari daftar belum mengizinkan kontrol. Permintaan tetap dikirim ke Server Agent agar izin terbaru diperiksa; alasan penolakan akan ditampilkan.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (busy)
            const Center(
                child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.neonCyan)))
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 480 ? 2 : 4;
                final buttonWidth =
                    (constraints.maxWidth - 8 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: buttonWidth,
                      child: _actionBtn(
                        'Start',
                        () => _act(item, 'start'),
                        AppColors.neonGreen,
                        tooltip: 'Aktifkan service',
                      ),
                    ),
                    SizedBox(
                      width: buttonWidth,
                      child: _actionBtn(
                        'Stop',
                        () => _act(item, 'stop'),
                        AppColors.roseRed,
                        tooltip: 'Hentikan service',
                      ),
                    ),
                    SizedBox(
                      width: buttonWidth,
                      child: _actionBtn(
                        'Restart',
                        () => _act(item, 'restart'),
                        AppColors.neonCyan,
                        tooltip: 'Mulai ulang service',
                      ),
                    ),
                    SizedBox(
                      width: buttonWidth,
                      child: _actionBtn(
                        'Logs',
                        () => _showLogs(item),
                        AppColors.neonGold,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _metaChip(String text) => Text(text,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11));

  Widget _actionBtn(
    String label,
    VoidCallback? onTap,
    Color color, {
    String? tooltip,
  }) {
    final actionInProgress = _busyKey != null;
    final effectiveOnTap = actionInProgress ? null : onTap;
    return Tooltip(
      message: actionInProgress
          ? 'Tunggu aksi yang sedang berjalan selesai'
          : tooltip ?? label,
      child: OutlinedButton(
        onPressed: effectiveOnTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
              color: color.withOpacity(effectiveOnTap == null ? 0.3 : 0.75)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 13)),
      ),
    );
  }
}
