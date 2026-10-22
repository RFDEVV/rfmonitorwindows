import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatTileData {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const StatTileData({required this.icon, required this.color, required this.value, required this.label});
}

/// The row of 3 compact glass tiles under the status hero (Uptime / Services
/// Online / Alerts Today in RFMonitor's case — same visual slot as the
/// reference app's Uptime / Total User / Total Order tiles).
class StatTileRow extends StatelessWidget {
  final List<StatTileData> tiles;
  const StatTileRow({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: tiles.asMap().entries.map((e) {
        final t = e.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key == tiles.length - 1 ? 0 : 10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.glassBase,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                children: [
                  Icon(t.icon, color: t.color, size: 18),
                  const SizedBox(height: 8),
                  Text(t.value, style: AppTheme.orbitron.copyWith(color: t.color, fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(t.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, letterSpacing: 0.5), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
