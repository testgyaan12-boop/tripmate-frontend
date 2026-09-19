import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';

/// Friendly full-screen state for non-members: shows trip info from the
/// public endpoint and offers a one-tap Join button.
class NotMemberCard extends StatefulWidget {
  final String tripId;
  final VoidCallback onRetry;
  const NotMemberCard(
      {super.key, required this.tripId, required this.onRetry});

  @override
  State<NotMemberCard> createState() => _State();
}

class _State extends State<NotMemberCard> {
  String? _tripName;
  String? _startName;
  String? _destName;
  String? _inviteCode;
  int _memberCount = 0;
  bool _loadingTrip = true;

  @override
  void initState() {
    super.initState();
    _loadTripInfo();
  }

  Future<void> _loadTripInfo() async {
    try {
      final res = await Dio().get(
        '${ApiConstants.baseUrl}/api/trips/${widget.tripId}/info',
      );
      if (!mounted) return;
      final d = Map<String, dynamic>.from(res.data['data'] as Map);
      setState(() {
        _tripName = (d['tripName'] ?? 'Trip').toString();
        _startName = (d['startName'] ?? '').toString();
        _destName = (d['destName'] ?? '').toString();
        _inviteCode = (d['inviteCode'] ?? '').toString();
        _memberCount = (d['memberCount'] as num?)?.toInt() ?? 0;
        _loadingTrip = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTrip = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _inviteCode != null && _inviteCode!.isNotEmpty
        ? '/join?code=$_inviteCode'
        : null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.group_off_outlined,
                  color: Color(0xFF2563EB), size: 38),
            ),
            const SizedBox(height: 14),
            if (_loadingTrip)
              const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              Text(
                _tripName ?? 'Trip',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (_startName!.isNotEmpty && _destName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$_startName → $_destName',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 14),
                  ),
                ),
              if (_memberCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$_memberCount members',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            const Text("You're not on this trip yet",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              'Ask a member for the invite code to join.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (route != null)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => context.go(route),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Join Trip'),
                ),
              )
            else
              const Text(
                'No invite code available. Ask a member to share one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onRetry,
                    child: const Text('Retry'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Back to Home'),
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
