import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dashboard_providers.dart';
import '../../core/data/refresh.dart';
import '../../core/network/api_error.dart';
import '../../shared/widgets/trip_nav_bar.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;

const _cardImages = [
  'assets/images/trip_hero.jpg',
  'assets/images/trip_goa.jpg',
  'assets/images/splash_road.jpg',
  'assets/images/auth_travel.jpg',
];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final trips = data.valueOrNull?.trips ?? [];
    // Every Home tap refetches; any local write refreshes too.
    ref.listen(dataVersionProvider, (_, _) {
      ref.invalidate(dashboardProvider);
    });
    ref.listen(tabRefreshRequestProvider, (_, req) {
      if (req != null && req.tab == 0) {
        ref.invalidate(dashboardProvider);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            await ref.read(dashboardProvider.future);
          },
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              children: [
                const SizedBox(height: 120),
                Center(child: Text('Failed to load: ${apiErrorMessage(e)}')),
                Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(dashboardProvider),
                    child: const Text('Retry'),
                  ),
                ),
              ],
            ),
            data: (d) => _Body(
              data: d,
              unread: unread,
            ),
          ),
        ),
      ),
      bottomNavigationBar: TripNavBar(
        tripId: trips.isNotEmpty ? '${trips.first.id}' : null,
        currentIndex: 0,
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final DashboardData data;
  final int unread;
  const _Body({required this.data, required this.unread});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, TripSummary trip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text(
            '“${trip.name}” will be removed. This frees one free-trip slot.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(dioClientProvider)
          .dio
          .delete('/api/trips/${trip.id}');
      ref.invalidate(dashboardProvider);
      bumpData(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (data.user['name'] ?? 'Traveller').toString();
    final trips = data.trips;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        _TopBar(user: data.user, unread: unread),
        const SizedBox(height: 16),
        Text(
          'Hello, $name 👋',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: Color(0xFF0F172A),
          ),
        ),
        const Text(
          'Where to next?',
          style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 18),
        if (trips.isEmpty)
          _EmptyState()
        else ...[
          _FadeRise(delay: 0, child: _HeroCard(trip: trips.first)),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Trips',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.go('/trips/new'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...trips.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FadeRise(
                    delay: 80 * (e.key + 1),
                    child: _TripCard(
                      trip: e.value,
                      image: _cardImages[e.key % _cardImages.length],
                      onLongPress: () =>
                          _confirmDelete(context, ref, e.value),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final Map<String, dynamic> user;
  final int unread;
  const _TopBar({required this.user, required this.unread});

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? '?').toString();
    final img = user['profileImage'] as String?;
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.go('/profile'),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF2563EB),
            backgroundImage: img != null ? NetworkImage(img) : null,
            child: img == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
        ),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => context.go('/notifications'),
              icon: const Icon(
                Icons.notifications_outlined,
                color: Color(0xFF0F172A),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final TripSummary trip;
  const _HeroCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
        image: const DecorationImage(
          image: AssetImage('assets/images/trip_hero.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0x400B1220), Color(0xE00B1220)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusChip(label: trip.statusLabel),
            const Spacer(),
            Text(
              trip.route,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const Text(
              'Road Trip',
              style: TextStyle(fontSize: 14, color: Color(0xCCFFFFFF)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stat(icon: Icons.route, text: trip.kmLabel),
                const SizedBox(width: 14),
                _Stat(icon: Icons.calendar_month, text: trip.daysLabel),
                const SizedBox(width: 14),
                _Stat(
                    icon: Icons.group, text: '${trip.members} Members'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () =>
                          context.go('/trips/${trip.id}/map'),
                      child: const Text('View Map'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () =>
                          context.go('/trips/${trip.id}/places'),
                      child: const Text('Continue Planning'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TripSummary trip;
  final String image;
  final VoidCallback? onLongPress;
  const _TripCard(
      {required this.trip, required this.image, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final pct = (trip.progress * 100).round();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go('/trips/${trip.id}/map'),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  image,
                  width: 86,
                  height: 86,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 86,
                    height: 86,
                    color: const Color(0xFFE2E8F0),
                    child: const Icon(Icons.image),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trip.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        _StatusChip(label: trip.statusLabel, small: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trip.route,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: trip.progress),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, _) =>
                                LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(4),
                              backgroundColor: const Color(0xFFE2E8F0),
                              valueColor:
                                  const AlwaysStoppedAnimation(
                                Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$pct%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$pct% Planned • ${trip.members} members',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.route,
                color: Color(0xFF2563EB),
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No trips yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Create your first road trip and invite friends.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/trips/new'),
              icon: const Icon(Icons.add),
              label: const Text('Create Trip'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool small;
  const _StatusChip({required this.label, this.small = false});

  Color get _color {
    switch (label) {
      case 'Finalized':
        return const Color(0xFF10B981);
      case 'Upcoming':
        return const Color(0xFF2563EB);
      case 'Completed':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Stat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 15),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FadeRise extends StatelessWidget {
  final int delay;
  final Widget child;
  const _FadeRise({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 500 + delay),
      curve: Curves.easeOutCubic,
      builder: (_, value, _) {
        final t =
            ((value * (500 + delay) - delay) / 500).clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
