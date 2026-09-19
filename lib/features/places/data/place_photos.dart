import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_provider.dart' show dioClientProvider;

/// Real photo URLs for a place (Wikimedia Commons via backend).
/// Empty list = none found (UI falls back to local banners).
/// Family caches per place; errors degrade to empty, never throw.
final placePhotosProvider =
    FutureProvider.autoDispose.family<List<String>, int>(
        (ref, placeId) async {
  final dio = ref.watch(dioClientProvider).dio;
  try {
    final res = await dio.get('/api/places/$placeId/photos');
    final List list = res.data['data'] as List? ?? [];
    return list
        .map((e) =>
            (Map<String, dynamic>.from(e)['url'] ?? '').toString())
        .where((u) => u.isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
});
