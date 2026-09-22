import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/data/trip_status.dart';

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
  String get route => TripStatus.route(trip);
  String get kmLabel => TripStatus.kmLabel(trip);
  String get dateLabel => TripStatus.dateLabel(trip);
  int get daysCount => TripStatus.daysCount(trip);

  String get daysLabel {
    final d = daysCount;
    return d > 0 ? '$d Days' : '–';
  }
}

class DashboardData {
  final Map<String, dynamic> user;
  final List<TripSummary> trips;
  DashboardData({required this.user, required this.trips});
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

    final status = TripStatus.statusLabel(t);
    return TripSummary(
      trip: t,
      members: members,
      places: places,
      itineraryItems: itin,
      progress: TripStatus.progress(
        status: t['status']?.toString() ?? '',
        places: places,
        itineraryItems: itin,
        members: members,
      ),
      statusLabel: status,
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
