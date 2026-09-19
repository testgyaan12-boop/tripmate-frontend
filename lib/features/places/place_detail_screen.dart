import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';
import 'presentation/widgets/place_gallery.dart';

/// Place details: gallery header, info, big 3-way vote, Reddit-style discussion.
class PlaceDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String placeId;
  const PlaceDetailScreen(
      {super.key, required this.tripId, required this.placeId});

  @override
  ConsumerState<PlaceDetailScreen> createState() => _State();
}

class _State extends ConsumerState<PlaceDetailScreen> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _comments = [];
  String? _distance;
  final _msg = TextEditingController();
  bool _sending = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlaceDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId ||
        old.placeId != widget.placeId) {
      _load();
    }
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/places/${widget.placeId}'),
        dio.get('/api/places/${widget.placeId}/comments'),
        dio.get('/api/trips/${widget.tripId}'),
      ]);
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res[0].data['data']);
      final p = Map<String, dynamic>.from(data['place']);
      String? dist;
      try {
        final t = Map<String, dynamic>.from(res[2].data['data'] as Map);
        final lat = (p['latitude'] as num?)?.toDouble();
        final lng = (p['longitude'] as num?)?.toDouble();
        final slat = (t['startLat'] as num?)?.toDouble();
        final slng = (t['startLng'] as num?)?.toDouble();
        if (lat != null && lng != null && slat != null && slng != null) {
          final km = const Distance().as(
              LengthUnit.Kilometer, LatLng(slat, slng), LatLng(lat, lng));
          dist = '${km.round()} KM away';
        }
      } catch (_) {}
      setState(() {
        _data = data;
        _comments = ((res[1].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _distance = dist;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _vote(String v) async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      await dio.post('/api/places/${widget.placeId}/vote',
          data: {'vote': v});
      bumpData(ref);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _send() async {
    if (_msg.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      await dio.post('/api/places/${widget.placeId}/comments',
          data: {'message': _msg.text.trim()});
      bumpData(ref);
      _msg.clear();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) => _load());
    ref.listen(tabRefreshRequestProvider, (_, req) {
      if (req != null && req.tab == 1) _load();
    });
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load this place'),
                    TextButton(
                        onPressed: _load,
                        child: const Text('Retry')),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final p = Map<String, dynamic>.from(_data!['place']);
    final votes = Map<String, dynamic>.from(_data!['votes'] ?? {});
    final my = _data!['myVote']?.toString();
    final img = (p['imageUrl'] as String?) ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Color(0xFF0F172A)),
                    onPressed: () =>
                        context.go('/trips/${widget.tripId}/places'),
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlaceGallery(
                      placeId: (p['id'] as num?)?.toInt(),
                      imageUrl: img.isNotEmpty ? img : null,
                      fallback: 'assets/images/trip_hero.jpg',
                      height: 280,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x550B1220),
                            Color(0x000B1220),
                            Color(0xCC0B1220),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((p['category']?.toString() ?? '')
                              .isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                p['category'].toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            (p['name'] ?? '').toString(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _InfoCard(p: p, distance: _distance),
                    const SizedBox(height: 14),
                    _VoteCard(
                      votes: votes,
                      myVote: my,
                      onVote: _vote,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text(
                          'Discussion',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_comments.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_comments.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              'No comments yet. Start the discussion!',
                              style: TextStyle(
                                  color: Color(0xFF64748B)),
                            ),
                          ),
                        ),
                      )
                    else
                      ..._comments.map((c) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 8),
                            child: _CommentTile(comment: c),
                          )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msg,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Join the discussion…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Map<String, dynamic> p;
  final String? distance;
  const _InfoCard({required this.p, required this.distance});

  @override
  Widget build(BuildContext context) {
    final rating = (p['rating'] as num?)?.toDouble();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((p['address']?.toString() ?? '').isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p['address'].toString(),
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
            if (distance != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.route,
                      size: 16, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Text(
                    distance!,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF334155)),
                  ),
                  if (rating != null) ...[
                    const Spacer(),
                    const Icon(Icons.star,
                        size: 16, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ],
            if ((p['description']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                p['description'].toString(),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoteCard extends StatelessWidget {
  final Map<String, dynamic> votes;
  final String? myVote;
  final void Function(String) onVote;
  const _VoteCard(
      {required this.votes, required this.myVote, required this.onVote});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Do you want to visit this place?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _VoteButton(
                    emoji: '👍',
                    label: 'YES\nVisit',
                    count: (votes['VISIT'] ?? 0).toString(),
                    color: const Color(0xFF10B981),
                    selected: myVote == 'VISIT',
                    onTap: () => onVote('VISIT'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VoteButton(
                    emoji: '🤔',
                    label: 'MAYBE\nLater',
                    count: (votes['MAYBE'] ?? 0).toString(),
                    color: const Color(0xFFF59E0B),
                    selected: myVote == 'MAYBE',
                    onTap: () => onVote('MAYBE'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VoteButton(
                    emoji: '👎',
                    label: 'NO\nSkip',
                    count: (votes['SKIP'] ?? 0).toString(),
                    color: const Color(0xFFF43F5E),
                    selected: myVote == 'SKIP',
                    onTap: () => onVote('SKIP'),
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

class _VoteButton extends StatelessWidget {
  final String emoji;
  final String label;
  final String count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _VoteButton({
    required this.emoji,
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : const Color(0xFF334155),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _CommentTile({required this.comment});

  static const _avatarColors = [
    Color(0xFF2563EB),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF10B981),
  ];

  String _ago(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = (comment['userId'] as num?)?.toInt() ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: _avatarColors[uid % _avatarColors.length],
              child: Text(
                'T',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Traveller $uid',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _ago(comment['createdAt']?.toString()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (comment['message'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
