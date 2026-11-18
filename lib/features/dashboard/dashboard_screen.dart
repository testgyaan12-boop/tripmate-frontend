import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dashboard_providers.dart';
import '../../core/data/refresh.dart';
import '../../core/data/trip_status.dart';
import '../../core/network/api_error.dart';
import '../../shared/widgets/trip_nav_bar.dart';
import '../../shared/widgets/top_bar.dart';
import '../../core/constants/app_colors.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../profile/data/profile_repository.dart' show profileProvider;

const _cardImages = [
  'assets/images/trip_hero.jpg',
  'assets/images/trip_goa.jpg',
  'assets/images/splash_road.jpg',
  'assets/images/auth_travel.jpg',
];

/// Ongoing → Upcoming → Planning → Completed. Same-status trips keep their
/// original (server) order — Dart's sort is not stable, so index breaks ties.
List<TripSummary> _orderedTrips(List<TripSummary> trips) {
  final indexed = trips.asMap().entries.toList()
    ..sort((a, b) {
      final byStatus = TripStatus.order(a.value.statusLabel)
          .compareTo(TripStatus.order(b.value.statusLabel));
      return byStatus != 0 ? byStatus : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final trips = _orderedTrips(
        data.valueOrNull?.trips ?? const <TripSummary>[]);
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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

  static const _statusOptions = [
    ('AUTO', 'Automatic', 'Derived from travel dates'),
    ('PLANNING', 'Planning', 'Still putting the trip together'),
    ('UPCOMING', 'Upcoming', 'Trip is coming up'),
    ('ONGOING', 'Ongoing', 'Trip is happening now'),
    ('COMPLETED', 'Completed', 'Trip is done'),
  ];

  Future<void> _changeStatus(
      BuildContext context, WidgetRef ref, TripSummary trip) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Trip status',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(ctx),
                ),
              ),
            ),
            for (final o in _statusOptions)
              ListTile(
                leading: Icon(
                  o.$1 == 'AUTO'
                      ? Icons.auto_awesome
                      : Icons.flag_outlined,
                  color: Color(TripStatus.statusColor(o.$2)),
                ),
                title: Text(o.$2,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(o.$3,
                    style: const TextStyle(fontSize: 12)),
                trailing: trip.rawStatus == o.$1
                    ? Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, o.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == trip.rawStatus) return;
    try {
      await ref
          .read(dioClientProvider)
          .dio
          .patch('/api/trips/${trip.id}/status', data: {'status': picked});
      ref.invalidate(dashboardProvider);
      ref.invalidate(profileProvider);
      bumpData(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status updated')),
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
      ref.invalidate(profileProvider);
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
    final trips = _orderedTrips(data.trips);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TripMateHomeTopBar(user: data.user),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            children: [
              if (trips.isEmpty)
                _EmptyState()
              else ...[
                _FadeRise(
                  delay: 0,
                  child: _HeroCard(
                    trip: trips.first,
                    onStatus: () => _changeStatus(context, ref, trips.first),
                    onEdit: () =>
                        context.go('/trips/${trips.first.id}/edit'),
                    onDelete: () =>
                        _confirmDelete(context, ref, trips.first),
                  ),
                ),
                const SizedBox(height: 22),
                _MyTripsSection(
                  trips: trips,
                  onDelete: (t) => _confirmDelete(context, ref, t),
                  onStatus: (t) => _changeStatus(context, ref, t),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MyTripsSection extends ConsumerStatefulWidget {
  final List<TripSummary> trips;
  final void Function(TripSummary trip) onDelete;
  final void Function(TripSummary trip) onStatus;
  const _MyTripsSection({
    required this.trips,
    required this.onDelete,
    required this.onStatus,
  });

  @override
  ConsumerState<_MyTripsSection> createState() => _MyTripsSectionState();
}

class _MyTripsSectionState extends ConsumerState<_MyTripsSection> {
  static const _tabs = ['All', 'Ongoing', 'Upcoming', 'Planning', 'Completed'];
  bool _searching = false;
  String _query = '';
  String _tab = 'All';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int _count(String tab) => tab == 'All'
      ? widget.trips.length
      : widget.trips.where((t) => t.statusLabel == tab).length;

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final byTab = _tab == 'All'
        ? widget.trips
        : widget.trips.where((t) => t.statusLabel == _tab).toList();
    final visible = q.isEmpty
        ? byTab
        : byTab
            .where((t) =>
                '${t.name} ${t.route} ${t.ownerName}'.toLowerCase().contains(q))
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_searching)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search my trips...',
                    prefixIcon: const Icon(Icons.search, size: 22),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.inputFill(context),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close search',
                onPressed: () {
                  _ctrl.clear();
                  setState(() {
                    _searching = false;
                    _query = '';
                  });
                },
                icon: Icon(Icons.close,
                    color: AppColors.textSecondary(context)),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Trips',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Search trips',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _searching = true),
                    icon: Icon(Icons.search,
                        color: AppColors.textSecondary(context)),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/trips/new'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                  ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in _tabs) ...[
                _TripTabChip(
                  label: '$tab ${_count(tab)}',
                  selected: _tab == tab,
                  onTap: () => setState(() => _tab = tab),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(
                children: [
                  Text(
                    _query.trim().isNotEmpty
                        ? 'No trips found for "$_query"'
                        : 'No $_tab trips yet',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                  if (_tab != 'All')
                    TextButton(
                      onPressed: () => setState(() => _tab = 'All'),
                      child: const Text('View all trips'),
                    ),
                ],
              ),
            ),
          )
        else
          ...visible.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FadeRise(
                    delay: 80 * (e.key + 1),
                    child: _TripCard(
                      trip: e.value,
                      image: _cardImages[widget.trips
                              .indexOf(e.value) %
                          _cardImages.length],
                      onStatus: () => widget.onStatus(e.value),
                      onEdit: () =>
                          context.go('/trips/${e.value.id}/edit'),
                      onDelete: () => widget.onDelete(e.value),
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final TripSummary trip;
  final VoidCallback onStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _HeroCard({
    required this.trip,
    required this.onStatus,
    required this.onEdit,
    required this.onDelete,
  });

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
            Row(
              children: [
                _StatusChip(label: trip.statusLabel),
                const Spacer(),
                if (trip.isOwner)
                  _TripMenu(
                    onStatus: onStatus,
                    onEdit: onEdit,
                    onDelete: onDelete,
                    light: true,
                  ),
              ],
            ),
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
            if (trip.ownerName.isNotEmpty)
              Text(
                'by ${trip.ownerName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xCCFFFFFF)),
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
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      onPressed: () =>
                          context.go('/trips/${trip.id}/map'),
                      child: const FittedBox(child: Text('View Map')),
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
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      onPressed: () =>
                          context.go('/trips/${trip.id}/itinerary'),
                      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Continue Planning')),
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
  final VoidCallback onStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _TripCard({
    required this.trip,
    required this.image,
    required this.onStatus,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (trip.progress * 100).round();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go('/trips/${trip.id}/itinerary'),
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
                    color: AppColors.cardBorder(context),
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
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                        _StatusChip(label: trip.statusLabel, small: true),
                        const SizedBox(width: 6),
                        if (trip.isOwner)
                          _TripMenu(
                            onStatus: onStatus,
                            onEdit: onEdit,
                            onDelete: onDelete,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trip.route,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    if (trip.ownerName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 11, color: AppColors.textSecondary(context)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'by ${trip.ownerName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (trip.dateLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 11, color: AppColors.textSecondary(context)),
                          const SizedBox(width: 4),
                          Text(
                            trip.dateLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                              backgroundColor: AppColors.cardBorder(context),
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

class _TripMenu extends StatelessWidget {
  final VoidCallback onStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool light;
  const _TripMenu({
    required this.onStatus,
    required this.onEdit,
    required this.onDelete,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Trip options',
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == 'status') onStatus();
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'status',
          child: _MenuRow(icon: Icons.flag_outlined, label: 'Change status'),
        ),
        PopupMenuItem(
          value: 'edit',
          child: _MenuRow(icon: Icons.edit_outlined, label: 'Edit trip'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            icon: Icons.delete_outline,
            label: 'Delete trip',
            color: Color(0xFFDC2626),
          ),
        ),
      ],
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: light ? Colors.white24 : AppColors.inputFill(context),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          Icons.more_vert,
          size: 18,
          color: light ? Colors.white : AppColors.textSecondary(context),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MenuRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: c),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, color: c)),
      ],
    );
  }
}

class _TripTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TripTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.inputFill(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? AppColors.primary : AppColors.cardBorder(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color:
                selected ? Colors.white : AppColors.textSecondary(context),
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
                    color: AppColors.card(context),
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
            Text(
              'Create your first road trip and invite friends.',
              style: TextStyle(color: AppColors.textSecondary(context)),
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

  Color get _color => Color(TripStatus.statusColor(label));

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
