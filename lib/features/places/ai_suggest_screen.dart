import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;

/// AI suggestion results: pick cards + Add selected (batch endpoint).
class AiSuggestScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String suggestionId;
  final int? dayNo;
  const AiSuggestScreen({
    super.key,
    required this.tripId,
    required this.suggestionId,
    this.dayNo,
  });

  @override
  ConsumerState<AiSuggestScreen> createState() => _State();
}

class _State extends ConsumerState<AiSuggestScreen> {
  List<Map<String, dynamic>> _places = [];
  final _picked = <int>{};
  String _provider = '';
  int _remaining = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get(
            '/api/trips/${widget.tripId}/places/ai/suggestions/${widget.suggestionId}'),
        dio.get('/api/trips/${widget.tripId}/places/ai/quota'),
      ]);
      if (!mounted) return;
      final data =
          Map<String, dynamic>.from(res[0].data['data'] as Map);
      final quota =
          Map<String, dynamic>.from(res[1].data['data'] as Map);
      final list = ((data['places'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _places = list;
        _picked.addAll(List.generate(list.length, (i) => i));
        _provider = (data['provider'] ?? '').toString();
        _remaining = ((quota['remaining'] ?? 0) as num).toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  Future<void> _addSelected() async {
    if (_picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one place')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.post(
        '/api/trips/${widget.tripId}/places/ai/suggestions/${widget.suggestionId}/add',
        data: {
          'indexes': _picked.toList(),
          if (widget.dayNo != null) 'dayNo': widget.dayNo,
        },
      );
      final added = res.data['data']['added'];
      if (!mounted) return;
      bumpData(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $added place(s) to your trip ✨')),
      );
      context.go('/trips/${widget.tripId}/places');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('AI suggestions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('/trips/${widget.tripId}/places'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Picked by $_provider · $_remaining of 5 suggestion batches left · coordinates verified where possible',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF1D4ED8)),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: _places.length,
                    itemBuilder: (_, i) {
                      final p = _places[i];
                      final on = _picked.contains(i);
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: 12),
                        child: _SuggestCard(
                          place: p,
                          picked: on,
                          onToggle: () => setState(() => on
                              ? _picked.remove(i)
                              : _picked.add(i)),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                        ),
                        onPressed: _busy ? null : _addSelected,
                        child: Text(_busy
                            ? 'Adding…'
                            : 'Add selected (${_picked.length})'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SuggestCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final bool picked;
  final VoidCallback onToggle;
  const _SuggestCard({
    required this.place,
    required this.picked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final verified = place['verified'] == true;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: picked
            ? const BorderSide(color: Color(0xFF2563EB), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: picked, onChanged: (_) => onToggle()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (place['name'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((place['address']?.toString() ?? '')
                        .isNotEmpty)
                      Text(
                        place['address'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    const SizedBox(height: 6),
                    if ((place['reason']?.toString() ?? '')
                        .isNotEmpty)
                      Text(
                        '✨ ${place['reason']}',
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Color(0xFF334155),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if ((place['category']?.toString() ??
                                '')
                            .isNotEmpty)
                          _Tag(
                              text: place['category'].toString(),
                              color: const Color(0xFF2563EB)),
                        _Tag(
                          text: verified
                              ? '✅ verified pin'
                              : '⚠️ approximate pin',
                          color: verified
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
