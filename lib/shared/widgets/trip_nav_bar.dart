import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/refresh.dart';

/// Trip bottom nav: Home | Places | Expenses | Itinerary | People.
/// Floating pill with icon + label, active pill highlight.
/// Shared by Home + all trip tabs.
class TripNavBar extends ConsumerWidget {
  /// Null when no trip exists yet (tabs beyond Home show a hint).
  final String? tripId;

  /// 0 Home, 1 Places, 2 Expenses, 3 Itinerary, 4 People.
  final int currentIndex;

  const TripNavBar(
      {super.key, required this.tripId, required this.currentIndex});

  void _go(BuildContext context, WidgetRef ref, int i) {
    // Every tap (even re-taps) announces itself; screens reload only when
    // their data is stale or a write happened since. Event handler, so
    // provider writes are safe here.
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
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 20,
              offset: Offset(0, 8),
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
  final VoidCallback onTap;
  const _NavTab({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF2563EB).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: active
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
