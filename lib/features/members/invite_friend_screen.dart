import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../shared/widgets/upgrade_dialog.dart';
import 'widgets/people_widgets.dart';
import 'share_link_bottom_sheet.dart';

/// Invite Friends: connected users list + incoming invites + share options.
class InviteFriendScreen extends ConsumerStatefulWidget {
  final String tripId;
  const InviteFriendScreen({super.key, required this.tripId});

  @override
  ConsumerState<InviteFriendScreen> createState() => _State();
}

class _State extends ConsumerState<InviteFriendScreen> {
  String _invite = '';
  String _tripName = 'TripMate trip';
  String _linkBase = '';
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _pending = [];
  final Set<int> _sent = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/${widget.tripId}'),
        dio.get('/api/config/public'),
        dio.get('/api/users/connections'),
        dio.get('/api/users/invites/pending'),
      ]);
      if (!mounted) return;
      final trip =
          Map<String, dynamic>.from(res[0].data['data'] as Map);
      final pub =
          Map<String, dynamic>.from(res[1].data['data'] as Map);
      setState(() {
        _invite = (trip['inviteCode'] ?? '').toString();
        _tripName = (trip['tripName'] ?? 'TripMate trip').toString();
        _linkBase = (pub['app.invite.base-url'] ?? '').toString();
        _connections = ((res[2].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _pending = ((res[3].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  String get _link =>
      _linkBase.isNotEmpty ? '$_linkBase$_invite' : 'Code: $_invite';

  String get _message =>
      'Join my TripMate trip "$_tripName"! $_link';

  Future<void> _share() async {
    await Share.share(_message, subject: 'TripMate invite');
  }

  Future<void> _sendInvite(int userId, String name) async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      await dio.post('/api/trips/${widget.tripId}/invite-user',
          data: {'userId': userId});
      if (!mounted) return;
      setState(() => _sent.add(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invite sent to $name'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeopleTheme.bg,
      appBar: AppBar(title: const Text('Invite Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/images/auth_travel.jpg',
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Incoming Invites ──
                    if (_pending.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 20, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          Text('Incoming Invites (${_pending.length})',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._pending.map((inv) =>
                          _IncomingInviteCard(inv: inv, onRefresh: _load)),
                      const SizedBox(height: 18),
                    ],

                    // ── Connected Users ──
                    const Text('Your Travel Buddies',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text(
                      "People you've traveled with before",
                      style: TextStyle(
                          color: PeopleTheme.sub, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    if (_connections.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.people_outline,
                                size: 40,
                                color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            const Text(
                              'No connections yet',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'When you join trips with others, they\'ll appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: PeopleTheme.sub, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._connections.map((c) {
                        final uid = (c['userId'] as num?)?.toInt() ?? 0;
                        final name =
                            (c['name'] ?? 'Unknown').toString();
                        final email =
                            (c['email'] ?? '').toString();
                        final img = c['profileImage']?.toString();
                        final sent = _sent.contains(uid);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    const Color(0xFFEFF6FF),
                                backgroundImage:
                                    img != null && img.isNotEmpty
                                        ? NetworkImage(img)
                                        : null,
                                child: img == null || img.isEmpty
                                    ? Text(
                                        name[0].toUpperCase(),
                                        style: const TextStyle(
                                            color:
                                                Color(0xFF2563EB),
                                            fontWeight:
                                                FontWeight.w700),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w700)),
                                    Text(email,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: PeopleTheme.sub)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 36,
                                child: sent
                                    ? const Icon(Icons.check_circle,
                                        color: Color(0xFF10B981),
                                        size: 22)
                                    : FilledButton(
                                        onPressed: () => _sendInvite(
                                            uid, name),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF2563EB),
                                          shape:
                                              RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius
                                                    .circular(10),
                                          ),
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 14),
                                        ),
                                        child: const Text('Invite',
                                            style: TextStyle(
                                                fontSize: 12)),
                                      ),
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 22),

                    // ── Share Options ──
                    const Text('Other Ways to Invite',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    _OptionCard(
                      emoji: '🔗',
                      title: 'Share Link',
                      sub: 'Anyone with the link can join',
                      onTap: () => showShareLinkSheet(context,
                          link: _link, tripName: _tripName),
                    ),
                    _OptionCard(
                      emoji: '💬',
                      title: 'WhatsApp',
                      sub: 'Invite your contacts',
                      onTap: _share,
                    ),
                    _OptionCard(
                      emoji: '✉️',
                      title: 'Email',
                      sub: 'Send invitation',
                      onTap: () => Share.share(_message,
                          subject: 'Join my trip on TripMate'),
                    ),
                    const SizedBox(height: 18),
                    ShareButton(
                      label: 'Share Trip Link',
                      icon: Icons.share_outlined,
                      onTap: _share,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _IncomingInviteCard extends StatefulWidget {
  final Map<String, dynamic> inv;
  final VoidCallback onRefresh;
  const _IncomingInviteCard({required this.inv, required this.onRefresh});

  @override
  State<_IncomingInviteCard> createState() => _IncomingInviteCardState();
}

class _IncomingInviteCardState extends State<_IncomingInviteCard> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      final dio = ProviderScope.containerOf(context)
          .read(dioClientProvider)
          .dio;
      final id = widget.inv['inviteId'];
      await dio
          .post('/api/users/invites/$id/${accept ? "accept" : "reject"}');
      if (!mounted) return;
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      final msg = apiErrorMessage(e);
      if (isLimitMessage(msg)) {
        showLimitUpgradeDialog(context, msg);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviter = (widget.inv['inviterName'] ?? 'Someone').toString();
    final trip = (widget.inv['tripName'] ?? 'a trip').toString();
    final start = (widget.inv['startName'] ?? '').toString();
    final dest = (widget.inv['destName'] ?? '').toString();
    final img = widget.inv['inviterImage']?.toString();
    final route =
        start.isNotEmpty && dest.isNotEmpty ? '$start → $dest' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFEF3C7),
                backgroundImage:
                    img != null && img.isNotEmpty ? NetworkImage(img) : null,
                child: img == null || img.isEmpty
                    ? Text(inviter[0].toUpperCase(),
                        style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black87),
                        children: [
                          TextSpan(
                              text: inviter,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          const TextSpan(text: ' invited you to'),
                        ],
                      ),
                    ),
                    Text(trip,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    if (route.isNotEmpty)
                      Text(route,
                          style: const TextStyle(
                              fontSize: 12, color: PeopleTheme.sub)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _respond(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _OptionCard({
    required this.emoji,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(emoji,
                      style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 12,
                            color: PeopleTheme.sub)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_outlined,
                  color: PeopleTheme.sub),
            ],
          ),
        ),
      ),
    );
  }
}
