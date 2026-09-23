import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/data/refresh.dart';
import '../../core/network/api_error.dart';

const _stopPalette = [
  Color(0xFF2563EB),
  Color(0xFF8B5CF6),
  Color(0xFFF59E0B),
  Color(0xFF06B6D4),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

/// Full-screen interactive trip map: OSM tiles, blue route polyline,
/// colorful stop pins, floating controls and a draggable route card.
class MapScreen extends ConsumerStatefulWidget {
  final String tripId;
  const MapScreen({super.key, required this.tripId});

  @override
  ConsumerState<MapScreen> createState() => _State();
}

class _State extends ConsumerState<MapScreen> {
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  Map<String, dynamic>? _trip;
  List<Map<String, dynamic>> _places = [];
  List<LatLng> _route = [];
  LatLng? _startPt;
  LatLng? _destPt;
  LatLng? _myLoc;
  double? _distKm;
  double? _durHrs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MapScreen old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) {
      // Trip switched: show loader while new data loads.
      setState(() => _loading = true);
      _load();
    }
  }

  @override
  void dispose() {
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.get('/api/trips/${widget.tripId}/places');
      final List list = res.data['data'] as List;
      try {
        final t = await dio.get('/api/trips/${widget.tripId}');
        final d = Map<String, dynamic>.from(t.data['data'] as Map);
        _trip = d;
        _startPt = _validPt(d['startLat'], d['startLng']);
        _destPt = _validPt(d['destLat'], d['destLng']);
        final km = d['totalKm'];
        if (km != null) _distKm = (km as num).toDouble();
      } catch (_) {}
      // Labeled points: start + places + dest, each with a display name.
      final labeled = <MapEntry<String, LatLng>>[];
      final startName = (_trip?['startName']?.toString() ?? '').trim();
      if (_startPt != null) {
        labeled.add(MapEntry(startName.isNotEmpty ? startName : 'Start', _startPt!));
      }
      for (final e in list) {
        final p = Map<String, dynamic>.from(e['place']);
        final pt = _validPt(p['latitude'], p['longitude']);
        if (pt != null) {
          final n = (p['name']?.toString() ?? '').trim();
          labeled.add(MapEntry(n.isNotEmpty ? n : 'Stop', pt));
        }
      }
      final destName = (_trip?['destName']?.toString() ?? '').trim();
      if (_destPt != null) {
        labeled.add(MapEntry(destName.isNotEmpty ? destName : 'Destination', _destPt!));
      }
      // Drop consecutive duplicates. Jump legs (>3000 km, i.e. wrong pins)
      // are excluded ONLY when the chain exceeds the routing provider's
      // 6,000 km limit — legit long trips (Delhi→London) stay untouched.
      const dist = Distance();
      final deduped = <LatLng>[];
      for (final e in labeled) {
        if (deduped.isEmpty ||
            (deduped.last.latitude - e.value.latitude).abs() > 1e-6 ||
            (deduped.last.longitude - e.value.longitude).abs() > 1e-6) {
          deduped.add(e.value);
        }
      }
      double chainM = 0;
      for (var i = 1; i < deduped.length; i++) {
        chainM += dist.as(LengthUnit.Meter, deduped[i - 1], deduped[i]);
      }
      final pts = <LatLng>[];
      final skipped = <String>[];
      if (chainM > 6000000) {
        for (var i = 0; i < labeled.length; i++) {
          final e = labeled[i];
          if (pts.isNotEmpty) {
            final last = pts.last;
            if ((last.latitude - e.value.latitude).abs() <= 1e-6 &&
                (last.longitude - e.value.longitude).abs() <= 1e-6) {
              continue;
            }
            final legKm = dist.as(LengthUnit.Kilometer, last, e.value);
            if (legKm > 3000) {
              skipped.add('${e.key} (~${legKm.round()} km away)');
              continue;
            }
          }
          pts.add(e.value);
        }
      } else {
        pts.addAll(deduped);
      }
      List<LatLng> route = List.from(pts);
      if (pts.length >= 2) {
        try {
          final r = await dio.post('/api/route', data: {
            'coordinates':
                pts.map((p) => [p.longitude, p.latitude]).toList(),
          });
          final feature = r.data['data']['features'][0];
          final coords = feature['geometry']['coordinates'] as List;
          route = coords
              .map((c) =>
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          final summary = feature['properties']['summary'];
          if (summary != null) {
            _distKm = (summary['distance'] as num).toDouble() / 1000;
            _durHrs = (summary['duration'] as num).toDouble() / 3600;
          }
        } catch (_) {
          // ORS key missing -> straight lines + estimated stats.
        }
      }
      if (_distKm == null && route.length >= 2) {
        double km = 0;
        for (var i = 1; i < route.length; i++) {
          km += dist.as(LengthUnit.Kilometer, route[i - 1], route[i]);
        }
        _distKm = km;
      }
      _durHrs ??= _distKm != null ? _distKm! / 55 : null;
      if (!mounted) return;
      setState(() {
        _places = list.map((e) => Map<String, dynamic>.from(e)).toList();
        _route = route;
        _loading = false;
      });
      _fitBounds();
      if (skipped.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${skipped.join(', ')} too far for driving directions — excluded from route.'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Parses a coordinate pair, rejecting null/non-finite values that would
  /// poison the map camera (Infinity/NaN crashes, invisible markers).
  LatLng? _validPt(dynamic lat, dynamic lng) {
    final a = (lat as num?)?.toDouble();
    final b = (lng as num?)?.toDouble();
    if (a == null || b == null || !a.isFinite || !b.isFinite) return null;
    if (a < -90 || a > 90 || b < -180 || b > 180) return null;
    return LatLng(a, b);
  }

  void _fitBounds() {
    if (_route.isEmpty) return;
    try {
      if (_route.length == 1) {
        _map.move(_route.first, 13);
        return;
      }
      final bounds = LatLngBounds.fromPoints(_route);
      final tiny = (bounds.north - bounds.south).abs() < 1e-6 &&
          (bounds.east - bounds.west).abs() < 1e-6;
      if (tiny) {
        // Degenerate bounds -> fitCamera yields infinite zoom.
        _map.move(bounds.center, 13);
        return;
      }
      _map.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
              top: 120, bottom: 300, left: 40, right: 40),
        ),
      );
    } catch (_) {}
  }

  String get _title {
    final s = _trip?['startName']?.toString();
    final d = _trip?['destName']?.toString();
    if (s != null && d != null && s.isNotEmpty && d.isNotEmpty) {
      return '$s → $d';
    }
    return _trip?['tripName']?.toString() ?? 'Trip Route';
  }

  String get _distLabel =>
      _distKm == null ? '–' : '${_distKm!.round()} KM';

  String get _durLabel {
    if (_durHrs == null) return '–';
    final totalMin = (_durHrs! * 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (m == 0) return '$h Hours';
    return '${h}h ${m}m';
  }

  Future<void> _vote(int placeId, String vote) async {
    final dio = ref.read(dioClientProvider).dio;
    await dio.post('/api/places/$placeId/vote', data: {'vote': vote});
    bumpData(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Voted $vote')));
  }

  Future<void> _goMine() async {
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
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLoc = me);
      _map.move(me, 13);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  void _zoom(double delta) {
    try {
      final cam = _map.camera;
      _map.move(cam.center, (cam.zoom + delta).clamp(2.0, 18.0));
    } catch (_) {}
  }

  void _openPlace(Map<String, dynamic> p) {
    showModalBottomSheet(
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (p['name'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              (p['address'] ?? '').toString(),
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    _vote(p['id'], 'VISIT');
                    Navigator.pop(context);
                  },
                  child: const Text('👍 Want To Visit'),
                ),
                OutlinedButton(
                  onPressed: () {
                    _vote(p['id'], 'SKIP');
                    Navigator.pop(context);
                  },
                  child: const Text('👎 Skip'),
                ),
                OutlinedButton(
                  onPressed: () {
                    _vote(p['id'], 'MAYBE');
                    Navigator.pop(context);
                  },
                  child: const Text('🤔 Maybe'),
                ),
              ],
            ),
            TextButton(
              onPressed: () => context.go(
                  '/trips/${widget.tripId}/places/${p['id']}'),
              child: const Text('Open details'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Subscriptions belong here: ref.listen asserts debugDoingBuild,
    // so it crashes in initState. Fires only on actual changes.
    ref.listen(dataVersionProvider, (_, _) => _load());
    final center =
        _route.isNotEmpty ? _route.first : const LatLng(19.0760, 72.8777);
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(initialCenter: center, initialZoom: 6),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              if (_route.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _route,
                    color: const Color(0xFF2563EB),
                    strokeWidth: 5,
                  ),
                ]),
              MarkerLayer(markers: _markers()),
            ],
          ),
          if (_loading)
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
          // Top floating bar.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _CircleBtn(
                    icon: Icons.arrow_back,
                    onTap: () => context.go('/home'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.refresh,
                    onTap: _load,
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.list,
                    onTap: () =>
                        context.go('/trips/${widget.tripId}/places'),
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.chat_bubble_outline,
                    onTap: () =>
                        context.go('/trips/${widget.tripId}/chat'),
                  ),
                ],
              ),
            ),
          ),
          // Floating map controls.
          Positioned(
            right: 12,
            bottom: 290,
            child: Column(
              children: [
                _CircleBtn(icon: Icons.my_location, onTap: _goMine),
                const SizedBox(height: 8),
                _CircleBtn(icon: Icons.add, onTap: () => _zoom(1)),
                const SizedBox(height: 8),
                _CircleBtn(icon: Icons.remove, onTap: () => _zoom(-1)),
              ],
            ),
          ),
          // Draggable route card.
          DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: 0.3,
            minChildSize: 0.16,
            maxChildSize: 0.7,
            snap: true,
            builder: (_, scroll) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 20,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: ListView(
                controller: scroll,
                padding:
                    const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Selected Route',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _RouteStat(
                        icon: Icons.route,
                        value: _distLabel,
                        label: 'Distance',
                      ),
                      _RouteStat(
                        icon: Icons.schedule,
                        value: _durLabel,
                        label: 'Duration',
                      ),
                      _RouteStat(
                        icon: Icons.place_outlined,
                        value: '${_places.length}',
                        label: 'Places',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_distKm == null && !_loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Pin start, destination & places to see distance & duration',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => context.go(
                          '/trips/${widget.tripId}/itinerary'),
                      child: const Text('View Full Itinerary'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceAround,
                    children: [
                      _SheetTab(
                        icon: Icons.place_outlined,
                        label: 'Places',
                        active: false,
                        onTap: () => context.go(
                            '/trips/${widget.tripId}/places'),
                      ),
                      _SheetTab(
                        icon: Icons.timeline_outlined,
                        label: 'Itinerary',
                        active: false,
                        onTap: () => context.go(
                            '/trips/${widget.tripId}/itinerary'),
                      ),
                      _SheetTab(
                        icon: Icons.group_outlined,
                        label: 'People',
                        active: false,
                        onTap: () => context.go(
                            '/trips/${widget.tripId}/members'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _markers() {
    final markers = <Marker>[
      if (_startPt != null)
        Marker(
          point: _startPt!,
          width: 46,
          height: 46,
          child: const _PinBadge(
            color: Color(0xFF10B981),
            child: Icon(Icons.flag, color: Colors.white, size: 22),
          ),
        ),
    ];
    for (var i = 0; i < _places.length; i++) {
      final p = _places[i];
      final ll =
          _validPt(p['place']['latitude'], p['place']['longitude']);
      if (ll == null) continue;
      final color = _stopPalette[i % _stopPalette.length];
      markers.add(
        Marker(
          point: ll,
          width: 46,
          height: 46,
          child: GestureDetector(
            onTap: () => _openPlace(
                Map<String, dynamic>.from(p['place'])),
            child: _PinBadge(
              color: color,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_destPt != null) {
      markers.add(
        Marker(
          point: _destPt!,
          width: 46,
          height: 46,
          child: const _PinBadge(
            color: Color(0xFFF43F5E),
            child: Icon(Icons.location_on,
                color: Colors.white, size: 22),
          ),
        ),
      );
    }
    if (_myLoc != null) {
      markers.add(
        Marker(
          point: _myLoc!,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 8),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }
}

class _SheetTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SheetTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF2563EB).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: active
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinBadge extends StatelessWidget {
  final Color color;
  final Widget child;
  const _PinBadge({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 8),
        ],
      ),
      child: Center(child: child),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: const Color(0xFF0F172A), size: 22),
        ),
      ),
    );
  }
}

class _RouteStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _RouteStat(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF2563EB), size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
