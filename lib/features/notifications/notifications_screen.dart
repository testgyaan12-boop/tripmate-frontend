import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../dashboard/dashboard_providers.dart' show unreadCountProvider;

final notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioClientProvider).dio;
  final res = await dio.get('/api/notifications');
  final List list = res.data['data'] as List;
  return list.map((e) => Map<String, dynamic>.from(e)).toList();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markRead(WidgetRef ref, int id) async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      await dio.patch('/api/notifications/$id/read');
    } catch (_) {}
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadCountProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No notifications yet'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final n = list[i];
              final read = n['read'] == true;
              return Card(
                color: read ? null : const Color(0xFFEFF6FF),
                child: ListTile(
                  leading: Icon(
                    Icons.notifications,
                    color: read
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF2563EB),
                  ),
                  title: Text(
                    (n['title'] ?? 'Notification').toString(),
                    style: TextStyle(
                      fontWeight:
                          read ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text((n['body'] ?? '').toString()),
                  onTap: () => _markRead(ref, n['id'] as int),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
