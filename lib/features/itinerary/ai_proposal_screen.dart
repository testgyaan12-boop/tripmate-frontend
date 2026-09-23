import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;

/// Full editor for an AI proposal: reorder, edit, add/delete days,
/// then Confirm & Save (or Regenerate with the next free chance).
class AiProposalScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String proposalId;
  const AiProposalScreen(
      {super.key, required this.tripId, required this.proposalId});

  @override
  ConsumerState<AiProposalScreen> createState() => _State();
}

class _DayEdit {
  final String uid;
  final title = TextEditingController();
  final stay = TextEditingController();
  final food = TextEditingController();
  final stops = TextEditingController();
  final distance = TextEditingController();
  final drive = TextEditingController();

  _DayEdit(Map<String, dynamic> d, String seed)
      : uid = '$seed-${d['dayNo']}_x' {
    title.text = (d['title'] ?? '').toString();
    stay.text = (d['stay'] ?? '').toString();
    food.text = (d['food'] ?? '').toString();
    final s = d['stops'];
    stops.text = s is List ? s.join(', ') : '';
    distance.text = d['distanceKm']?.toString() ?? '';
    drive.text = d['driveMins']?.toString() ?? '';
  }

  Map<String, dynamic> toMap(int dayNo) => {
        'dayNo': dayNo,
        'title': title.text.trim(),
        'stops': stops.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'distanceKm': double.tryParse(distance.text.trim()),
        'driveMins': int.tryParse(drive.text.trim()),
        'stay': stay.text.trim(),
        'food': food.text.trim(),
      };

  void dispose() {
    title.dispose();
    stay.dispose();
    food.dispose();
    stops.dispose();
    distance.dispose();
    drive.dispose();
  }
}

class _State extends ConsumerState<AiProposalScreen> {
  String _proposalId = '';
  String _provider = '';
  int _remaining = 0;
  List<_DayEdit> _days = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _proposalId = widget.proposalId;
    _load(_proposalId);
  }

  void _reset(List<_DayEdit> days) {
    for (final d in _days) {
      d.dispose();
    }
    _days = days;
  }

  @override
  void dispose() {
    for (final d in _days) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load(String pid) async {
    setState(() => _loading = true);
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get(
            '/api/trips/${widget.tripId}/itinerary/ai/proposals/$pid'),
        dio.get('/api/trips/${widget.tripId}/itinerary/ai/quota'),
      ]);
      if (!mounted) return;
      final data =
          Map<String, dynamic>.from(res[0].data['data'] as Map);
      final quota =
          Map<String, dynamic>.from(res[1].data['data'] as Map);
      final seed = DateTime.now().microsecondsSinceEpoch.toString();
      _reset(((data['days'] as List?) ?? [])
          .map((e) => _DayEdit(Map<String, dynamic>.from(e), seed))
          .toList());
      setState(() {
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

  Future<void> _regenerate() async {
    setState(() => _busy = true);
    final dio = ref.read(dioClientProvider).dio;
    try {
      final cur = await dio.get(
          '/api/trips/${widget.tripId}/itinerary/ai/proposals/$_proposalId');
      final prev = Map<String, dynamic>.from(cur.data['data'] as Map);
      final res = await dio.post(
        '/api/trips/${widget.tripId}/itinerary/ai/propose',
        data: (prev['questions'] as Map?) ?? {},
      );
      final id = res.data['data']['proposalId'].toString();
      if (!mounted) return;
      setState(() => _proposalId = id);
      await _load(id);
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

  Future<void> _confirm() async {
    final payload =
        _days.asMap().entries.map((e) => e.value.toMap(e.key + 1)).toList();
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one day')),
      );
      return;
    }
    if (payload.any((d) => (d['title'] as String).isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every day needs a title')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.put(
        '/api/trips/${widget.tripId}/itinerary/ai/proposals/$_proposalId/confirm',
        data: {'days': payload},
      );
      final done =
          Map<String, dynamic>.from(res.data['data'] as Map);
      if (!mounted) return;
      bumpData(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Saved ${done['saved']} days · ${done['placesCreated']} new places ✨')),
      );
      context.go('/trips/${widget.tripId}/itinerary');
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
        title: const Text('AI trip plan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('/trips/${widget.tripId}/itinerary'),
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
                    _remaining < 0
                        ? 'Draft by $_provider · Unlimited AI plans (Pro) · drag days to reorder'
                        : 'Draft by $_provider · $_remaining of 2 free AI plans left · drag days to reorder',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF1D4ED8)),
                  ),
                ),
                Expanded(
                  child: _days.isEmpty
                      ? const Center(
                          child: Text('No days — add one below'))
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              16, 12, 16, 16),
                          itemCount: _days.length,
                          onReorderItem:
                              (fromIndex, toIndex) {
                            setState(() {
                              final d =
                                  _days.removeAt(fromIndex);
                              _days.insert(toIndex, d);
                            });
                          },
                          itemBuilder: (_, i) => _DayCard(
                            key: ValueKey(_days[i].uid),
                            index: i,
                            day: _days[i],
                            onDelete: () => setState(
                                () => _days.removeAt(i)),
                          ),
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _days.add(
                                  _DayEdit({}, DateTime.now()
                                          .microsecondsSinceEpoch
                                          .toString()))),
                          icon: const Icon(Icons.add),
                          tooltip: 'Add day',
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed:
                              _busy ? null : _regenerate,
                          child: Text(_busy
                              ? 'Working…'
                              : 'Regenerate'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          14),
                                ),
                              ),
                              onPressed:
                                  _busy ? null : _confirm,
                              child: const Text(
                                'Confirm & Save',
                                style: TextStyle(
                                    fontWeight:
                                        FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final int index;
  final _DayEdit day;
  final VoidCallback onDelete;
  const _DayCard({
    super.key,
    required this.index,
    required this.day,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Day ${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.drag_handle,
                    color: Color(0xFF94A3B8)),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFEF4444)),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _box(day.title, 'Day title'),
            const SizedBox(height: 8),
            _box(day.stops, 'Stops (comma separated)',
                maxLines: 2),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _box(day.distance, 'KM',
                        keyboard: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: _box(day.drive, 'Minutes',
                        keyboard: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 8),
            _box(day.stay, 'Stay'),
            const SizedBox(height: 8),
            _box(day.food, 'Food'),
          ],
        ),
      ),
    );
  }

  Widget _box(TextEditingController c, String hint,
      {int maxLines = 1, TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
