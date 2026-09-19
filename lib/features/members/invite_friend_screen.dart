import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import 'widgets/people_widgets.dart';
import 'share_link_bottom_sheet.dart';

/// Screen 3 — Invite Friends: illustration, invite option cards,
/// bottom Share Trip Link button.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeopleTheme.bg,
      appBar: AppBar(title: const Text('Invite Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/images/auth_travel.jpg',
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Invite Your Friends',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text(
                    'Add your travel buddies and make your trip more fun',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: PeopleTheme.sub, fontSize: 14),
                  ),
                  const SizedBox(height: 18),
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
