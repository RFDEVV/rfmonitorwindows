import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../theme/app_style.dart';

class NavItem {
  final String label;
  final String svg; // inline SVG string, no icon fonts
  final Color glow;
  const NavItem(this.label, this.svg, this.glow);
}

const navItems = [
  NavItem(
      'Home',
      '<svg viewBox="0 0 24 24"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z" fill="currentColor"/></svg>',
      AppColors.neonCyan),
  NavItem(
      'PM2',
      '<svg viewBox="0 0 24 24"><path d="M4 4h16v4H4zM4 10h16v4H4zM4 16h16v4H4z" fill="currentColor"/></svg>',
      AppColors.neonGreen),
  NavItem(
      'Service',
      '<svg viewBox="0 0 24 24"><path d="M12 2 3 6v6c0 5 4 9 9 10 5-1 9-5 9-10V6l-9-4z" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
      AppColors.neonGold),
  NavItem(
      'Power',
      '<svg viewBox="0 0 24 24"><path d="M13 2 3 14h7l-1 8 10-12h-7l1-8z" fill="currentColor"/></svg>',
      AppColors.neonOrange),
  NavItem(
      'Server',
      '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="4" y="14" width="16" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="7.5" cy="7" r="1" fill="currentColor"/><circle cx="7.5" cy="17" r="1" fill="currentColor"/></svg>',
      AppColors.neonCyan),
  NavItem(
      'Files',
      '<svg viewBox="0 0 24 24"><path d="M3 6.5A2.5 2.5 0 0 1 5.5 4H10l2 2h6.5A2.5 2.5 0 0 1 21 8.5v9a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5v-11z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M3 9h18" stroke="currentColor" stroke-width="1.7"/></svg>',
      AppColors.neonGold),
  NavItem(
      'Speed',
      '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 12 17 7" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
      AppColors.neonGreen),
  NavItem(
      'Setting',
      '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3" fill="currentColor"/><path d="M19 12a7 7 0 0 0-.1-1.2l2-1.6-2-3.4-2.4 1a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.4 2 1.6A7 7 0 0 0 5 12c0 .4 0 .8.1 1.2l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 2 1.2L10 21h4l.5-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.4-2-1.6c.1-.4.1-.8.1-1.2z" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>',
      AppColors.neonGold),
];

class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassBottomNav(
      {super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: AppStyleKit.card(accent: AppColors.neonCyan, radius: 26),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: List.generate(navItems.length, (i) {
          return SizedBox(
            width: 48,
            child: _NavButton(
              item: navItems[i],
              selected: i == currentIndex,
              onTap: () => onTap(i),
            ),
          );
        }),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: AppStyleKit.isGlass
          ? ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(filter: AppStyleKit.blurFilter, child: bar),
            )
          : bar,
    );
  }
}

class GlassSideNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassSideNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rail = Container(
      width: 104,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: AppStyleKit.card(accent: AppColors.neonCyan, radius: 24),
      child: ListView.builder(
        itemCount: navItems.length,
        itemBuilder: (context, index) => SizedBox(
          height: 72,
          child: _NavButton(
            item: navItems[index],
            selected: index == currentIndex,
            onTap: () => onTap(index),
          ),
        ),
      ),
    );

    return AppStyleKit.isGlass
        ? ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: AppStyleKit.blurFilter,
              child: rail,
            ),
          )
        : rail;
  }
}

class _NavButton extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _NavButton(
      {required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final neo = AppStyleKit.isNeo;
    final minimal = AppStyleKit.isMinimal;

    final iconColor = selected
        ? (neo ? AppStyleKit.neoBg : item.glow)
        : AppColors.textSecondary;
    final labelColor = selected
        ? (neo ? AppStyleKit.neoInk : item.glow)
        : AppColors.textSecondary;

    BoxDecoration? pill;
    if (selected && neo) {
      pill = BoxDecoration(
        color: item.glow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppStyleKit.neoInk, width: 2),
      );
    } else if (selected && !minimal) {
      pill = BoxDecoration(
        color: item.glow.withOpacity(0.20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.glow.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
              color: item.glow.withOpacity(0.45),
              blurRadius: 14,
              spreadRadius: -2)
        ],
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 34,
              alignment: Alignment.center,
              decoration: pill,
              child: SizedBox(
                width: 22,
                height: 22,
                child: SvgPicture.string(item.svg,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn)),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                color: labelColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (minimal)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(top: 3),
                width: selected ? 14 : 0,
                height: 2,
                decoration: BoxDecoration(
                    color: item.glow, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      ),
    );
  }
}
