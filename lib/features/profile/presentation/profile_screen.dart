import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/presentation/auth_provider.dart';
import '../data/profile_repository.dart';
import 'widgets/profile_widgets.dart';
import 'widgets/my_expenses.dart';

const _navItems = [
  (Icons.dashboard_outlined, 'Overview'),
  (Icons.route_outlined, 'Trips'),
  (Icons.place_outlined, 'Places'),
  (Icons.emoji_events_outlined, 'Achievements'),
  (Icons.wallet_outlined, 'My Expenses'),
  (Icons.settings_outlined, 'Settings'),
];

/// Travel-identity page: responsive mobile scroll / desktop sidebar layout.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _State();
}

class _State extends ConsumerState<ProfileScreen> {
  int _tab = 0;
  bool _pub = true;
  bool _inviteOk = true;
  bool _showVisited = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pub = p.getBool('tm_priv_public') ?? true;
      _inviteOk = p.getBool('tm_priv_invite') ?? true;
      _showVisited = p.getBool('tm_priv_visited') ?? true;
    });
  }

  Future<void> _toggle(String key, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
    if (!mounted) return;
    setState(() {
      if (key == 'tm_priv_public') _pub = v;
      if (key == 'tm_priv_invite') _inviteOk = v;
      if (key == 'tm_priv_visited') _showVisited = v;
    });
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('See you on the next road trip!'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) context.go('/login');
    }
  }

  List<Map<String, dynamic>> _badges(Map<String, dynamic> s) {
    int n(String k) => ((s[k] ?? 0) as num).toInt();
    final defs = [
      {
        'emoji': '🧭',
        'title': 'First Journey',
        'sub': 'Join your first trip',
        'cur': n('tripsJoined'),
        'need': 1
      },
      {
        'emoji': '👥',
        'title': 'Trip Organizer',
        'sub': 'Create 5 group trips',
        'cur': n('tripsCreated'),
        'need': 5
      },
      {
        'emoji': '🚗',
        'title': 'Road Explorer',
        'sub': 'Complete 10 trips',
        'cur': n('tripsCreated'),
        'need': 10
      },
      {
        'emoji': '📍',
        'title': 'Place Collector',
        'sub': 'Visit 50 places',
        'cur': n('placesVisited'),
        'need': 50
      },
      {
        'emoji': '🗳️',
        'title': 'Super Voter',
        'sub': 'Cast 50 votes',
        'cur': n('votesGiven'),
        'need': 50
      },
    ];
    return defs
        .map((b) => {
              ...b,
              'unlocked': (b['cur'] as int) >= (b['need'] as int),
              'progress': (b['cur'] as int) >= (b['need'] as int)
                  ? b['sub']
                  : '${b['cur']}/${b['need']} — ${b['sub']}',
            })
        .toList();
  }

  List<Map<String, String>> _activity(
      List<Map<String, dynamic>> trips, int me) {
    final acts = trips.map((t) {
      final mine = ((t['createdByUserId'] as num?)?.toInt() ?? -1) == me;
      var when = '';
      try {
        when = DateFormat('d MMM yyyy')
            .format(DateTime.parse(t['createdAt'].toString()));
      } catch (_) {}
      return {
        'text':
            '${mine ? 'created' : 'joined'} “${t['tripName'] ?? 'a trip'}”',
        'when': when,
        'mine': mine ? '1' : '0',
      };
    }).toList();
    acts.sort((a, b) => b['when']!.compareTo(a['when']!));
    return acts.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load profile: $e'),
              TextButton(
                onPressed: () => ref.invalidate(profileProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (d) => LayoutBuilder(
          builder: (_, c) =>
              c.maxWidth >= 900 ? _desktop(d) : _mobile(d),
        ),
      ),
    );
  }

  // ---------------- mobile ----------------

  Widget _mobile(ProfileData d) {
    final me = (d.user['id'] as num?)?.toInt() ?? 0;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(profileProvider);
        await ref.read(profileProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileHeader(
              user: d.user,
              onEditPhoto: () => context.go('/profile/edit'),
            ),
            const SizedBox(height: 18),
            StatsCard(stats: d.stats),
            const SectionTitle('Travel Preferences'),
            _prefs(d.user),
            const SectionTitle('My Trips'),
            ..._tripCards(d),
            const SectionTitle('Saved Places'),
            _savedRow(d),
            const SectionTitle('Travel Badges'),
            ..._badgeCards(d),
            const SectionTitle('Activity'),
            ..._activityCards(d, me),
            const SectionTitle('Privacy'),
            _privacyCard(),
            const SectionTitle('Account Settings'),
            ..._settingsTiles(),
          ],
        ),
      ),
    );
  }

  // ---------------- desktop ----------------

  Widget _desktop(ProfileData d) {
    final me = (d.user['id'] as num?)?.toInt() ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 250,
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
          child: Column(
            children: [
              _MiniMe(user: d.user),
              const SizedBox(height: 12),
              ..._navItems.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: _tab == e.key,
                      selectedTileColor: const Color(0xFFEFF6FF),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: Icon(e.value.$1,
                          color: _tab == e.key
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF64748B)),
                      title: Text(e.value.$2,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      onTap: () => setState(() => _tab = e.key),
                    ),
                  )),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 8, 32, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Banner(user: d.user, stats: d.stats),
                    const SizedBox(height: 18),
                    if (_tab == 0) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                const SectionTitle('Trips Timeline'),
                                ..._tripCards(d),
                                const SectionTitle('Activity'),
                                ..._activityCards(d, me),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                const SectionTitle(
                                    'Travel Preferences'),
                                _prefs(d.user),
                                const SectionTitle('Travel Badges'),
                                ..._badgeCards(d),
                                const SectionTitle('Privacy'),
                                _privacyCard(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_tab == 1) ...[
                      const SectionTitle('My Trips'),
                      ..._tripCards(d),
                    ],
                    if (_tab == 2) ...[
                      const SectionTitle('Saved Places'),
                      _savedGrid(d),
                    ],
                    if (_tab == 3) ...[
                      const SectionTitle('Travel Badges'),
                      ..._badgeCards(d),
                    ],
                    if (_tab == 4) ...[
                      const SectionTitle('My Expenses'),
                      const MyExpensesSection(),
                    ],
                    if (_tab == 5) ...[
                      const SectionTitle('Privacy'),
                      _privacyCard(),
                      const SectionTitle('Account Settings'),
                      ..._settingsTiles(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- shared sections ----------------

  Widget _prefs(Map<String, dynamic> u) {
    String or(String? v, String fb) =>
        (v ?? '').isEmpty ? fb : v!;
    final favs = (u['favoritePlaces']?.toString() ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
          children: [
            PreferenceChip(
                icon: Icons.explore_outlined,
                label: 'Travel Style',
                value: or(u['travelStyle']?.toString(), 'Explorer')),
            PreferenceChip(
                icon: Icons.directions_car_outlined,
                label: 'Vehicle',
                value: or(u['vehicle']?.toString(), 'Car')),
            PreferenceChip(
                icon: Icons.wallet_outlined,
                label: 'Budget',
                value: or(u['budgetType']?.toString(), 'Medium')),
            PreferenceChip(
                icon: Icons.photo_camera_outlined,
                label: 'Loves',
                value: favs.isEmpty ? 'Mountains' : favs.first),
          ],
        ),
        if (favs.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: favs
                .map((f) => Chip(
                      label: Text(f,
                          style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFFEFF6FF),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  List<Widget> _tripCards(ProfileData d) {
    if (d.trips.isEmpty) {
      return [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(
                child: Text('No trips yet',
                    style: TextStyle(color: Color(0xFF64748B)))),
          ),
        )
      ];
    }
    return d.trips
        .map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TripHistoryCard(
                trip: t,
                members:
                    d.memberCounts[(t['id'] as num).toInt()] ?? 0,
                onOpen: () => context.go('/trips/${t['id']}/map'),
              ),
            ))
        .toList();
  }

  Widget _savedRow(ProfileData d) {
    if (d.saved.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
              child: Text('Vote 👍 on places to save them here',
                  style: TextStyle(color: Color(0xFF64748B)))),
        ),
      );
    }
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: d.saved.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _SavedCard(place: d.saved[i]),
      ),
    );
  }

  Widget _savedGrid(ProfileData d) {
    if (d.saved.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('Nothing saved yet'))));
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children:
          d.saved.map((p) => _SavedCard(place: p)).toList(),
    );
  }

  List<Widget> _badgeCards(ProfileData d) {
    return _badges(d.stats)
        .map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AchievementBadge(
                emoji: b['emoji'].toString(),
                title: b['title'].toString(),
                subtitle: b['progress'].toString(),
                unlocked: b['unlocked'] == true,
              ),
            ))
        .toList();
  }

  List<Widget> _activityCards(ProfileData d, int me) {
    final acts = _activity(d.trips, me);
    if (acts.isEmpty) {
      return [
        const Card(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('No activity yet'))))
      ];
    }
    return acts
        .map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    a['mine'] == '1'
                        ? Icons.add_circle_outline
                        : Icons.group_add_outlined,
                    color: const Color(0xFF2563EB),
                  ),
                  title: Text('You ${a['text']}',
                      style: const TextStyle(fontSize: 13)),
                  trailing: Text(a['when']!,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8))),
                ),
              ),
            ))
        .toList();
  }

  Widget _privacyCard() {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Show profile publicly',
                style: TextStyle(fontSize: 14)),
            value: _pub,
            onChanged: (v) => _toggle('tm_priv_public', v),
          ),
          SwitchListTile(
            title: const Text('Allow people to invite me',
                style: TextStyle(fontSize: 14)),
            value: _inviteOk,
            onChanged: (v) => _toggle('tm_priv_invite', v),
          ),
          SwitchListTile(
            title: const Text('Show visited places',
                style: TextStyle(fontSize: 14)),
            value: _showVisited,
            onChanged: (v) => _toggle('tm_priv_visited', v),
          ),
        ],
      ),
    );
  }

  List<Widget> _settingsTiles() {
    return [
      SettingsTile(
        icon: Icons.person_outline,
        title: 'Profile Settings',
        subtitle: 'Name, photo, preferences',
        onTap: () => context.go('/profile/edit'),
      ),
      const SizedBox(height: 8),
      SettingsTile(
        icon: Icons.notifications_outlined,
        title: 'Notification Settings',
        onTap: () => context.go('/settings/notifications'),
      ),
      const SizedBox(height: 8),
      SettingsTile(
        icon: Icons.workspace_premium_outlined,
        title: 'Subscription',
        subtitle: 'Free, Pro & Family plans',
        onTap: () => context.go('/subscription'),
      ),
      const SizedBox(height: 8),
      SettingsTile(
        icon: Icons.help_outline,
        title: 'Help & Support',
        onTap: () => showDialog(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Help & Support'),
            content: Text(
                'Write to support@tripmate.app — we reply within a day.'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      SettingsTile(
        icon: Icons.info_outline,
        title: 'About TripMate',
        onTap: () => showAboutDialog(
          context: context,
          applicationName: 'TripMate',
          applicationVersion: '1.0.0',
          children: const [
            Text('Plan trips together: routes, votes, itinerary and chat.')
          ],
        ),
      ),
      const SizedBox(height: 8),
      SettingsTile(
        icon: Icons.logout,
        title: 'Logout',
        danger: const Color(0xFFEF4444),
        onTap: _logout,
      ),
    ];
  }
}

class _MiniMe extends StatelessWidget {
  final Map<String, dynamic> user;
  const _MiniMe({required this.user});

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? '?').toString();
    final img = user['profileImage'] as String?;
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFF2563EB),
          backgroundImage: img != null ? NetworkImage(img) : null,
          child: img == null
              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text((user['email'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> stats;
  const _Banner({required this.user, required this.stats});

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? 'Traveller').toString();
    final img = user['profileImage'] as String?;
    int n(String k) => ((stats[k] ?? 0) as num).toInt();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            backgroundImage: img != null ? NetworkImage(img) : null,
            child: img == null
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800))
                : null,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                Text((user['email'] ?? '').toString(),
                    style: const TextStyle(
                        color: Color(0xE6FFFFFF), fontSize: 13)),
                const SizedBox(height: 8),
                Text(
                  '${n('tripsCreated')} trips · ${n('placesVisited')} places · ${n('friendsMet')} friends',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final Map<String, dynamic> place;
  const _SavedCard({required this.place});

  @override
  Widget build(BuildContext context) {
    final img = (place['imageUrl'] as String?) ?? '';
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: img.isNotEmpty
                  ? Image.network(img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Image.asset(
                          'assets/images/trip_goa.jpg',
                          fit: BoxFit.cover))
                  : Image.asset('assets/images/trip_goa.jpg',
                      fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((place['name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  Text((place['address'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
