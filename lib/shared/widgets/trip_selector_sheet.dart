import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../features/auth/presentation/auth_provider.dart' show dioClientProvider;

class TripDropdown extends ConsumerStatefulWidget {
  final String tripId;
  const TripDropdown({super.key, required this.tripId});

  @override
  ConsumerState<TripDropdown> createState() => _TripDropdownState();
}

class _TripDropdownState extends ConsumerState<TripDropdown> {
  String _tripName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TripDropdown old) {
    super.didUpdateWidget(old);
    if (old.tripId != widget.tripId) _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.get('/api/trips/${widget.tripId}');
      if (!mounted) return;
      final body = res.data;
      final data = body is Map ? (body['data'] ?? body) : body;
      final name = (data is Map ? data['tripName'] : null) ?? 'Trip';
      setState(() {
        _tripName = name.toString();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TripDropdown] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Flexible(
                  child: Text(
                    _tripName.isNotEmpty ? _tripName : 'Trip',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down,
                  size: 20, color: AppColors.textSecondary(context)),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet() async {
    final dio = ref.read(dioClientProvider).dio;
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TripSearchSheet(
        currentTripId: widget.tripId,
        dio: dio,
      ),
    );
    if (selectedId == null || selectedId == widget.tripId || !mounted) return;
    final loc = GoRouterState.of(context).uri.toString();
    String tab = 'map';
    if (loc.contains('/places')) {
      tab = 'places';
    } else if (loc.contains('/expenses')) {
      tab = 'expenses';
    } else if (loc.contains('/itinerary')) {
      tab = 'itinerary';
    } else if (loc.contains('/members')) {
      tab = 'members';
    }
    context.go('/trips/$selectedId/$tab');
  }
}

class _TripSearchSheet extends StatefulWidget {
  final String currentTripId;
  final dynamic dio;
  const _TripSearchSheet({required this.currentTripId, required this.dio});

  @override
  State<_TripSearchSheet> createState() => _TripSearchSheetState();
}

class _TripSearchSheetState extends State<_TripSearchSheet> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.dio.get('/api/trips/mine');
      if (!mounted) return;
      final body = res.data;
      final list = body is Map ? (body['data'] ?? []) : body;
      setState(() {
        _trips = (list as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TripSelector] $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _trips;
    return _trips.where((t) {
      final hay =
          '${t['tripName'] ?? ''} ${t['startName'] ?? ''} ${t['destName'] ?? ''}'
              .toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  void _select(String id) {
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search trips...',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.inputFill(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 36,
                                  color: AppColors.textSecondary(context)),
                              const SizedBox(height: 8),
                              Text('Failed to load trips',
                                  style: TextStyle(
                                      color:
                                          AppColors.textSecondary(context),
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _loading = true;
                                    _error = null;
                                  });
                                  _load();
                                },
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _filtered.isEmpty
                          ? Center(
                              child: Text(
                                _query.isEmpty
                                    ? 'No trips yet'
                                    : 'No trips found',
                                style: TextStyle(
                                    color:
                                        AppColors.textSecondary(context)),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final t = _filtered[i];
                                final id = t['id'].toString();
                                final name =
                                    (t['tripName'] ?? 'Trip').toString();
                                final start =
                                    (t['startName'] ?? '').toString();
                                final dest =
                                    (t['destName'] ?? '').toString();
                                final sel = id == widget.currentTripId;
                                final route =
                                    start.isNotEmpty && dest.isNotEmpty
                                        ? '$start -> $dest'
                                        : '';

                                return Material(
                                  color: sel
                                      ? AppColors.blue
                                          .withValues(alpha: 0.08)
                                      : AppColors.card(context),
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => _select(id),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                          color: sel
                                              ? AppColors.blue
                                              : AppColors.cardBorder(
                                                  context),
                                          width: sel ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: sel
                                                  ? AppColors.blue
                                                      .withValues(
                                                          alpha: 0.12)
                                                  : AppColors.inputFill(
                                                      context),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      10),
                                            ),
                                            child: Icon(
                                              Icons.flight_takeoff,
                                              size: 20,
                                              color: sel
                                                  ? AppColors.blue
                                                  : AppColors
                                                      .textSecondary(
                                                          context),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(name,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 15,
                                                      color: sel
                                                          ? AppColors.blue
                                                          : AppColors
                                                              .textPrimary(
                                                                  context),
                                                    )),
                                                if (route.isNotEmpty)
                                                  Text(route,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: AppColors
                                                            .textSecondary(
                                                                context),
                                                      )),
                                              ],
                                            ),
                                          ),
                                          if (sel)
                                            const Icon(
                                                Icons.check_circle,
                                                color: AppColors.blue,
                                                size: 20)
                                          else
                                            Icon(Icons.chevron_right,
                                                size: 20,
                                                color: AppColors
                                                    .textMuted(context)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }
}
