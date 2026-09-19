import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';

final tokenStorageProvider = Provider((_) => TokenStorage());
final dioClientProvider =
    Provider((ref) => DioClient(ref.watch(tokenStorageProvider)));
final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.watch(dioClientProvider).dio));

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<Map<String, dynamic>?>>(
        (ref) => AuthNotifier(ref.watch(authRepositoryProvider)));

class AuthNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>?>> {
  final AuthRepository _repo;
  AuthNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.login(email, password));
  }

  Future<void> register(String name, String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.register(name, email, password));
  }

  Future<void> loginWithGoogle(String idToken) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.loginWithGoogle(idToken));
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncValue.data(null);
  }
}
