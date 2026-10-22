import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

/// Log Viewer realtime untuk SEMUA tipe: 'pm2' | 'docker' | 'systemd' | 'generic'.
///
/// - Hanya meminta baris BARU sejak cursor (GET /logs/stream) tiap 2 detik →
///   payload per polling cuma beberapa ratus byte (hemat kuota).
/// - Tombol hapus benar-benar menghapus di SERVER (PM2: file log dikosongkan),
///   jadi log lama tidak muncul lagi setelah refresh berikutnya.
/// - Auto-scroll ke baris terbaru selama user tidak sedang scroll ke atas.
/// - Polling berhenti saat app di background.
Future<void> showLogViewer(
  BuildContext context, {
  required ApiService api,
  required String type,
  required String name,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => LogViewerSheet(api: api, type: type, name: name),
  );
}

class LogViewerSheet extends StatefulWidget {
  final ApiService api;
  final String type;
  final String name;

  const LogViewerSheet({super.key, required this.api, required this.type, required this.name});

  @override
  State<LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<LogViewerSheet> with WidgetsBindingObserver {
  static const _maxLines = 1500;
  static const _pollEvery = Duration(seconds: 2);

  final List<String> _lines = [];
  String? _cursor;
  String? _error;
  bool _loading = true;
  bool _autoRefresh = true;
  bool _inFlight = false;
  bool _foreground = true;
  bool _stickToBottom = true;
  Timer? _timer;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _poll(initial: true);
    _timer = Timer.periodic(_pollEvery, (_) {
      if (_autoRefresh && _foreground && mounted) _poll();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _autoRefresh) _poll();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
    if (nearBottom != _stickToBottom) setState(() => _stickToBottom = nearBottom);
  }

  Future<void> _poll({bool initial = false}) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final chunk = await widget.api.streamLogs(widget.type, widget.name, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        if (chunk.reset) _lines.clear();
        _lines.addAll(chunk.lines);
        if (_lines.length > _maxLines) _lines.removeRange(0, _lines.length - _maxLines);
        _cursor = chunk.cursor ?? _cursor;
        _loading = false;
        _error = null;
      });
      if (_stickToBottom && (chunk.lines.isNotEmpty || initial)) _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // error sesaat saat polling tidak menghapus log yang sudah tampil
        if (_lines.isEmpty) _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _inFlight = false;
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgBottom,
            title: const Text('Hapus Log?', style: TextStyle(color: AppColors.textPrimary)),
            content: Text(
              widget.type == 'pm2'
                  ? 'File log PM2 "${widget.name}" di server akan dikosongkan. Log baru tetap tampil realtime.'
                  : widget.type == 'generic'
                      ? 'Log agent di server akan dihapus.'
                      : 'Log lama disembunyikan; hanya log baru yang tampil setelah ini.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus', style: TextStyle(color: AppColors.roseRed)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      await widget.api.clearLogsFor(widget.type, widget.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menghapus log: $e')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _lines.clear();
      _cursor = null; // server akan mengirim isi terbaru setelah penghapusan
    });
    _stickToBottom = true;
    _poll(initial: true);
  }

  void _copyToClipboard() {
    if (_lines.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Log disalin ke clipboard', style: AppTheme.rajdhani.copyWith(color: AppColors.textPrimary)),
        backgroundColor: AppColors.bgBottom,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  IconData get _typeIcon {
    switch (widget.type) {
      case 'pm2':     return Icons.layers_rounded;
      case 'docker':  return Icons.inventory_2_outlined;
      case 'systemd': return Icons.settings_applications_rounded;
      case 'generic': return Icons.article_outlined;
      default:        return Icons.terminal_rounded;
    }
  }

  String get _typeLabel {
    switch (widget.type) {
      case 'pm2':     return 'PM2';
      case 'docker':  return 'DOCKER';
      case 'systemd': return 'SYSTEMD';
      case 'generic': return 'ALL LOGS';
      default:        return widget.type.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.97,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, _) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C0F14),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.neonGold.withOpacity(0.35)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 10),
            _header(),
            const Divider(color: AppColors.glassBorder, height: 1),
            Expanded(child: _body()),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neonGold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neonGold.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_typeIcon, color: AppColors.neonGold, size: 12),
              const SizedBox(width: 5),
              Text(_typeLabel, style: AppTheme.chakraPetch.copyWith(color: AppColors.neonGold, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.name,
              style: AppTheme.orbitron.copyWith(color: AppColors.neonGold, fontSize: 14, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              if (_autoRefresh) _poll();
            },
            icon: Icon(
              _autoRefresh ? Icons.pause_circle_outline : Icons.play_circle_outline,
              color: _autoRefresh ? AppColors.neonGreen : AppColors.textSecondary,
              size: 22,
            ),
            tooltip: _autoRefresh ? 'Jeda' : 'Lanjut',
          ),
          IconButton(
            onPressed: _clearLogs,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.roseRed, size: 20),
            tooltip: 'Hapus log',
          ),
          IconButton(
            onPressed: _lines.isEmpty ? null : _copyToClipboard,
            icon: const Icon(Icons.copy_rounded, color: AppColors.textSecondary, size: 18),
            tooltip: 'Salin',
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _lines.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.neonGold));
    }
    if (_error != null && _lines.isEmpty) return _errorView();
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Stack(
        children: [
          _lines.isEmpty
              ? const Center(
                  child: Text('Belum ada log. Log baru akan muncul di sini secara realtime.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)))
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: _lines.length,
                    itemBuilder: (_, i) {
                      final raw = _lines[i];
                      final isErr = raw.startsWith('[err] ');
                      final text = raw.length > 2000 ? '${raw.substring(0, 2000)}…' : raw;
                      return Text(
                        text,
                        style: TextStyle(
                          color: isErr ? AppColors.roseRed : const Color(0xFFD7E3D2),
                          fontFamily: 'monospace', // font biasa → mudah dibaca
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      );
                    },
                  ),
                ),
          if (!_stickToBottom && _lines.isNotEmpty)
            Positioned(
              right: 10,
              bottom: 10,
              child: FloatingActionButton.small(
                backgroundColor: AppColors.neonGold,
                onPressed: () {
                  _stickToBottom = true;
                  _jumpToBottom();
                  setState(() {});
                },
                child: const Icon(Icons.arrow_downward_rounded, color: Colors.black),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF080A0D),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${_lines.length} baris', style: AppTheme.rajdhani.copyWith(color: AppColors.textSecondary, fontSize: 10.5)),
          Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: _autoRefresh ? AppColors.neonGreen : AppColors.textSecondary, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(_autoRefresh ? 'Live · 2 dtk · hanya baris baru' : 'Dijeda',
                style: AppTheme.rajdhani.copyWith(color: AppColors.textSecondary, fontSize: 10.5)),
          ]),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.roseRed, size: 36),
          const SizedBox(height: 12),
          Text('Gagal memuat log', style: AppTheme.orbitron.copyWith(color: AppColors.roseRed, fontSize: 13)),
          const SizedBox(height: 8),
          Text(_error ?? '', style: AppTheme.rajdhani.copyWith(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _poll(initial: true);
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Coba Lagi'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.neonCyan, side: const BorderSide(color: AppColors.neonCyan)),
          ),
        ],
      ),
    );
  }
}
