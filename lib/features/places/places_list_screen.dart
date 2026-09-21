import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/not_member_card.dart';
import '../../shared/widgets/top_bar.dart' show DarkModeToggle, NotificationsButton;
import '../../shared/widgets/trip_selector_sheet.dart';
import '../../core/data/refresh.dart';
import 'presentation/widgets/place_gallery.dart';

const _fallbacks = [
  'assets/images/trip_hero.jpg',
  'assets/images/trip_goa.jpg',
  'assets/images/splash_road.jpg',
  'assets/images/auth_travel.jpg',
];

const _categories = [
  'Nature',
  'Waterfall',
  'Food',
  'Stay',
  'Viewpoint',
  'Temple',
  'Adventure',
  'Other',
];

/// Airbnb-style places discovery: search, vote tabs, photo cards, add place.
class PlacesListScreen extends ConsumerStatefulWidget {
  final String tripId;
  const PlacesListScreen({super.key, required this.tripId});

  @override
  ConsumerState<PlacesListScreen> createState() => _State();
}

class _State extends ConsumerState<PlacesListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  Map<String, dynamic>? _trip;
  String _query = '';
  bool _loading = true;
  bool _error = false;
  bool _notMember = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _search.addListener(() => setState(() => _query = _search.text.trim()));
    _load();
  }

  @override
  void didUpdateWidget(covariant PlacesListScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/${widget.tripId}/places'),
        dio.get('/api/trips/${widget.tripId}'),
      ]);
      if (!mounted) return;
      setState(() {
        _all = ((res[0].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _trip = Map<String, dynamic>.from(res[1].data['data'] as Map);
        _loading = false;
        _error = false;
      });
    } catch (e) {
      if (mounted) {
        if (isNotMemberError(e)) {
          setState(() {
            _loading = false;
            _notMember = true;
          });
        } else {
          setState(() {
            _loading = false;
            _error = true;
          });
        }
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final tab = _tabs.index;
    var list = _all.where((e) {
      final my = e['myVote']?.toString();
      if (tab == 1 && my != 'VISIT') return false;
      if (tab == 2 && my != 'MAYBE') return false;
      if (tab == 3 && my != 'SKIP') return false;
      if (_query.isEmpty) return true;
      final p = Map<String, dynamic>.from(e['place']);
      final hay =
          '${p['name'] ?? ''} ${p['address'] ?? ''}'.toLowerCase();
      return hay.contains(_query.toLowerCase());
    }).toList();
    list.sort((a, b) {
      final va = (Map<String, dynamic>.from(a['votes'] ?? {})['VISIT'] ?? 0);
      final vb = (Map<String, dynamic>.from(b['votes'] ?? {})['VISIT'] ?? 0);
      return (vb as num).compareTo(va as num);
    });
    return list;
  }

  String? _distanceLabel(Map<String, dynamic> p) {
    final lat = (p['latitude'] as num?)?.toDouble();
    final lng = (p['longitude'] as num?)?.toDouble();
    final slat = (_trip?['startLat'] as num?)?.toDouble();
    final slng = (_trip?['startLng'] as num?)?.toDouble();
    if (lat == null || lng == null || slat == null || slng == null) {
      return null;
    }
    final km = const Distance()
        .as(LengthUnit.Kilometer, LatLng(slat, slng), LatLng(lat, lng));
    final from = (_trip?['startName']?.toString() ?? '').isNotEmpty
        ? _trip!['startName'].toString()
        : 'route';
    return '${km.round()} KM from $from';
  }

  /// AI flow: quota -> count -> suggest -> results screen.
  Future<void> _suggest() async {
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
            content: Text(
                'Free suggestions used (5/5 for this trip).')),
        );
        return;
      }
      final count = await showModalBottomSheet<int>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '✨ AI must-visit picks',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                '$remaining of 5 suggestion batches left',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              for (final c in [3, 5, 8])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, c),
                      child: Text('Suggest $c places'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      if (count == null || !mounted) return;
      final res = await dio.post(
        '/api/trips/${widget.tripId}/places/ai/suggest',
        data: {'count': count},
      );
      final sid = res.data['data']['suggestionId'].toString();
      if (!mounted) return;
      context.go('/trips/${widget.tripId}/places/ai/$sid');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  void _addPlace() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddPlaceSheet(
        onAdded: () {
          Navigator.pop(context);
          _load();
        },
        tripId: widget.tripId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) => _load());
    ref.listen(tabRefreshRequestProvider, (_, req) {
      if (req != null && req.tab == 1) _load();
    });
    final items = _filtered;
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: TripDropdown(tripId: widget.tripId),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/trips/${widget.tripId}/map'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI suggestions',
            onPressed: _suggest,
          ),
          const DarkModeToggle(),
          const NotificationsButton(),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Going'),
            Tab(text: 'Maybe'),
            Tab(text: 'Skipped'),
          ],
        ),
      ),
      floatingActionButton: _notMember
          ? null
          : FloatingActionButton.extended(
        onPressed: _addPlace,
        icon: const Icon(Icons.add),
        label: const Text('Add Place'),
      ),
      body: _notMember
          ? NotMemberCard(tripId: widget.tripId, onRetry: _load)
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search places on route',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _search.clear(),
                      ),
                filled: true,
                fillColor: AppColors.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                          child: _error && _query.isEmpty
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text("Couldn't load places"),
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              )
                            : Text(
                                _query.isEmpty
                                    ? 'No places here yet'
                                    : 'No matches for "$_query"',
                                style: const TextStyle(
                                    color: Color(0xFF64748B)),
                              ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: items.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _PlaceCard(
                              entry: items[i],
                              image: _fallbacks[i % _fallbacks.length],
                              distance: _distanceLabel(
                                Map<String, dynamic>.from(
                                    items[i]['place']),
                              ),
                              tripId: widget.tripId,
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String image;
  final String? distance;
  final String tripId;
  const _PlaceCard({
    required this.entry,
    required this.image,
    required this.distance,
    required this.tripId,
  });

  @override
  Widget build(BuildContext context) {
    final p = Map<String, dynamic>.from(entry['place']);
    final votes = Map<String, dynamic>.from(entry['votes'] ?? {});
    final my = entry['myVote']?.toString();
    final img = (p['imageUrl'] as String?) ?? '';
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              PlaceGallery(
                placeId: (p['id'] as num?)?.toInt(),
                imageUrl: img.isNotEmpty ? img : null,
                fallback: image,
                height: 180,
              ),
              if ((p['category']?.toString() ?? '').isNotEmpty)
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
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
                ),
              if ((p['remarks']?.toString() ?? '') == 'ai-generated')
                Positioned(
                  left: 12,
                  top: (p['category']?.toString() ?? '').isNotEmpty
                      ? 46
                      : 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🤖 AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (my != null)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      my == 'VISIT'
                          ? '👍 Going'
                          : my == 'SKIP'
                              ? '👎 Skipped'
                              : '🤔 Maybe',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (p['name'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                if ((p['address']?.toString() ?? '').isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p['address'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (distance != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.route,
                          size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        distance!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _VotePill(
                        text: '👍 ${votes['VISIT'] ?? 0} Going'),
                    _VotePill(
                        text: '🤔 ${votes['MAYBE'] ?? 0} Maybe'),
                    _VotePill(
                        text: '👎 ${votes['SKIP'] ?? 0} Skipped'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => context.go(
                        '/trips/$tripId/places/${p['id']}'),
                    child: const Text('View Details'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VotePill extends StatelessWidget {
  final String text;
  const _VotePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.inputFill(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary(context),
        ),
      ),
    );
  }
}

class _AddPlaceSheet extends ConsumerStatefulWidget {
  final String tripId;
  final VoidCallback onAdded;
  const _AddPlaceSheet({required this.tripId, required this.onAdded});

  @override
  ConsumerState<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends ConsumerState<_AddPlaceSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  String _category = _categories.first;
  double? _lat;
  double? _lng;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _useCurrent() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      await dio.post('/api/trips/${widget.tripId}/places', data: {
        'name': _name.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'category': _category,
        if (_lat != null) 'latitude': _lat,
        if (_lng != null) 'longitude': _lng,
      });
      bumpData(ref);
      widget.onAdded();
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _form,
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
              const Text(
                'Add Place',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  hintText: 'Place name (e.g. Jog Falls)',
                  filled: true,
                  fillColor: AppColors.inputFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter a place name'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                decoration: InputDecoration(
                  hintText: 'Location (e.g. Karnataka)',
                  filled: true,
                  fillColor: AppColors.inputFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.inputFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: _categories
                    .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _category = v ?? _category),
              ),
              TextButton.icon(
                onPressed: _useCurrent,
                icon: const Icon(Icons.gps_fixed, size: 18),
                label: Text(
                  _lat == null
                      ? 'Use current location for pin'
                      : 'Pinned: ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle:
                        const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Adding…' : 'Add Place'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
