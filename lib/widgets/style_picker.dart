import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_style.dart';

/// Pilih gaya UI: Neo 3D (default), Glassmorphism, Minimalist.
/// Tiap kartu pilihan memperlihatkan tampilan gayanya sendiri.
class StylePicker extends StatelessWidget {
  const StylePicker({super.key});

  Color _accent(AppStyle s) {
    switch (s) {
      case AppStyle.neo:
        return AppColors.neonGold;
      case AppStyle.glass:
        return AppColors.neonCyan;
      case AppStyle.minimal:
        return AppColors.neonGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StyleController.instance,
      builder: (context, _) {
        final active = StyleController.instance.style;
        return Column(
          children: [
            for (final s in AppStyle.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, right: 5),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => StyleController.instance.set(s),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppStyleKit.cardFor(s, accent: _accent(s), radius: 16),
                    child: Row(
                      children: [
                        // pratinjau mini: dua batang + titik status
                        Container(
                          width: 54,
                          height: 44,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(s == AppStyle.minimal ? 6 : 10),
                            border: Border.all(color: _accent(s).withOpacity(0.8), width: s == AppStyle.neo ? 2 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(height: 5, width: 30, color: _accent(s)),
                              Container(height: 5, width: 18, color: _accent(s).withOpacity(0.5)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.label,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(s.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        Icon(
                          s == active ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: s == active ? _accent(s) : AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
