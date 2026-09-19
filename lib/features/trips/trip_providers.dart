import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;

final tripsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioClientProvider).dio;
  final res = await dio.get('/api/trips/mine');
  final List list = res.data['data'] as List;
  return list.map((e) => Map<String, dynamic>.from(e)).toList();
});
