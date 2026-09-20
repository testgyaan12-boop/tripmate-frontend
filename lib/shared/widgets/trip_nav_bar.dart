import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/refresh.dart';

/// Trip bottom nav: Home | Places | Expenses | Itinerary | People.
/// White pill with blue accent, dark-mode aware.
class TripNavBar extends ConsumerWidget {
  final String? tripId;
  final int currentIndex;
  const TripNavBar(
      {super.key, required this.tripId, required this.currentIndex});

  void _go(BuildContext context, WidgetRef ref, int i) {
    ref.read(tabRefreshRequestProvider.notifier).state =
        TabRefresh(i, DateTime.now().millisecondsSinceEpoch);
    if (i == currentIndex) return;
    if (i == 0) {
      context.go('/home');
      return;
    }
    if (tripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a trip first')),
      );
      return;
    }
    const routes = ['places', 'expenses', 'itinerary', 'members'];
    context.go('/trips/$tripId/${routes[i - 1]}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const items = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.place_outlined, Icons.place, 'Places'),
      (Icons.wallet_outlined, Icons.wallet, 'Expenses'),
      (Icons.timeline_outlined, Icons.timeline, 'Itinerary'),
      (Icons.group_outlined, Icons.group, 'People'),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : const Color(0x22000000),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              _NavTab(
                active: currentIndex == i,
                icon: currentIndex == i ? items[i].$2 : items[i].$1,
                label: items[i].$3,
                isDark: isDark,
                onTap: () => _go(context, ref, i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _NavTab({
    required this.active,
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF2563EB);
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);
    final bgColor = active
        ? activeColor.withValues(alpha: 0.12)
        : Colors.transparent;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: active ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
