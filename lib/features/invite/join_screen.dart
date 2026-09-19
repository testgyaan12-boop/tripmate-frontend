import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_error.dart';
import '../../core/router/pending_invite.dart';
import '../../core/storage/token_storage.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;

/// Invite landing: public trip preview, then login-gated join.
/// Opened from shared links (/join?code= or /#/join?code=).
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
      if (!mounted) return;
      context.go('/trips/$tripId/map');
    } catch (e) {
      // 401 (dead session) auto-redirects to login via onAuthLost,
      // with the pending code intact for the ride back.
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  String _dates() {
    final s = _preview?['startDate']?.toString();
    final e = _preview?['endDate']?.toString();
    try {
      if (s != null && e != null) {
        return '${DateFormat('d MMM').format(DateTime.parse(s))} – ${DateFormat('d MMM yyyy').format(DateTime.parse(e))}';
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Trip invite')),
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
                    : _InviteCard(
                        preview: _preview!,
                        dates: _dates(),
                        busy: _busy,
                        onJoin: _join,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
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

class _InviteCard extends StatelessWidget {
  final Map<String, dynamic> preview;
  final String dates;
  final bool busy;
  final VoidCallback onJoin;
  const _InviteCard({
    required this.preview,
    required this.dates,
    required this.busy,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final route =
        '${preview['startName'] ?? ''} → ${preview['destName'] ?? ''}';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "You've been invited! 🎉",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  (preview['tripName'] ?? 'Trip').toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (route.trim() != '→')
                  Text(route,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dates.isNotEmpty)
                  _MetaRow(icon: Icons.calendar_month_outlined, text: dates),
                _MetaRow(
                  icon: Icons.group_outlined,
                  text:
                      '${preview['memberCount'] ?? 0} member(s) already in',
                ),
                const SizedBox(height: 16),
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
                    onPressed: busy ? null : onJoin,
                    child:
                        Text(busy ? 'Joining…' : 'Join Trip'),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'You will be asked to login first if needed.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
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
