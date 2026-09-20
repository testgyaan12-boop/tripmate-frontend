import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';

/// Trip activity timeline — who joined, when, RSVP changes.
class TripHistoryScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripHistoryScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<TripHistoryScreen> {
  List<Map<String, dynamic>> _activity = [];
  List<Map<String, dynamic>> _pastMembers = [];
  bool _loading = true;
  int? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/${widget.tripId}/activity'),
        dio.get('/api/trips/${widget.tripId}/past-members'),
        dio.get('/api/users/me'),
      ]);
      if (!mounted) return;
      setState(() {
        _activity = ((res[0].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _pastMembers = ((res[1].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _me = (res[2].data['data']['id'] as num?)?.toInt();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
        setState(() => _loading = false);
      }
    }
  }

  String _actionIcon(String action) {
    switch (action) {
      case 'CREATED':
        return '🎉';
      case 'JOINED':
        return '👋';
      case 'LEFT':
        return '🚪';
      case 'REMOVED':
        return '❌';
      case 'RSVP_CHANGED':
        return '📋';
      case 'INVITED':
        return '📩';
      default:
        return '📌';
    }
  }

  String _actionText(String action) {
    switch (action) {
      case 'CREATED':
        return 'created this trip';
      case 'JOINED':
        return 'joined the trip';
      case 'LEFT':
        return 'left the trip';
      case 'REMOVED':
        return 'was removed';
      case 'RSVP_CHANGED':
        return 'updated RSVP';
      case 'INVITED':
        return 'shared invite';
      default:
        return action.toLowerCase().replaceAll('_', ' ');
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'CREATED':
        return const Color(0xFF8B5CF6);
      case 'JOINED':
        return const Color(0xFF10B981);
      case 'LEFT':
      case 'REMOVED':
        return const Color(0xFFEF4444);
      case 'RSVP_CHANGED':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6366F1);
    }
  }

  void _shareSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ShareSheet(
        tripId: widget.tripId,
        pastMembers: _pastMembers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Trip History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share with past members',
            onPressed: _shareSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _activity.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(Icons.history,
                            color: Color(0xFF10B981), size: 36),
                      ),
                      const SizedBox(height: 14),
                      const Text('No activity yet',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text(
                        'Activity will appear here as members join, leave, or update their RSVP.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _activity.length,
                    itemBuilder: (_, i) {
                      final a = _activity[i];
                      final name = (a['name'] ?? 'Someone').toString();
                      final action = (a['action'] ?? '').toString();
                      final detail = (a['detail'] ?? '').toString();
                      final ts = a['createdAt'];
                      final dt = ts != null
                          ? DateFormat('MMM d, h:mm a')
                              .format(DateTime.parse(ts.toString()))
                          : '';
                      final icon = _actionIcon(action);
                      final color = _actionColor(action);
                      final isMe = ((a['userId'] as num?) ?? -1).toInt() == _me;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(icon,
                                        style:
                                            const TextStyle(fontSize: 18)),
                                  ),
                                ),
                                if (i < _activity.length - 1)
                                  Container(
                                    width: 2,
                                    height: 24,
                                    color: const Color(0xFFE2E8F0),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: RichText(
                                            text: TextSpan(
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.black87),
                                              children: [
                                                TextSpan(
                                                  text: isMe ? 'You' : name,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700),
                                                ),
                                                TextSpan(
                                                    text:
                                                        ' ${_actionText(action)}'),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (detail.isNotEmpty &&
                                        action != 'CREATED' &&
                                        action != 'JOINED')
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4),
                                        child: Text(detail,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF94A3B8))),
                                      ),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4),
                                      child: Text(dt,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFCBD5E1))),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _ShareSheet extends StatelessWidget {
  final String tripId;
  final List<Map<String, dynamic>> pastMembers;
  const _ShareSheet({required this.tripId, required this.pastMembers});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text('Share with past members',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Re-share the trip invite with people who were previously part of this trip.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (pastMembers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text('No past members found',
                    style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            )
          else
            ...pastMembers.map((m) {
              final name = (m['name'] ?? 'Unknown').toString();
              final email = (m['email'] ?? '').toString();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEFF6FF),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Color(0xFF2563EB), fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(email,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF94A3B8))),
                trailing: IconButton(
                  icon: const Icon(Icons.share_outlined, size: 20),
                  onPressed: () {
                    Share.share(
                      'Join my TripMate trip! Use code to join: http://localhost:8080/join?code=$tripId',
                      subject: 'TripMate invite',
                    );
                  },
                ),
              );
            }),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}
