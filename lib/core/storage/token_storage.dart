import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _access = 'tm_access';
  static const _refresh = 'tm_refresh';
  final _store = const FlutterSecureStorage();

  Future<void> save(String access, String refresh) async {
    await _store.write(key: _access, value: access);
    await _store.write(key: _refresh, value: refresh);
  }

  Future<String?> access() => _store.read(key: _access);
  Future<String?> refresh() => _store.read(key: _refresh);

  Future<void> clear() async {
    await _store.delete(key: _access);
    await _store.delete(key: _refresh);
  }
}
