import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../shared/widgets/upgrade_dialog.dart';
import '../../core/data/refresh.dart';
import 'widgets/people_widgets.dart';
import 'share_link_bottom_sheet.dart';
import '../../shared/widgets/top_bar.dart' show DarkModeToggle, NotificationsButton;
import '../../shared/widgets/trip_selector_sheet.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/not_member_card.dart';

/// Screen 1 — People dashboard: trip header, member summary,
/// invite actions, invitation link, avatar strip.
class MembersScreen extends ConsumerStatefulWidget {
  final String tripId;
  const MembersScreen({super.key, required this.tripId});

  @override
  ConsumerState<MembersScreen> createState() => _State();
}

class _State extends ConsumerState<MembersScreen> {
  List<Map<String, dynamic>> _members = [];
  Map<String, dynamic> _trip = {};
  String _invite = '';
  String _tripName = '';
  String _linkBase = '';
  int? _me;
  bool _loading = true;
  bool _error = false;
  bool _notMember = false;
  bool _retried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MembersScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) {
      // Trip switched: drop stale data, show loader while new data loads.
      setState(() {
        _loading = true;
        _notMember = false;
        _error = false;
        _members = [];
      });
      _load();
    }
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/${widget.tripId}/members/detailed'),
        dio.get('/api/trips/${widget.tripId}'),
        dio.get('/api/config/public'),
        dio.get('/api/users/me'),
      ]);
      if (!mounted) return;
      final trip = Map<String, dynamic>.from(res[1].data['data'] as Map);
      final pub = Map<String, dynamic>.from(res[2].data['data'] as Map);
      setState(() {
        _members = ((res[0].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _trip = trip;
        _invite = (trip['inviteCode'] ?? '').toString();
        _tripName = (trip['tripName'] ?? 'TripMate trip').toString();
        _linkBase = (pub['app.invite.base-url'] ?? '').toString();
        _me = (res[3].data['data']['id'] as num?)?.toInt();
        _loading = false;
        _error = false;
        _notMember = false;
      });
    } catch (e) {
      if (mounted) {
        if (isNotMemberError(e) && !_retried) {
          _retried = true;
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) { _load(); return; }
        }
        setState(() {
          _loading = false;
          _error = !isNotMemberError(e);
          _notMember = isNotMemberError(e);
        });
      }
    }
  }

  String get _inviteLink =>
      _linkBase.isNotEmpty ? '$_linkBase$_invite' : 'Code: $_invite';

  bool get _isOwner => _members.any((m) =>
      PeopleTheme.memberId(m) == _me && m['role'] == 'OWNER');

  Future<void> _share() async {
    await Share.share(
      'Join my TripMate trip "$_tripName"! $_inviteLink',
      subject: 'TripMate invite',
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _inviteLink));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation link copied')),
      );
    }
  }

  Future<void> _setRsvp(String value) async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      await dio.patch(
        '/api/trips/${widget.tripId}/members/rsvp',
        data: {'rsvp': value},
      );
      bumpData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  void _rsvpSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Text(
                'My status',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            _RsvpOption(
              emoji: '✅',
              label: 'Going',
              color: const Color(0xFF10B981),
              onTap: () => _setRsvp('GOING'),
            ),
            _RsvpOption(
              emoji: '🤔',
              label: 'Maybe',
              color: const Color(0xFFF59E0B),
              onTap: () => _setRsvp('MAYBE'),
            ),
            _RsvpOption(
              emoji: '❌',
              label: 'Not Going',
              color: const Color(0xFFF43F5E),
              onTap: () => _setRsvp('NOT_GOING'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshInvite() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      await dio.post('/api/trips/${widget.tripId}/invite/refresh');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New invite link generated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  void _openShareSheet() {
    showShareLinkSheet(context,
        link: _inviteLink, tripName: _tripName);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) => _load());
    ref.listen(tabRefreshRequestProvider, (_, req) {
      if (req != null && req.tab == 3) _load();
    });
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: TripDropdown(tripId: widget.tripId),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/trips/${widget.tripId}/map'),
        ),
        actions: [
          const DarkModeToggle(),
          const NotificationsButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notMember
              ? NotMemberCard(
                  tripId: widget.tripId, onRetry: _load)
              : _error
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load members'),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TripHeaderCard(
                            trip: _trip,
                            memberCount: _members.length),
                        const SizedBox(height: 12),
                        _summaryCard(),
                        const SizedBox(height: 12),
                        ShareButton(
                          label: '+ Invite Friends',
                          icon: Icons.person_add_alt,
                          onTap: () => context.push(
                              '/trips/${widget.tripId}/members/invite'),
                        ),
                        const SizedBox(height: 10),
                        ShareButton(
                          label: '🔗 Share Trip Link',
                          icon: Icons.link_outlined,
                          primary: false,
                          onTap: _openShareSheet,
                        ),
                        const SizedBox(height: 12),
                        InviteCard(
                          link: _inviteLink,
                          onCopy: _copy,
                          onShare: _share,
                          showRefresh: _isOwner,
                          onRefresh: _refreshInvite,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Text(
                              'Trip Members (${_members.length})',
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => context.push(
                                  '/trips/${widget.tripId}/members/all'),
                              child: const Text('View All Members'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        MemberAvatarList(
                          members: _members,
                          me: _me,
                          onTap: (_) => context.push(
                              '/trips/${widget.tripId}/members/all'),
                        ),
                        const SizedBox(height: 18),
                        // ── Trip History ──
                        ShareButton(
                          label: '📜 Trip History',
                          icon: Icons.history,
                          primary: false,
                          onTap: () => context.push(
                              '/trips/${widget.tripId}/history'),
                        ),
                        const SizedBox(height: 18),
                        // ── Join by Code ──
                        _JoinByCode(tripId: widget.tripId),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _summaryCard() {
    final n = _members.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Text('👥',
                  style: TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n Member${n == 1 ? '' : 's'} Joined',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'Planning this trip together',
                  style: TextStyle(
                      color: PeopleTheme.sub, fontSize: 13),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _rsvpSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'My Status',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinByCode extends StatefulWidget {
  final String tripId;
  const _JoinByCode({required this.tripId});

  @override
  State<_JoinByCode> createState() => _State2();
}

class _State2 extends State<_JoinByCode> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an invite code')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final dio = ProviderScope.containerOf(context)
          .read(dioClientProvider)
          .dio;
      // Try joining by code (public trip lookup)
      final tripRes = await dio.get('/api/trips/by-code/$code');
      final tripId = (tripRes.data['data']['tripId']).toString();
      await dio.post('/api/trips/$tripId/join',
          data: {'inviteCode': code});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Joined trip successfully!'),
            backgroundColor: Color(0xFF10B981)),
      );
      _ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      final msg = apiErrorMessage(e);
      if (isLimitMessage(msg)) {
        showLimitUpgradeDialog(context, msg);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Join Another Trip',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Enter an invite code to join a different trip.',
            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'Invite code',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _busy ? null : _join,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Join'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RsvpOption extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _RsvpOption({
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
