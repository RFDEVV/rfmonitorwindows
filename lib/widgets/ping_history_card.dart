import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PingHistoryCard extends StatelessWidget {
  final List<bool?> ticks;
  const PingHistoryCard({super.key, required this.ticks});

  @override
  Widget build(BuildContext context) {
    final dropCount = ticks.where((t) => t == false).length;

    return NeonCornerCard(
      color: AppColors.neonCyan,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.wifi_rounded, color: AppColors.neonCyan, size: 16),
            const SizedBox(width: 8),
            Text(
              'PING HISTORY',
              style: AppTheme.chakraPetch.copyWith(
                color: AppColors.textPrimary, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600,
              ),
            ),
          ]),
          Row(children: [
            _dot(AppColors.neonGreen, 'Online'),
            const SizedBox(width: 10),
            _dot(AppColors.roseRed, 'Offline'),
          ]),
        ]),
        if (dropCount > 0) ...[
          const SizedBox(height: 6),
          Text(
            '$dropCount drop terdeteksi',
            style: AppTheme.rajdhani.copyWith(color: AppColors.roseRed, fontSize: 11),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 32,
          child: ticks.isEmpty
              ? Center(
                  child: Text(
                    'Belum ada data ping…',
                    style: AppTheme.rajdhani.copyWith(color: AppColors.textSecondary, fontSize: 11),
                  ),
                )
              : Row(
                  children: ticks.map((t) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: t == null
                              ? Colors.grey.shade800
                              : (t ? AppColors.neonGreen : AppColors.roseRed),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: t == null
                              ? []
                              : [BoxShadow(
                                  color: (t ? AppColors.neonGreen : AppColors.roseRed).withOpacity(0.5),
                                  blurRadius: 4,
                                )],
                        ),
                      ),
                    ),
                  )).toList(),
                ),
        ),
      ]),
    );
  }

  Widget _dot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: AppTheme.rajdhani.copyWith(color: AppColors.textSecondary, fontSize: 10.5)),
    ]);
  }
}
