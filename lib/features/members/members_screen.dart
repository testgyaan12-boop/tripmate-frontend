import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';

/// People screen: member count banner, profile cards with status,
/// invite-link generation, self RSVP editing.
class MembersScreen extends ConsumerStatefulWidget {
  final String tripId;
  const MembersScreen({super.key, required this.tripId});

  @override
  ConsumerState<MembersScreen> createState() => _State();
}

class _State extends ConsumerState<MembersScreen> {
  List<Map<String, dynamic>> _members = [];
  String _invite = '';
  String _tripName = '';
  String _linkBase = '';
  int? _me;
  bool _loading = true;
  bool _error = false;

  static const _avatarColors = [
    Color(0xFF2563EB),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF10B981),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MembersScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) _load();
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
        _invite = (trip['inviteCode'] ?? '').toString();
        _tripName = (trip['tripName'] ?? 'TripMate trip').toString();
        _linkBase = (pub['app.invite.base-url'] ?? '').toString();
        _me = (res[3].data['data']['id'] as num?)?.toInt();
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  String get _inviteLink =>
      _linkBase.isNotEmpty ? '$_linkBase$_invite' : 'Code: $_invite';

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

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) => _load());
    ref.listen(tabRefreshRequestProvider, (_, req) {
      if (req != null && req.tab == 3) _load();
    });
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('People'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/trips/${widget.tripId}/map'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                children: [
                  _CountBanner(count: _members.length),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: _share,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Invite Friends'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InviteCard(
                      link: _inviteLink,
                      onCopy: _copy,
                      showRefresh: _members.any((m) =>
                          (m['userId'] as num?)?.toInt() == _me &&
                          m['role'] == 'OWNER'),
                      onRefresh: _refreshInvite),
                  const SizedBox(height: 18),
                  ..._members.map((m) {
                    final uid = (m['userId'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberCard(
                        member: m,
                        isMe: uid == _me,
                        color: _avatarColors[
                            uid % _avatarColors.length],
                        onTap: uid == _me ? _rsvpSheet : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _CountBanner extends StatelessWidget {
  final int count;
  const _CountBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.group,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count Member${count == 1 ? '' : 's'} joined',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Planning this trip together',
                style: TextStyle(
                    color: Color(0xE6FFFFFF), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final String link;
  final VoidCallback onCopy;
  final bool showRefresh;
  final VoidCallback onRefresh;
  const _InviteCard({
    required this.link,
    required this.onCopy,
    required this.showRefresh,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trip invitation link',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      link,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy link',
                ),
                if (showRefresh) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'New link (old one stops working)',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool isMe;
  final Color color;
  final VoidCallback? onTap;
  const _MemberCard({
    required this.member,
    required this.isMe,
    required this.color,
    required this.onTap,
  });

  Color _statusColor(String rsvp) {
    switch (rsvp) {
      case 'GOING':
        return const Color(0xFF10B981);
      case 'MAYBE':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFF43F5E);
    }
  }

  String _statusLabel(String rsvp) {
    switch (rsvp) {
      case 'GOING':
        return 'Going';
      case 'MAYBE':
        return 'Maybe';
      default:
        return 'Not Going';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (member['name']?.toString() ?? '').isNotEmpty
            ? member['name'].toString()
            : 'Traveller ${member['userId']}';
    final img = member['profileImage'] as String?;
    final isOwner = member['role'] == 'OWNER';
    final rsvp = (member['rsvp'] ?? 'GOING').toString();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color,
                backgroundImage:
                    img != null ? NetworkImage(img) : null,
                onBackgroundImageError:
                    img != null ? (_, _) {} : null,
                child: img == null
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                        ),
                      )
                    : null,
            ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isMe)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        if (isOwner) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.workspace_premium,
                              size: 15, color: Color(0xFFF59E0B)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOwner ? 'Trip Owner' : 'Member',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor(rsvp).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(rsvp),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(rsvp),
                  ),
                ),
              ),
            ],
          ),
        ),
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
