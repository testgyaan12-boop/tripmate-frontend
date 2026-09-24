import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_error.dart';
import '../../shared/widgets/upgrade_dialog.dart';
import '../../core/router/pending_invite.dart';
import '../../core/storage/token_storage.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../members/widgets/people_widgets.dart';

/// Screens 5+6 — Join Trip: illustration + trip card + Join/Decline,
/// then a success state with trip overview and member avatars.
class JoinScreen extends ConsumerStatefulWidget {
  final String? code;
  const JoinScreen({super.key, required this.code});

  @override
  ConsumerState<JoinScreen> createState() => _State();
}

class _State extends ConsumerState<JoinScreen> {
  Map<String, dynamic>? _preview;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  // Screen 6 state
  bool _joined = false;
  Map<String, dynamic> _trip = {};
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = widget.code;
    if (code == null || code.isEmpty) {
      setState(() {
        _error = 'This invite link has no code.';
        _loading = false;
      });
      return;
    }
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await dio.get('/api/trips/by-code/$code');
      if (!mounted) return;
      setState(() {
        _preview = Map<String, dynamic>.from(res.data['data'] as Map);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.statusCode == 410
            ? 'This invite link expired. Ask the owner for a fresh one.'
            : e.response?.statusCode == 404
                ? 'This invite link is invalid.'
                : apiErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _join() async {
    final code = widget.code;
    final tripId = _preview?['tripId'];
    if (code == null || code.isEmpty || tripId == null) return;
    // Remember the code across a possible login detour.
    ref.read(pendingInviteProvider.notifier).state = code;
    final token = await TokenStorage().access();
    if (!mounted) return;
    if (token == null) {
      context.go('/login');
      return;
    }
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      await dio.post('/api/trips/$tripId/join',
          data: {'inviteCode': code});
      ref.read(pendingInviteProvider.notifier).state = null;
      // Screen 6: load overview for the success state.
      final res = await Future.wait([
        dio.get('/api/trips/$tripId'),
        dio.get('/api/trips/$tripId/members/detailed'),
      ]);
      if (!mounted) return;
      setState(() {
        _trip =
            Map<String, dynamic>.from(res[0].data['data'] as Map);
        _members = ((res[1].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _joined = true;
        _busy = false;
      });
    } catch (e) {
      // 401 (dead session) auto-redirects to login via onAuthLost,
      // with the pending code intact for the ride back.
      if (mounted) {
        setState(() => _busy = false);
        final msg = apiErrorMessage(e);
        if (isLimitMessage(msg)) {
          showLimitUpgradeDialog(context, msg);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    }
  }

  String _dates(Map<String, dynamic> p) {
    final s = p['startDate']?.toString();
    final e = p['endDate']?.toString();
    try {
      if (s != null && e != null) {
        return '${DateFormat('d MMM').format(DateTime.parse(s))} - ${DateFormat('d MMM yyyy').format(DateTime.parse(e))}';
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Join Trip')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _StateCard(
                        icon: Icons.link_off,
                        title: 'Invite unavailable',
                        body: _error!,
                        actionLabel: 'Back to home',
                        onAction: () => context.go('/home'),
                      )
                    : _joined
                        ? _SuccessCard(
                            trip: _trip,
                            members: _members,
                            dates: _dates(_trip.isNotEmpty
                                ? _trip
                                : _preview!),
                            onView: () => context.go(
                                '/trips/${_preview!['tripId']}/map'),
                          )
                        : Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(22),
                                child: Image.asset(
                                  'assets/images/auth_travel.jpg',
                                  height: 170,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(height: 14),
                              JoinTripCard(
                                preview: _preview!,
                                dates: _dates(_preview!),
                                busy: _busy,
                                onJoin: _join,
                                onDecline: () =>
                                    context.go('/home'),
                              ),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  const _StateCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon,
                  color: const Color(0xFF2563EB), size: 36),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final List<Map<String, dynamic>> members;
  final String dates;
  final VoidCallback onView;
  const _SuccessCard({
    required this.trip,
    required this.members,
    required this.dates,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final s = (trip['startName'] ?? '').toString();
    final d = (trip['destName'] ?? '').toString();
    final route = s.isNotEmpty && d.isNotEmpty
        ? '$s → $d'
        : (trip['tripName'] ?? 'Trip').toString();
    final km = (trip['totalKm'] as num?)?.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color:
                    const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 10),
              const Text('You joined this trip',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const Text('Welcome to the adventure',
                  style: TextStyle(color: Color(0xFF64748B))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Trip Overview',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(route,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _row(Icons.group_outlined,
                    'Members: ${members.length}'),
                if (km != null)
                  _row(Icons.route_outlined,
                      'Distance: $km KM'),
                if (dates.isNotEmpty)
                  _row(Icons.calendar_month_outlined,
                      'Dates: $dates'),
                const SizedBox(height: 10),
                MemberAvatarList(members: members),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: onView,
            child: const Text('View Trip Plan'),
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
