import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../dashboard/dashboard_providers.dart';
import '../../core/data/refresh.dart';
import '../../core/network/api_error.dart';
import '../auth/presentation/widgets/auth_text_field.dart';

/// Create or Edit Trip: name, start/destination (ORS autocomplete + current
/// location), travel date picker, day stepper. Pass [editTripId] to edit.
class CreateTripScreen extends ConsumerStatefulWidget {
  final String? editTripId;
  const CreateTripScreen({super.key, this.editTripId});
  @override
  ConsumerState<CreateTripScreen> createState() => _State();
}

class _GeoHit {
  final String label;
  final double lat;
  final double lng;
  _GeoHit({required this.label, required this.lat, required this.lng});
}

class _State extends ConsumerState<CreateTripScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _dest = TextEditingController();
  final _startFocus = FocusNode();
  final _destFocus = FocusNode();

  double? _startLat;
  double? _startLng;
  double? _destLat;
  double? _destLng;

  List<_GeoHit> _suggestions = [];
  String? _suggestFor;
  Timer? _debounce;
  bool _searching = false;

  late DateTime _startDate = DateTime.now().add(const Duration(days: 30));
  int _days = 5;
  bool _busy = false;
  bool get _isEdit => widget.editTripId != null;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _start.dispose();
    _dest.dispose();
    _startFocus.dispose();
    _destFocus.dispose();
    super.dispose();
  }

  DateTime get _endDate => _startDate.add(Duration(days: _days - 1));

  @override
  void initState() {
    super.initState();
    _startFocus.addListener(_onFocus);
    _destFocus.addListener(_onFocus);
    if (_isEdit) _loadTrip();
  }

  Future<void> _loadTrip() async {
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.get('/api/trips/${widget.editTripId}');
      if (!mounted) return;
      final t = res.data['data'];
      setState(() {
        _name.text = (t['tripName'] ?? '').toString();
        _start.text = (t['startName'] ?? '').toString();
        _dest.text = (t['destName'] ?? '').toString();
        if (t['startDate'] != null) {
          try { _startDate = DateTime.parse(t['startDate'].toString()); } catch (_) {}
        }
        if (t['endDate'] != null && t['startDate'] != null) {
          try {
            final end = DateTime.parse(t['endDate'].toString());
            _days = end.difference(_startDate).inDays + 1;
            if (_days < 1) _days = 5;
          } catch (_) {}
        } else if (t['daysCount'] != null) {
          _days = (t['daysCount'] as num).toInt();
        }
      });
    } catch (_) {}
  }
  String get _dateLabel => DateFormat('d MMMM yyyy').format(_startDate);
  String get _rangeLabel =>
      '${DateFormat('d MMM').format(_startDate)} – ${DateFormat('d MMM yyyy').format(_endDate)} · $_days Days';

  void _onChanged(String field, String value) {
    if (field == 'start') {
      _startLat = null;
      _startLng = null;
    } else {
      _destLat = null;
      _destLng = null;
    }
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _suggestFor = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search(field, value.trim());
    });
  }

  Future<void> _search(String field, String query) async {
    setState(() {
      _searching = true;
      _suggestFor = field;
    });
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.get('/api/geo/search',
          queryParameters: {'q': query});
      final features =
          (res.data['data']['features'] as List?) ?? [];
      final hits = features.take(4).map((f) {
        final coords = f['geometry']['coordinates'] as List;
        final props = Map<String, dynamic>.from(f['properties'] as Map);
        return _GeoHit(
          label: (props['label'] ??
                  props['name'] ??
                  props['display_name'] ??
                  query)
              .toString(),
          lng: (coords[0] as num).toDouble(),
          lat: (coords[1] as num).toDouble(),
        );
      }).toList();
      if (!mounted) return;
      final current =
          field == 'start' ? _start.text.trim() : _dest.text.trim();
      if (current != query) return;
      setState(() => _suggestions = hits);
    } catch (_) {
      // ORS key missing etc. -> manual entry still works.
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(_GeoHit hit) {
    setState(() {
      if (_suggestFor == 'start') {
        _start.text = hit.label;
        _startLat = hit.lat;
        _startLng = hit.lng;
        _startFocus.unfocus();
      } else {
        _dest.text = hit.label;
        _destLat = hit.lat;
        _destLng = hit.lng;
        _destFocus.unfocus();
      }
      _suggestions = [];
      _suggestFor = null;
    });
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
        _startLat = pos.latitude;
        _startLng = pos.longitude;
        _start.text = 'Current Location';
        _suggestions = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final data = {
        'tripName': _name.text.trim(),
        'startName': _start.text.trim(),
        if (_startLat != null) 'startLat': _startLat,
        if (_startLng != null) 'startLng': _startLng,
        'destName': _dest.text.trim(),
        if (_destLat != null) 'destLat': _destLat,
        if (_destLng != null) 'destLng': _destLng,
        'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
        'endDate': DateFormat('yyyy-MM-dd').format(_endDate),
        'daysCount': _days,
      };
      final res = _isEdit
          ? await dio.put('/api/trips/${widget.editTripId}', data: data)
          : await dio.post('/api/trips', data: data);
      final id = _isEdit ? widget.editTripId : res.data['data']['id'];
      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      bumpData(ref);
      context.go(_isEdit ? '/home' : '/trips/$id/map');
    } catch (e) {
      if (!mounted) return;
      final msg = apiErrorMessage(e);
      if (!_isEdit && msg.contains('Trip limit reached')) {
        _showUpgradeDialog(msg);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Free-limit paywall: Upgrade Now -> subscription screen.
  void _showUpgradeDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trip limit reached'),
        content: Text('$msg\n\nUpgrade to Pro for unlimited trips.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Maybe later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/subscription');
            },
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Trip' : 'Create New Trip'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                          ),
                        ),
                        child: const Icon(
                          Icons.route,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Plan your next road trip',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Label('Trip Name'),
                          const SizedBox(height: 6),
                          AuthTextField(
                            controller: _name,
                            hint: 'Mumbai to Ooty Road Trip',
                            icon: Icons.route_outlined,
                            validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Give your trip a name'
                                    : null,
                          ),
                          const SizedBox(height: 14),
                          const _Label('Starting Location'),
                          const SizedBox(height: 6),
                          AuthTextField(
                            controller: _start,
                            hint: 'Mumbai',
                            icon: Icons.my_location,
                            focusNode: _startFocus,
                            onChanged: (v) => _onChanged('start', v),
                            validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Enter a starting point'
                                    : null,
                          ),
                          _LocationExtras(
                            field: 'start',
                            suggestFor: _suggestFor,
                            suggestions: _suggestions,
                            searching: _searching,
                            onPick: _pick,
                            action: TextButton.icon(
                              onPressed: _useCurrent,
                              icon: const Icon(Icons.gps_fixed, size: 16),
                              label: const Text('Use current location'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const _Label('Destination'),
                          const SizedBox(height: 6),
                          AuthTextField(
                            controller: _dest,
                            hint: 'Ooty',
                            icon: Icons.location_on_outlined,
                            focusNode: _destFocus,
                            onChanged: (v) => _onChanged('dest', v),
                            validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Enter a destination'
                                    : null,
                          ),
                          _LocationExtras(
                            field: 'dest',
                            suggestFor: _suggestFor,
                            suggestions: _suggestions,
                            searching: _searching,
                            onPick: _pick,
                          ),
                          const SizedBox(height: 14),
                          const _Label('Travel Date'),
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 15),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_month_outlined,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _dateLabel,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          _rangeLabel,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.edit_calendar_outlined,
                                    color: Color(0xFF2563EB),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const _Label('Number of Days'),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: _days > 1
                                      ? () =>
                                          setState(() => _days--)
                                      : null,
                                  icon: const Icon(Icons.remove),
                                ),
                                Text(
                                  '$_days Days',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton.filledTonal(
                                  onPressed: _days < 30
                                      ? () =>
                                          setState(() => _days++)
                                      : null,
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: _busy ? null : _create,
                      child:
                          Text(_busy ? ( _isEdit ? 'Saving…' : 'Creating…') : ( _isEdit ? 'Save Changes' : 'Create Trip')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onFocus() {
    if (!_startFocus.hasFocus && !_destFocus.hasFocus) {
      setState(() {
        _suggestions = [];
        _suggestFor = null;
      });
    }
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF334155),
      ),
    );
  }
}

class _LocationExtras extends StatelessWidget {
  final String field;
  final String? suggestFor;
  final List<_GeoHit> suggestions;
  final bool searching;
  final void Function(_GeoHit) onPick;
  final Widget? action;

  const _LocationExtras({
    required this.field,
    required this.suggestFor,
    required this.suggestions,
    required this.searching,
    required this.onPick,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestFor != field) {
      return action ?? const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (searching)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ...suggestions.map(
          (h) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.location_on_outlined,
              color: Color(0xFF2563EB),
              size: 20,
            ),
            title: Text(h.label,
                style: const TextStyle(fontSize: 13)),
            onTap: () => onPick(h),
          ),
        ),
        action ?? const SizedBox.shrink(),
      ],
    );
  }
}
