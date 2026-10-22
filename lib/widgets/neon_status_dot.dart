import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small glowing status dot (green = online, red = offline, grey = unknown).
class NeonStatusDot extends StatelessWidget {
  final bool? online; // null = unknown/checking
  final double size;
  const NeonStatusDot({super.key, required this.online, this.size = 10});

  @override
  Widget build(BuildContext context) {
    final color = online == null ? AppColors.textSecondary : (online! ? AppColors.neonGreen : AppColors.roseRed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: online == null ? [] : [BoxShadow(color: color.withOpacity(0.8), blurRadius: 8, spreadRadius: 1)],
      ),
    );
  }
}
