import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_icons.dart';
import '../theme/app_style.dart';
import '../widgets/app_header_bar.dart';
import '../widgets/glass_card.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

/// Speedtest — 100% diukur di SERVER (server ↔ Cloudflare), bukan HP.
/// Jarum bergerak realtime mengikuti progress asli yang di-broadcast server
/// lewat WebSocket tiap ~200 ms (tidak memakai kuota HP untuk tesnya).
class SpeedtestScreen extends StatefulWidget {
  final ApiService api;
  final SocketService? socket;
  const SpeedtestScreen({super.key, required this.api, this.socket});

  @override
  State<SpeedtestScreen> createState() => _SpeedtestScreenState();
}

class _SpeedtestScreenState extends State<SpeedtestScreen> with SingleTickerProviderStateMixin {
  bool _running = false;
  String _phase = '';          // 'ping' | 'download' | 'upload' | ''
  String? _error;

  double? _pingMs;
  double? _downloadMbps;
  double? _uploadMbps;
  double _liveMbps = 0;
  double _scaleMax = 100;      // skala gauge otomatis: 100 → 200 → 500 → 1000 …

  StreamSubscription? _progressSub;
  late final AnimationController _needleCtrl;
  late Animation<double> _needleAnim;

  static const _scales = [100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];

  @override
  void initState() {
    super.initState();
    _needleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _needleAnim = Tween<double>(begin: 0, end: 0).animate(CurvedAnimation(parent: _needleCtrl, curve: Curves.easeOutCubic));

    _progressSub = widget.socket?.eventStream.listen((event) {
      if (!mounted || !_running) return;
      if (event['kind'] != 'speedtest_progress') return;
      final phase = event['phase'] as String?;
      if (phase == null) return;
      final inst = (event['instantMbps'] as num?)?.toDouble() ?? 0;
      setState(() => _phase = phase);
      if (phase == 'download' || phase == 'upload') {
        _liveMbps = inst;
        _animateTo(inst, quick: true);
      }
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _needleCtrl.dispose();
    super.dispose();
  }

  double _niceScale(double v) {
    for (final s in _scales) {
      if (v * 1.12 <= s) return s;
    }
    return _scales.last;
  }

  void _animateTo(double mbps, {bool quick = false}) {
    _scaleMax = math.max(_scaleMax, _niceScale(mbps));
    final target = (mbps / _scaleMax).clamp(0.0, 1.0);
    _needleAnim = Tween<double>(begin: _needleAnim.value, end: target)
        .animate(CurvedAnimation(parent: _needleCtrl, curve: Curves.easeOutCubic));
    _needleCtrl.duration = Duration(milliseconds: quick ? 220 : 700);
    _needleCtrl.forward(from: 0);
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _phase = 'ping';
      _pingMs = null;
      _downloadMbps = null;
      _uploadMbps = null;
      _liveMbps = 0;
      _scaleMax = 100;
    });
    _animateTo(0);

    try {
      final res = await widget.api.runSpeedtest();
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _pingMs = (data['pingMs'] as num?)?.toDouble();
        _downloadMbps = (data['downloadMbps'] as num?)?.toDouble();
        _uploadMbps = (data['uploadMbps'] as num?)?.toDouble();
        _phase = '';
      });
      // jarum berhenti di angka resmi dari server (download), pelan dan halus
      _animateTo(_downloadMbps ?? 0);
      _liveMbps = _downloadMbps ?? 0;
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Timeout — server tidak merespon. Pastikan agent server berjalan.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _phase = '';
        });
      }
    }
  }

  Color get _accent {
    switch (_phase) {
      case 'download':
        return AppColors.neonCyan;
      case 'upload':
        return AppColors.neonGold;
      case 'ping':
        return AppColors.neonGreen;
      default:
        return AppColors.neonGreen;
    }
  }

  String get _phaseText {
    switch (_phase) {
      case 'ping':
        return 'MENGUKUR PING';
      case 'download':
        return 'DOWNLOAD';
      case 'upload':
        return 'UPLOAD';
      default:
        return _downloadMbps != null ? 'SELESAI' : 'SIAP';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppHeaderBar(
          title: 'SPEEDTEST',
          subtitle: 'NETWORK BENCHMARK',
          iconWidget: AppHeaderBar.svgIcon(AppIcons.speedtest, AppColors.neonGreen),
          accent: AppColors.neonGreen,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 21, 110),
            children: [
              _gaugeCard(),
              const SizedBox(height: 16),
              _steps(),
              const SizedBox(height: 18),
              _startButton(),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Diukur oleh SERVER ke internet (Cloudflare) — bukan HP, tidak memakai kuota HP.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                GlassCard(
                  glowColor: AppColors.roseRed,
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.roseRed),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.roseRed, fontSize: 12.5))),
                  ]),
                ),
              ],
              const SizedBox(height: 18),
              Row(children: [
                _result(Icons.podcasts_rounded, 'PING', _pingMs, 'ms', AppColors.neonGreen),
                const SizedBox(width: 10),
                _result(Icons.south_rounded, 'DOWNLOAD', _downloadMbps, 'Mbps', AppColors.neonCyan),
                const SizedBox(width: 10),
                _result(Icons.north_rounded, 'UPLOAD', _uploadMbps, 'Mbps', AppColors.neonGold),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gaugeCard() {
    return GlassCard(
      glowColor: _accent,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      child: LayoutBuilder(builder: (context, c) {
        final r = math.min(c.maxWidth / 2 - 18, 150.0);
        final h = r * 1.5 + 44;
        final center = Offset(c.maxWidth / 2, r + 24);
        return SizedBox(
          height: h,
          width: c.maxWidth,
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _needleAnim,
                builder: (_, __) => CustomPaint(
                  size: Size(c.maxWidth, h),
                  painter: _GaugePainter(
                    value: _needleAnim.value,
                    accent: _accent,
                    scaleMax: _scaleMax,
                    center: center,
                    radius: r,
                    neo: AppStyleKit.isNeo,
                  ),
                ),
              ),
              // angka di bawah hub jarum — widget biasa, tidak bertumpuk dengan gambar gauge
              Positioned(
                left: 0,
                right: 0,
                top: center.dy + 18,
                child: Column(children: [
                  Text(
                    _running || _downloadMbps != null ? _liveMbps.toStringAsFixed(_liveMbps >= 100 ? 0 : 1) : '--',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: r * 0.34, fontWeight: FontWeight.w800, height: 1),
                  ),
                  const SizedBox(height: 2),
                  const Text('Mbps', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text(_phaseText, style: TextStyle(color: _accent, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 2)),
                ]),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _steps() {
    Widget step(String label, String name, bool done, Color c) {
      final active = _running && _phase == name;
      final on = active || done;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? c.withOpacity(active ? 0.22 : 0.10) : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(AppStyleKit.isNeo ? 8 : 20),
            border: Border.all(color: on ? c : Colors.white12, width: AppStyleKit.isNeo ? 2 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (active)
              SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 2, color: c))
            else
              Icon(done ? Icons.check_circle_rounded : Icons.circle_outlined, size: 13, color: on ? c : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: on ? c : AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ]),
        ),
      );
    }

    return Row(children: [
      step('PING', 'ping', _pingMs != null, AppColors.neonGreen),
      const SizedBox(width: 8),
      step('DOWNLOAD', 'download', _downloadMbps != null, AppColors.neonCyan),
      const SizedBox(width: 8),
      step('UPLOAD', 'upload', _uploadMbps != null, AppColors.neonGold),
    ]);
  }

  Widget _startButton() {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: _running ? null : _run,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.neonGreen,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.neonGreen.withOpacity(0.25),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        icon: _running
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black54))
            : const Icon(Icons.play_arrow_rounded, size: 26),
        label: Text(_running ? 'MENGUKUR…' : (_downloadMbps != null ? 'ULANGI TES' : 'MULAI TES')),
      ),
    );
  }

  Widget _result(IconData icon, String label, double? v, String unit, Color c) {
    return Expanded(
      child: GlassCard(
        glowColor: c,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        radius: 16,
        child: Column(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              v == null ? '--' : v.toStringAsFixed(v >= 100 ? 0 : 1),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800, height: 1),
            ),
          ),
          Text(unit, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
      ),
    );
  }
}

/// Gauge 240°: lintasan, busur gradien, tick + angka skala, jarum bercahaya.
class _GaugePainter extends CustomPainter {
  final double value;      // 0..1
  final Color accent;
  final double scaleMax;
  final Offset center;
  final double radius;
  final bool neo;

  const _GaugePainter({
    required this.value,
    required this.accent,
    required this.scaleMax,
    required this.center,
    required this.radius,
    required this.neo,
  });

  static const double _start = 5 * math.pi / 6;   // 150°
  static const double _sweep = 4 * math.pi / 3;   // 240°

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = radius * 0.11;

    // lintasan
    canvas.drawArc(
      rect, _start, _sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = neo ? StrokeCap.butt : StrokeCap.round
        ..color = Colors.white.withOpacity(0.08),
    );

    // busur progres bergradien
    final v = value.clamp(0.0, 1.0);
    if (v > 0.001) {
      canvas.drawArc(
        rect, _start, _sweep * v, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = neo ? StrokeCap.butt : StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: _sweep,
            colors: const [AppColors.neonCyan, AppColors.neonGreen, AppColors.neonGold, AppColors.roseRed],
            transform: const GradientRotation(_start),
          ).createShader(rect),
      );
    }

    // tick + angka skala
    final tickPaint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.35);
    for (var i = 0; i <= 10; i++) {
      final a = _start + _sweep * i / 10;
      final dir = Offset(math.cos(a), math.sin(a));
      final major = i % 2 == 0;
      final p1 = center + dir * (radius - stroke / 2 - 6);
      final p2 = center + dir * (radius - stroke / 2 - (major ? 16 : 11));
      canvas.drawLine(p1, p2, tickPaint);
      if (major) {
        final val = scaleMax * i / 10;
        final tp = TextPainter(
          text: TextSpan(
            text: val >= 1000 ? '${(val / 1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)}k' : val.toStringAsFixed(0),
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lp = center + dir * (radius - stroke / 2 - 30);
        tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // jarum
    final angle = _start + _sweep * v;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final len = radius - stroke - 8;
    final needle = Path()
      ..moveTo(len, 0)
      ..lineTo(-14, -6)
      ..lineTo(-14, 6)
      ..close();
    if (!neo) {
      canvas.drawPath(
        needle,
        Paint()
          ..color = accent.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    canvas.drawPath(needle, Paint()..color = accent);
    if (neo) {
      canvas.drawPath(
        needle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFF4EDE0),
      );
    }
    canvas.restore();

    // hub
    canvas.drawCircle(center, 11, Paint()..color = const Color(0xFF0D0D12));
    canvas.drawCircle(
      center, 11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.accent != accent || old.scaleMax != scaleMax || old.radius != radius || old.neo != neo;
}
