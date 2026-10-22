import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';

/// CPU / RAM / Disk metric card
/// - Font label: Chakra Petch (header)
/// - Font nilai %: Rajdhani SemiBold (sesuai referensi)
/// - Efek neon corner di pojok card
/// - Sparkline realtime terus update
class MetricBarCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final double percent;     // 0–100
  final List<double> history;
  final Color color;

  const MetricBarCard({
    super.key,
    required this.icon,
    required this.label,
    required this.percent,
    required this.history,
    required this.color,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return NeonCornerCard(
      color: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Icon dengan background glow
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTheme.chakraPetch.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sublabel != null)
                      Text(
                        sublabel!,
                        // Rajdhani Regular untuk sublabel nilai
                        style: AppTheme.rajdhani.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              // Percent pill — Rajdhani SemiBold sesuai referensi gambar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8)],
                ),
                child: Text(
                  '${percent.toStringAsFixed(0)}%',
                  style: AppTheme.rajdhaniSemiBold.copyWith(
                    color: color,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _progressBar(),
          const SizedBox(height: 14),
          _sparkline(),
        ],
      ),
    );
  }

  Widget _progressBar() {
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      final fillW = (w * percent.clamp(0, 100) / 100).clamp(0.0, w);
      return SizedBox(
        height: 10,
        child: Stack(alignment: Alignment.centerLeft, children: [
          // Track
          Container(
            width: double.infinity, height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          // Fill gradient
          Container(
            width: fillW, height: 6,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withOpacity(0.5), color]),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)],
            ),
          ),
          // Dot di ujung fill
          Positioned(
            left: (fillW - 5).clamp(0, w - 10),
            child: Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withOpacity(0.9), blurRadius: 8, spreadRadius: 2)],
              ),
            ),
          ),
        ]),
      );
    });
  }

  Widget _sparkline() {
    if (history.isEmpty) {
      return SizedBox(
        height: 64,
        child: Center(
          child: Text(
            'Mengumpulkan data…',
            style: AppTheme.rajdhani.copyWith(color: color.withOpacity(0.5), fontSize: 11),
          ),
        ),
      );
    }
    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.clamp(0, 100)))
        .toList();

    return SizedBox(
      height: 64,
      child: LineChart(
        LineChartData(
          gridData:      const FlGridData(show: false),
          titlesData:    const FlTitlesData(show: false),
          borderData:    FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          minY: 0, maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots:     spots,
              isCurved:  true,
              color:     color,
              barWidth:  2.5,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (s, d) => s.x == d.spots.last.x,
                getDotPainter:  (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4, color: color,
                  strokeColor: color.withOpacity(0.4), strokeWidth: 5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                  colors: [color.withOpacity(0.28), color.withOpacity(0.02)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
