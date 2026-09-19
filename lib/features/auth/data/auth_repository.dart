import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/token_storage.dart';

class AuthRepository {
  final Dio _dio;
  final _tokens = TokenStorage();
  AuthRepository(this._dio);

  Future<Map<String, dynamic>> _issue(Map<String, dynamic> body, String path) async {
    final res = await _dio.post(path, data: body);
    final data = Map<String, dynamic>.from(res.data['data']);
    await _tokens.save(data['accessToken'], data['refreshToken']);
    return data;
  }

  Future<Map<String, dynamic>> login(String email, String password) =>
      _issue({'email': email, 'password': password}, ApiConstants.login);

  Future<Map<String, dynamic>> register(String name, String email, String password) =>
      _issue({'name': name, 'email': email, 'password': password}, ApiConstants.register);

  Future<Map<String, dynamic>> loginWithGoogle(String idToken) =>
      _issue({'idToken': idToken}, ApiConstants.google);

  Future<void> logout() async {
    try {
      await _dio.post(ApiConstants.logout);
    } finally {
      await _tokens.clear();
    }
  }
}
