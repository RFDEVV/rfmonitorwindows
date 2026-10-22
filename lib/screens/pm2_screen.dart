import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/log_viewer_sheet.dart';
import '../widgets/app_header_bar.dart';
import '../theme/app_icons.dart';
import '../services/api_service.dart';

class Pm2Screen extends StatefulWidget {
  final ApiService api;
  const Pm2Screen({super.key, required this.api});

  @override
  State<Pm2Screen> createState() => _Pm2ScreenState();
}

class _Pm2ScreenState extends State<Pm2Screen> {
  List<dynamic> _apps = [];
  bool _loading = true;
  String? _error;
  String? _busyApp;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await widget.api.getPm2List();
      setState(() => _apps = apps);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndRun(String name, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgBottom,
        title: Text('$action "$name"?', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'This will run pm2 $action on $name.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm', style: TextStyle(color: _actionColor(action))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyApp = name);
    try {
      await widget.api.pm2Action(name, action);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      setState(() => _busyApp = null);
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return AppColors.neonEmerald;
      case 'stopped':
        return AppColors.amberGold;
      default:
        return AppColors.roseRed;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'start':
        return AppColors.neonEmerald;
      case 'stop':
        return AppColors.roseRed;
      default:
        return AppColors.neonCyan;
    }
  }

  String _uptime(num? ms) {
    if (ms == null) return '-';
    final msInt = ms.toInt();
    if (msInt <= 0) return '-';
    final d = Duration(milliseconds: msInt);
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppHeaderBar(
          title: 'PM2 PROCESS',
          subtitle: 'MONITOR',
          iconWidget: AppHeaderBar.svgIcon(AppIcons.pm2, AppColors.neonGreen),
          accent: AppColors.neonGreen,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.neonCyan,
            backgroundColor: AppColors.bgBottom,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.neonCyan))
                : _error != null
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text('Error: $_error', style: const TextStyle(color: AppColors.roseRed)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _refresh,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonCyan),
                            child: const Text('Try Again', style: TextStyle(color: Colors.black)),
                          ),
                        ],
                      )
                    : _apps.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: const [
                              Center(
                                child: Text(
                                  'No PM2 processes found.',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                            itemCount: _apps.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final app = _apps[i];
                              final String appName = app['name'] ?? 'Unknown';
                              final String status = app['status'] ?? 'errored';
                              final controllable = app['controllable'] == true;
                              final busy = _busyApp == appName;

                              return GlassCard(
                                glowColor: _statusColor(status),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // APP NAME & STATUS BADGE
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            appName,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: _statusColor(status).withOpacity(0.4)),
                                          ),
                                          child: Text(
                                            status.toUpperCase(),
                                            style: TextStyle(
                                              color: _statusColor(status),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    // METRIC CHIPS (SingleChildScrollView agar tidak overflow)
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          _metaChip('CPU ${app['cpu'] ?? 0}%'),
                                          const SizedBox(width: 6),
                                          _metaChip('${app['memoryMB'] ?? 0} MB'),
                                          const SizedBox(width: 6),
                                          _metaChip('Up ${_uptime(app['uptimeMs'])}'),
                                          const SizedBox(width: 6),
                                          _metaChip('${app['restarts'] ?? 0} restarts'),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // ACTION BUTTONS / BUSY INDICATOR
                                    if (busy)
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.neonCyan,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      Row(
                                        children: [
                                          if (controllable) ...[
                                            Expanded(child: _actionButton('Start', 'start', appName)),
                                            const SizedBox(width: 6),
                                            Expanded(child: _actionButton('Stop', 'stop', appName)),
                                            const SizedBox(width: 6),
                                            Expanded(child: _actionButton('Restart', 'restart', appName)),
                                            const SizedBox(width: 6),
                                          ],
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => showLogViewer(
                                                context,
                                                api: widget.api,
                                                type: 'pm2',
                                                name: appName,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(color: AppColors.neonGold.withOpacity(0.6)),
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                              child: const Text(
                                                'Logs',
                                                style: TextStyle(color: AppColors.neonGold, fontSize: 11),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgBottom.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
    );
  }

  Widget _actionButton(String label, String action, String appName) {
    final color = _actionColor(action);
    return OutlinedButton(
      onPressed: () {
        if (!_apps.any(
          (app) => app['name'] == appName && app['controllable'] == true,
        )) {
          return;
        }
        _confirmAndRun(appName, action);
      },
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.6)),
        padding: const EdgeInsets.symmetric(vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}