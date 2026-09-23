import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../places/presentation/widgets/place_gallery.dart';
import '../../core/network/api_error.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/not_member_card.dart';
import '../../shared/widgets/top_bar.dart' show DarkModeToggle, NotificationsButton;
import '../../shared/widgets/trip_selector_sheet.dart';
import '../../core/data/refresh.dart';
import 'ai_questions_sheet.dart';

const _fallbacks = [
  'assets/images/trip_hero.jpg',
  'assets/images/trip_goa.jpg',
  'assets/images/splash_road.jpg',
  'assets/images/auth_travel.jpg',
];

/// Stops for a timeline leg: persisted stopsJson string, else legacy list.
List<String> _stopsOf(Map<String, dynamic> item) {
  final raw = item['stops'];
  if (raw is List) {
    return raw.map((e) => e.toString()).toList();
  }
  final js = item['stopsJson']?.toString() ?? '';
  if (js.isEmpty) return [];
  try {
    final dec = jsonDecode(js);
    if (dec is List) return dec.map((e) => e.toString()).toList();
  } catch (_) {}
  return [];
}

/// Travel-journal itinerary: vertical timeline grouped by day, leg cards
/// with image, distance, travel time, stay and food.
class ItineraryScreen extends ConsumerStatefulWidget {
  final String tripId;
  const ItineraryScreen({super.key, required this.tripId});

  @override
  ConsumerState<ItineraryScreen> createState() => _State();
}

class _State extends ConsumerState<ItineraryScreen> {
  Map<String, dynamic>? _trip;
  List<Map<String, dynamic>> _items = [];
  Map<int, Map<String, dynamic>> _places = {};
  bool _busy = false;
  bool _loading = true;
  bool _notMember = false;
  final int _imgSeed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ItineraryScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) {
      // Trip switched: drop stale data, show loader while new data loads.
      setState(() {
        _loading = true;
        _notMember = false;
        _trip = null;
        _items = [];
        _places = {};
      });
      _load();
    }
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/${widget.tripId}'),
        dio.get('/api/trips/${widget.tripId}/itinerary'),
        dio.get('/api/trips/${widget.tripId}/places'),
      ]);
      if (!mounted) return;
      final places = <int, Map<String, dynamic>>{};
      for (final e in (res[2].data['data'] as List)) {
        final p = Map<String, dynamic>.from(e['place']);
        places[(p['id'] as num).toInt()] = p;
      }
      setState(() {
        _trip = Map<String, dynamic>.from(res[0].data['data'] as Map);
        _items = ((res[1].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _places = places;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        if (isNotMemberError(e)) {
          setState(() {
            _loading = false;
            _notMember = true;
          });
        } else {
          setState(() => _loading = false);
        }
      }
    }
  }

  /// AI flow: quota -> detailed questions -> propose -> full editor.
  Future<void> _aiPlan() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final q = await dio
          .get('/api/trips/${widget.tripId}/itinerary/ai/quota');
      final remaining =
          ((q.data['data']['remaining'] ?? 0) as num).toInt();
      if (!mounted) return;
      if (remaining <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Free AI plans used (2/2 for this trip). Use Quick plan.')),
        );
        return;
      }
      final answers = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => AiQuestionsSheet(remaining: remaining),
      );
      if (answers == null || !mounted) return;
      setState(() => _busy = true);
      final res = await dio.post(
        '/api/trips/${widget.tripId}/itinerary/ai/propose',
        data: answers,
      );
      final pid = res.data['data']['proposalId'].toString();
      if (!mounted) return;
      context.go('/trips/${widget.tripId}/itinerary/ai/$pid');
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

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final days = (_trip?['daysCount'] as num?)?.toInt() ?? 5;
      await dio.put(
          '/api/trips/${widget.tripId}/itinerary/generate?days=$days');
      bumpData(ref);
      await _load();
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

  String _cleanTitle(String t) {
    var s = t;
    for (final suffix in [' — journey begins', ' — arrival', ' · on the road']) {
      if (s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length);
      }
    }
    final m = RegExp(r'^(.*) · day \d+$').firstMatch(s);
    if (m != null) s = m.group(1)!;
    return s.trim();
  }

  String _legAnchor(int dayNo, bool isFrom) {
    final byDay = <int, List<Map<String, dynamic>>>{};
    for (final it in _items) {
      byDay.putIfAbsent((it['dayNo'] as num?)?.toInt() ?? 1, () => []).add(it);
    }
    final days = byDay.keys.toList()..sort();
    final idx = days.indexOf(dayNo);
    if (isFrom) {
      if (idx > 0) {
        final t = _cleanTitle(
            (byDay[days[idx - 1]]!.last['title'] ?? '').toString());
        if (t.isNotEmpty) return t;
      }
      return _trip?['startName']?.toString() ?? '';
    }
    if (idx >= 0 && idx < days.length - 1) {
      final t = _cleanTitle(
          (byDay[days[idx]]!.last['title'] ?? '').toString());
      if (t.isNotEmpty) return t;
    }
    return _trip?['destName']?.toString() ?? '';
  }

  /// Day-wise AI: prefilled leg sheet -> suggest -> results (stamped on add).
  Future<void> _suggestDay(int day, String from, String to) async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final q = await dio
          .get('/api/trips/${widget.tripId}/places/ai/quota');
      final remaining =
          ((q.data['data']['remaining'] ?? 0) as num).toInt();
      if (!mounted) return;
      if (remaining <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Free suggestions used (5/5 for this trip).')),
        );
        return;
      }
      final req = await showModalBottomSheet<_DaySuggestReq>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _DaySuggestSheet(
            day: day, from: from, to: to, remaining: remaining),
      );
      if (req == null || !mounted) return;
      final res = await dio.post(
        '/api/trips/${widget.tripId}/places/ai/suggest',
        data: {
          'count': req.count,
          'dayNo': day,
          'from': req.from,
          'to': req.to,
        },
      );
      final sid = res.data['data']['suggestionId'].toString();
      if (!mounted) return;
      context.go('/trips/${widget.tripId}/places/ai/$sid?day=$day');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _createManualItem(int dayNo) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddItemSheet(
        dayNo: dayNo,
        tripId: widget.tripId,
        places: _places,
        onPlaceAdded: (p) {
          setState(() => _places[p['id'] as int] = p);
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      await dio.post('/api/trips/${widget.tripId}/itinerary', data: {
        'dayNo': dayNo,
        'title': result['title'],
        'placeId': result['placeId'],
        'stopsJson': result['stopsJson'],
        'stayNotes': result['stayNotes'],
        'foodNotes': result['foodNotes'],
        'distanceKm': result['distanceKm'],
        'driveMins': result['driveMins'],
      });
      bumpData(ref);
      await _load();
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

  Future<void> _updateItem(Map<String, dynamic> item) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddItemSheet(
        dayNo: (item['dayNo'] as num?)?.toInt() ?? 1,
        existing: item,
        tripId: widget.tripId,
        places: _places,
        onPlaceAdded: (p) {
          setState(() => _places[p['id'] as int] = p);
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final id = item['id'];
      await dio.put('/api/trips/${widget.tripId}/itinerary/$id', data: {
        'title': result['title'],
        'dayNo': result['dayNo'],
        'placeId': result['placeId'],
        'stopsJson': result['stopsJson'],
        'stayNotes': result['stayNotes'],
        'foodNotes': result['foodNotes'],
        'distanceKm': result['distanceKm'],
        'driveMins': result['driveMins'],
      });
      bumpData(ref);
      await _load();
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

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${item['title'] ?? ''}" from itinerary?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      await dio.delete('/api/trips/${widget.tripId}/itinerary/${item['id']}');
      bumpData(ref);
      await _load();
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

  String _dayDate(int day) {
    final s = _trip?['startDate']?.toString();
    if (s == null) return 'Day $day';
    try {
      final date =
          DateTime.parse(s).add(Duration(days: day - 1));
      return 'Day $day · ${DateFormat('EEE, d MMM').format(date)}';
    } catch (_) {
      return 'Day $day';
    }
  }

  String _minsLabel(dynamic mins) {
    if (mins == null) return '–';
    final m = (mins as num).toInt();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final r = m % 60;
    if (r == 0) return '$h Hours';
    return '${h}h ${r}m';
  }

  /// Tap a stop chip: open its place page, or explain when missing.
  void _openStopByName(String name) {
    final needle = name.toLowerCase();
    for (final p in _places.values) {
      if ((p['name']?.toString() ?? '').toLowerCase() == needle) {
        context.go('/trips/${widget.tripId}/places/${p['id']}');
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('“$name” is not added as a place yet')),
    );
  }

  /// Tap a day: linked place opens its detail page, otherwise a day sheet.
  void _openStop(Map<String, dynamic> item) {
    final pid = (item['placeId'] as num?)?.toInt();
    if (pid != null) {
      context.go('/trips/${widget.tripId}/places/$pid');
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _DayInfoSheet(
        item: item,
        minsLabel: _minsLabel,
        onOpenPlaces: () {
          Navigator.pop(sheetCtx);
          context.go('/trips/${widget.tripId}/places');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) => _load());
    ref.listen(tabRefreshRequestProvider, (_, req) {
      if (req != null && req.tab == 2) _load();
    });
    final byDay = <int, List<Map<String, dynamic>>>{};
    for (final it in _items) {
      byDay.putIfAbsent((it['dayNo'] as num?)?.toInt() ?? 1, () => []).add(it);
    }
    final days = byDay.keys.toList()..sort();
    final skeleton =
        _items.isNotEmpty && _items.every((e) => e['placeId'] == null);
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: TripDropdown(tripId: widget.tripId),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/trips/${widget.tripId}/map'),
        ),
        actions: [
          const DarkModeToggle(),
          const NotificationsButton(),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _notMember
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _aiPlan,
              label: Text(_busy ? 'Working…' : '✨ AI Plan'),
              icon: const Icon(Icons.auto_awesome),
            ),
      body: _notMember
          ? NotMemberCard(tripId: widget.tripId, onRetry: _load)
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : days.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.card(context),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.timeline,
                            color: Color(0xFF2563EB),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No itinerary yet',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Add places with locations and votes for a detailed day-wise plan — or generate a route skeleton right now.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _generate,
                            icon:
                                const Icon(Icons.auto_awesome),
                            label: Text(_busy
                                ? 'Generating…'
                                : 'Quick plan'),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => context.go(
                              '/trips/${widget.tripId}/places'),
                          icon: const Icon(Icons.add_location_alt,
                              size: 18),
                          label: const Text('Add places first'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(20, 12, 20, 100),
                    itemCount: days.length + (skeleton ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (skeleton && i == 0) {
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: 12),
                          child: _SkeletonBanner(
                            onAddPlaces: () => context.go(
                                '/trips/${widget.tripId}/places'),
                          ),
                        );
                      }
                      final k = skeleton ? i - 1 : i;
                      final dayNo = days[k];
                      return _DaySection(
                        label: _dayDate(dayNo),
                        isLast: k == days.length - 1,
                        onSuggest: () => _suggestDay(
                          dayNo,
                          _legAnchor(dayNo, true),
                          _legAnchor(dayNo, false),
                        ),
                        onAddItem: () => _createManualItem(dayNo),
                        children: [
                          for (var j = 0;
                              j < byDay[days[k]]!.length;
                              j++) ...[
                          _LegCard(
                            item: byDay[days[k]]![j],
                            onTap: () =>
                                _openStop(byDay[days[k]]![j]),
                            onStopTap: _openStopByName,
                              place: _places[(
                                  byDay[days[k]]![j]['placeId']
                                      as num?)
                                  ?.toInt()],
                              image: _fallbacks[
                                  (_imgSeed + k + j) %
                                      _fallbacks.length],
                              minsLabel: _minsLabel,
                              onEdit: () => _updateItem(byDay[days[k]]![j]),
                              onDelete: () => _deleteItem(byDay[days[k]]![j]),
                            ),
                            if (j < byDay[days[k]]!.length - 1)
                              const _LegConnector(),
                          ],
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}

class _SkeletonBanner extends StatelessWidget {
  final VoidCallback onAddPlaces;
  const _SkeletonBanner({required this.onAddPlaces});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome,
                color: Color(0xFF2563EB)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Route skeleton — add places with votes, then regenerate for a detailed plan.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
            TextButton(
              onPressed: onAddPlaces,
              child: const Text('Add places'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySuggestReq {
  final int count;
  final String from;
  final String to;
  _DaySuggestReq(
      {required this.count, required this.from, required this.to});
}

class _DaySuggestSheet extends StatefulWidget {
  final int day;
  final String from;
  final String to;
  final int remaining;
  const _DaySuggestSheet({
    required this.day,
    required this.from,
    required this.to,
    required this.remaining,
  });

  @override
  State<_DaySuggestSheet> createState() => _DaySuggestSheetState();
}

class _DaySuggestSheetState extends State<_DaySuggestSheet> {
  late final _from = TextEditingController(text: widget.from);
  late final _to = TextEditingController(text: widget.to);
  int _count = 5;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '✨ Day ${widget.day} picks',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800),
            ),
            Text(
              '${widget.remaining} of 5 suggestion batches left · 1 day = 1 chance',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            _sheetField(_from, 'From'),
            const SizedBox(height: 8),
            _sheetField(_to, 'To'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [3, 5, 8]
                  .map((c) => ChoiceChip(
                        label: Text('$c places'),
                        selected: _count == c,
                        onSelected: (_) =>
                            setState(() => _count = c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(
                    context,
                    _DaySuggestReq(
                        count: _count,
                        from: _from.text.trim(),
                        to: _to.text.trim())),
                icon:
                    const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Suggest stops'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final String label;
  final bool isLast;
  final List<Widget> children;
  final VoidCallback? onSuggest;
  final VoidCallback? onAddItem;
  const _DaySection({
    required this.label,
    required this.isLast,
    required this.children,
    this.onSuggest,
    this.onAddItem,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label.split('·').first.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  width: 2.5,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isLast
                        ? Colors.transparent
                        : const Color(0xFF2563EB)
                            .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      if (onSuggest != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onSuggest,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      if (onAddItem != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onAddItem,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.add_circle_outline,
                              size: 18,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ...children,
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic>? place;
  final String image;
  final String Function(dynamic) minsLabel;
  final VoidCallback? onTap;
  final void Function(String)? onStopTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _LegCard({
    required this.item,
    required this.place,
    required this.image,
    required this.minsLabel,
    this.onTap,
    this.onStopTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final img = (place?['imageUrl'] as String?) ?? '';
    final km = (item['distanceKm'] as num?)?.toDouble();
    final stay = (item['stayNotes']?.toString() ?? '').isNotEmpty
        ? item['stayNotes'].toString()
        : null;
    final food = (item['foodNotes']?.toString() ?? '').isNotEmpty
        ? item['foodNotes'].toString()
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlaceGallery(
            placeId: (place?['id'] as num?)?.toInt(),
            imageUrl: img.isNotEmpty ? img : null,
            fallback: image,
            height: 140,
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (item['title'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    if (onEdit != null || onDelete != null)
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: AppColors.textMuted(context),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (v) {
                          if (v == 'edit') onEdit?.call();
                          if (v == 'delete') onDelete?.call();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 18, color: Colors.red[600]),
                                const SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red[600])),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if ((place?['address']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      place!['address'].toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                if (_stopsOf(item).isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _stopsOf(item)
                        .map((s) => ActionChip(
                              label: Text(s,
                                  style: const TextStyle(
                                      fontSize: 11)),
                              avatar: const Icon(
                                  Icons.place_outlined,
                                  size: 14,
                                  color: Color(0xFF2563EB)),
                              onPressed: () =>
                                  onStopTap?.call(s),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(
                      icon: Icons.route,
                      text: km == null ? '– KM' : '${km.round()} KM',
                    ),
                    _Chip(
                      icon: Icons.schedule,
                      text: minsLabel(item['driveMins']),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _NoteRow(
                  icon: Icons.hotel_outlined,
                  label: 'Stay',
                  value: stay ?? 'Not planned yet',
                  dim: stay == null,
                ),
                const SizedBox(height: 6),
                _NoteRow(
                  icon: Icons.restaurant_outlined,
                  label: 'Food',
                  value: food ?? 'Not planned yet',
                  dim: food == null,
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

class _DayInfoSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final String Function(dynamic) minsLabel;
  final VoidCallback onOpenPlaces;
  const _DayInfoSheet({
    required this.item,
    required this.minsLabel,
    required this.onOpenPlaces,
  });

  @override
  Widget build(BuildContext context) {
    final stops = _stopsOf(item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            (item['title'] ?? '').toString(),
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (stops.isNotEmpty)
            ...stops.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          size: 15, color: Color(0xFF2563EB)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(s.toString(),
                              style:
                                  const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _Chip(
                icon: Icons.route,
                text: item['distanceKm'] == null
                    ? '– KM'
                    : '${(item['distanceKm'] as num).round()} KM',
              ),
              _Chip(
                icon: Icons.schedule,
                text: minsLabel(item['driveMins']),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _NoteRow(
            icon: Icons.hotel_outlined,
            label: 'Stay',
            value: (item['stayNotes']?.toString() ?? '').isNotEmpty
                ? item['stayNotes'].toString()
                : (item['stay']?.toString() ?? '').isNotEmpty
                    ? item['stay'].toString()
                    : 'Not planned yet',
            dim: ((item['stayNotes']?.toString() ?? '').isEmpty &&
                (item['stay']?.toString() ?? '').isEmpty),
          ),
          const SizedBox(height: 6),
          _NoteRow(
            icon: Icons.restaurant_outlined,
            label: 'Food',
            value: (item['foodNotes']?.toString() ?? '').isNotEmpty
                ? item['foodNotes'].toString()
                : (item['food']?.toString() ?? '').isNotEmpty
                    ? item['food'].toString()
                    : 'Not planned yet',
            dim: ((item['foodNotes']?.toString() ?? '').isEmpty &&
                (item['food']?.toString() ?? '').isEmpty),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onOpenPlaces,
              child: const Text('Open Places tab'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tip: vote 👍 on these places to choose tonight\'s stay',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
          ),
        ],
      ),
    );
  }
}

class _LegConnector extends StatelessWidget {
  const _LegConnector();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 8),
          Icon(Icons.arrow_downward,
              size: 18, color: Color(0xFF2563EB)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF2563EB)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D4ED8),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool dim;
  const _NoteRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: dim
                  ? AppColors.textMuted(context)
                  : AppColors.textPrimary(context),
              fontStyle: dim ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ],
    );
  }
}

class _AddItemSheet extends ConsumerStatefulWidget {
  final int dayNo;
  final String tripId;
  final Map<String, dynamic>? existing;
  final Map<int, Map<String, dynamic>> places;
  final void Function(Map<String, dynamic> place) onPlaceAdded;
  const _AddItemSheet({
    required this.dayNo,
    required this.tripId,
    required this.places,
    required this.onPlaceAdded,
    this.existing,
  });

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  late final TextEditingController _titleC;
  late final TextEditingController _stayC;
  late final TextEditingController _foodC;
  late final TextEditingController _kmC;
  late final TextEditingController _minsC;
  late int _dayNo;
  final Set<int> _selectedPlaceIds = {};

  // inline add place
  bool _showAddPlace = false;
  bool _placeSaving = false;
  late final TextEditingController _placeNameC;
  late final TextEditingController _placeAddrC;
  String _placeCategory = 'Other';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleC = TextEditingController(text: e?['title']?.toString() ?? '');
    _stayC = TextEditingController(text: e?['stayNotes']?.toString() ?? '');
    _foodC = TextEditingController(text: e?['foodNotes']?.toString() ?? '');
    _kmC = TextEditingController(
        text: e?['distanceKm'] != null ? (e!['distanceKm'] as num).toString() : '');
    _minsC = TextEditingController(
        text: e?['driveMins'] != null ? (e!['driveMins'] as num).toString() : '');
    _dayNo = widget.dayNo;
    final pid = (e?['placeId'] as num?)?.toInt();
    if (pid != null) _selectedPlaceIds.add(pid);
    _placeNameC = TextEditingController();
    _placeAddrC = TextEditingController();
  }

  @override
  void dispose() {
    _titleC.dispose();
    _stayC.dispose();
    _foodC.dispose();
    _kmC.dispose();
    _minsC.dispose();
    _placeNameC.dispose();
    _placeAddrC.dispose();
    super.dispose();
  }

  void _togglePlace(Map<String, dynamic> place) {
    final pid = place['id'] as int;
    setState(() {
      if (_selectedPlaceIds.contains(pid)) {
        _selectedPlaceIds.remove(pid);
      } else {
        _selectedPlaceIds.add(pid);
      }
      if (_selectedPlaceIds.length == 1) {
        final only = widget.places[_selectedPlaceIds.first];
        if (only != null) _titleC.text = only['name']?.toString() ?? '';
      } else if (_selectedPlaceIds.isEmpty) {
        _titleC.clear();
      }
    });
  }

  static const _categories = [
    'Nature', 'Waterfall', 'Food', 'Stay', 'Viewpoint', 'Temple', 'Adventure', 'Other',
  ];

  Future<void> _savePlace() async {
    if (_placeNameC.text.trim().isEmpty) return;
    setState(() => _placeSaving = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.post('/api/trips/${widget.tripId}/places', data: {
        'name': _placeNameC.text.trim(),
        'address': _placeAddrC.text.trim().isEmpty ? null : _placeAddrC.text.trim(),
        'category': _placeCategory,
      });
      final place = Map<String, dynamic>.from(res.data['data'] as Map);
      widget.onPlaceAdded(place);
      final pid = (place['id'] as num).toInt();
      setState(() {
        _selectedPlaceIds.add(pid);
        _titleC.text = place['name']?.toString() ?? '';
        _showAddPlace = false;
        _placeNameC.clear();
        _placeAddrC.clear();
        _placeCategory = 'Other';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _placeSaving = false);
    }
  }

  void _submit() {
    if (_titleC.text.trim().isEmpty) return;
    final km = double.tryParse(_kmC.text.trim());
    final mins = int.tryParse(_minsC.text.trim());
    final names = _selectedPlaceIds
        .map((id) => widget.places[id]?['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    Navigator.pop(context, {
      'title': _titleC.text.trim(),
      'dayNo': _dayNo,
      'placeId': _selectedPlaceIds.isNotEmpty ? _selectedPlaceIds.first : null,
      'stopsJson': names.isNotEmpty ? jsonEncode(names) : null,
      'stayNotes': _stayC.text.trim(),
      'foodNotes': _foodC.text.trim(),
      'distanceKm': km,
      'driveMins': mins,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final placesList = widget.places.values.toList();
    final noPlaces = placesList.isEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isEdit ? 'Edit item' : 'Add to itinerary',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.inputFill(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 18, color: Color(0xFF64748B)),
                  const SizedBox(width: 10),
                  const Text('Day', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 10),
                  DropdownButton<int>(
                    value: _dayNo,
                    underline: const SizedBox(),
                    isDense: true,
                    items: List.generate(30, (i) => i + 1)
                        .map((d) => DropdownMenuItem(value: d, child: Text('Day $d')))
                        .toList(),
                    onChanged: (v) => setState(() => _dayNo = v ?? _dayNo),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (noPlaces)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.inputFill(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: _showAddPlace
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.add_location_alt, size: 18, color: Color(0xFF2563EB)),
                              const SizedBox(width: 6),
                              Text(
                                'Add a place',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(Icons.close, size: 18, color: AppColors.textMuted(context)),
                                onPressed: () => setState(() => _showAddPlace = false),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _placeField(_placeNameC, 'Place name *'),
                          const SizedBox(height: 8),
                          _placeField(_placeAddrC, 'Address (optional)'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _placeCategory,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.inputFill(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            items: _categories
                                .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) => setState(() => _placeCategory = v ?? _placeCategory),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 42,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _placeSaving ? null : _savePlace,
                              child: _placeSaving
                                  ? const SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Save place & select', style: TextStyle(fontSize: 13)),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Icon(Icons.place_outlined, size: 36, color: AppColors.textMuted(context)),
                          const SizedBox(height: 8),
                          Text(
                            'No places added yet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add a place first, then select it for your itinerary.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => setState(() => _showAddPlace = true),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add place here', style: TextStyle(fontSize: 13)),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  context.go('/trips/${widget.tripId}/places');
                                },
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Go to Places', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ],
                      ),
              )
            else ...[
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Text(
                    'Select places',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  if (_selectedPlaceIds.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_selectedPlaceIds.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: placesList.map((p) {
                  final pid = (p['id'] as num).toInt();
                  final sel = _selectedPlaceIds.contains(pid);
                  return ChoiceChip(
                    label: Text(
                      p['name']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: sel ? Colors.white : AppColors.textPrimary(context),
                      ),
                    ),
                    selected: sel,
                    selectedColor: const Color(0xFF2563EB),
                    onSelected: (_) => _togglePlace(p),
                    avatar: sel
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : const Icon(Icons.place_outlined, size: 14),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            _field(_titleC, 'Title *', Icons.title),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _field(_kmC, 'Distance KM', Icons.route, num: true),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(_minsC, 'Drive mins', Icons.schedule, num: true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(_stayC, 'Stay notes', Icons.hotel_outlined, maxLines: 2),
            const SizedBox(height: 10),
            _field(_foodC, 'Food notes', Icons.restaurant_outlined, maxLines: 2),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: noPlaces ? null : _submit,
                icon: Icon(isEdit ? Icons.check : Icons.add, size: 18),
                label: Text(isEdit ? 'Save changes' : 'Add item'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {int maxLines = 1, bool num = false}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: num ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: AppColors.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _placeField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
