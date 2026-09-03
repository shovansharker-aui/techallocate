import 'package:flutter/material.dart';

/// A floating, fully-rounded (stadium/pill shaped) bottom navigation bar
/// — used instead of Flutter's stock rectangular BottomNavigationBar
/// per request. Shared by native Android and the mobile-width web/PWA
/// shell so both look and behave identically.
class PillBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PillBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    (Icons.archive_outlined, Icons.archive, 'Archive'),
    (Icons.water_drop_outlined, Icons.water_drop, 'Water Plant'),
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
    (Icons.history_outlined, Icons.history, 'History'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_items.length, (i) {
            final selected = i == currentIndex;
            final (outlineIcon, filledIcon, label) = _items[i];
            return _NavButton(
              icon: selected ? filledIcon : outlineIcon,
              label: label,
              selected: selected,
              color: scheme.primary,
              onTap: () => onTap(i),
            );
          }),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _NavButton({required this.icon, required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : Colors.grey, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? color : Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
