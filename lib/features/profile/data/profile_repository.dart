import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_provider.dart' show dioClientProvider;
import 'package:tripmate_app/core/constants/api_constants.dart';

final profileRepositoryProvider =
    Provider((ref) => ProfileRepository(ref.watch(dioClientProvider).dio));

class ProfileRepository {
  final Dio _dio;
  ProfileRepository(this._dio);

  Future<Map<String, dynamic>> me() async {
    final res = await _dio.get('/api/users/me');
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> stats() async {
    final res = await _dio.get('/api/users/me/stats');
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<List<Map<String, dynamic>>> myTrips() async {
    final res = await _dio.get('/api/trips/mine');
    return ((res.data['data'] as List))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<int> memberCount(int tripId) async {
    try {
      final res = await _dio.get('/api/trips/$tripId/members');
      return (res.data['data'] as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Places across my trips where I voted VISIT (= saved).
  Future<List<Map<String, dynamic>>> savedPlaces(
      List<Map<String, dynamic>> trips) async {
    final out = <Map<String, dynamic>>[];
    await Future.wait(trips.map((t) async {
      try {
        final res = await _dio.get('/api/trips/${t['id']}/places');
        for (final e in (res.data['data'] as List)) {
          final m = Map<String, dynamic>.from(e);
          if (m['myVote'] == 'VISIT') {
            out.add(Map<String, dynamic>.from(m['place']));
          }
        }
      } catch (_) {}
    }));
    return out;
  }

  Future<Map<String, dynamic>> update(Map<String, dynamic> fields) async {
    final res = await _dio.patch('/api/users/me', data: fields);
    return Map<String, dynamic>.from(res.data['data']);
  }

  /// Uploads a photo, returns an absolute URL for profileImage.
  Future<String> uploadAvatar(String path, String filename) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    final res = await _dio.post('/api/files/upload', data: form);
    var url = res.data['data']['url'].toString();
    if (url.startsWith('/')) url = ApiConstants.baseUrl + url;
    return url;
  }
}

class ProfileData {
  final Map<String, dynamic> user;
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> trips;
  final Map<int, int> memberCounts;
  final List<Map<String, dynamic>> saved;
  ProfileData({
    required this.user,
    required this.stats,
    required this.trips,
    required this.memberCounts,
    required this.saved,
  });
}

final profileProvider = FutureProvider<ProfileData>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  final user = await repo.me();
  final results = await Future.wait([
    repo.stats(),
    repo.myTrips(),
  ]);
  final stats = results[0] as Map<String, dynamic>;
  final trips = results[1] as List<Map<String, dynamic>>;
  final counts = <int, int>{};
  await Future.wait(trips.map((t) async {
    counts[(t['id'] as num).toInt()] =
        await repo.memberCount((t['id'] as num).toInt());
  }));
  final saved = await repo.savedPlaces(trips);
  return ProfileData(
    user: user,
    stats: stats,
    trips: trips,
    memberCounts: counts,
    saved: saved,
  );
});
