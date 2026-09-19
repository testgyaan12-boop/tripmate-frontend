import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;

class TripSummary {
  final Map<String, dynamic> trip;
  final int members;
  final int places;
  final int itineraryItems;
  final double progress;
  final String statusLabel;

  TripSummary({
    required this.trip,
    required this.members,
    required this.places,
    required this.itineraryItems,
    required this.progress,
    required this.statusLabel,
  });

  int get id => trip['id'] as int;
  String get name => (trip['tripName'] ?? 'Trip').toString();
  String get route =>
      '${trip['startName'] ?? ''} → ${trip['destName'] ?? ''}';

  String get kmLabel {
    final km = trip['totalKm'];
    return km == null ? '–' : '${(km as num).round()} KM';
  }

  String get daysLabel {
    final d = trip['daysCount'];
    if (d != null) return '$d Days';
    final s = trip['startDate'];
    final e = trip['endDate'];
    if (s != null && e != null) {
      final days =
          DateTime.parse(e).difference(DateTime.parse(s)).inDays + 1;
      if (days > 0) return '$days Days';
    }
    return '–';
  }
}

class DashboardData {
  final Map<String, dynamic> user;
  final List<TripSummary> trips;
  DashboardData({required this.user, required this.trips});
}

String _statusOf(Map<String, dynamic> t) {
  if ((t['status'] ?? '') == 'FINALIZED') return 'Finalized';
  final now = DateTime.now();
  try {
    if (t['startDate'] != null &&
        DateTime.parse(t['startDate']).isAfter(now)) {
      return 'Upcoming';
    }
    if (t['endDate'] != null &&
        DateTime.parse(t['endDate']).isBefore(now)) {
      return 'Completed';
    }
  } catch (_) {}
  return 'Planning';
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final dio = ref.watch(dioClientProvider).dio;
  final meRes = await dio.get('/api/users/me');
  final tripsRes = await dio.get('/api/trips/mine');
  final List raw = tripsRes.data['data'] as List;

  final summaries = await Future.wait(raw.map((e) async {
    final t = Map<String, dynamic>.from(e);
    final id = t['id'];
    int members = 0, places = 0, itin = 0;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/$id/members'),
        dio.get('/api/trips/$id/places'),
        dio.get('/api/trips/$id/itinerary'),
      ]);
      members = (res[0].data['data'] as List).length;
      places = (res[1].data['data'] as List).length;
      itin = (res[2].data['data'] as List).length;
    } catch (_) {}
    double progress;
    if ((t['status'] ?? '') == 'FINALIZED') {
      progress = 1.0;
    } else {
      progress = 0.2 +
          (places > 0 ? 0.3 : 0) +
          (itin > 0 ? 0.3 : 0) +
          (members > 1 ? 0.2 : 0);
    }
    return TripSummary(
      trip: t,
      members: members,
      places: places,
      itineraryItems: itin,
      progress: progress.clamp(0.0, 1.0),
      statusLabel: _statusOf(t),
    );
  }));

  return DashboardData(
    user: Map<String, dynamic>.from(meRes.data['data']),
    trips: summaries,
  );
});

final unreadCountProvider = FutureProvider<int>((ref) async {
  final dio = ref.watch(dioClientProvider).dio;
  try {
    final res = await dio.get('/api/notifications');
    final List list = res.data['data'] as List;
    return list.where((n) => n['read'] == false).length;
  } catch (_) {
    return 0;
  }
});
