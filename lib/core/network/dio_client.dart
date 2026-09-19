import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../storage/token_storage.dart';

/// Dio with JWT attach + single-flight refresh on 401/403.
/// Backend answers 401 for bad sessions and 403 for forbidden; both trigger
/// one refresh attempt. Concurrent 401s share a single refresh call —
/// without this, token rotation would revoke all but the first attempt and
/// kill the session. If refresh fails, tokens are cleared and [onAuthLost]
/// fires so the app can return to login.
class DioClient {
  final Dio dio;
  final TokenStorage tokens;
  void Function()? onAuthLost;

  /// In-flight refresh shared by concurrent 401s. Never awaited twice.
  Future<Map<String, dynamic>>? _refreshing;

  DioClient(this.tokens)
      : dio = Dio(BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) async {
        final a = await tokens.access();
        if (a != null) o.headers['Authorization'] = 'Bearer $a';
        h.next(o);
      },
      onError: (e, h) async {
        final code = e.response?.statusCode;
        if ((code == 401 || code == 403) &&
            e.requestOptions.extra['retried'] != true) {
          try {
            final data = await (_refreshing ??= _doRefresh());
            e.requestOptions.headers['Authorization'] =
                'Bearer ${data['accessToken']}';
            e.requestOptions.extra['retried'] = true;
            final retry = await dio.fetch(e.requestOptions);
            return h.resolve(retry);
          } catch (_) {
            await tokens.clear();
            onAuthLost?.call();
          } finally {
            _refreshing = null;
          }
        }
        h.next(e);
      },
    ));
  }

  Future<Map<String, dynamic>> _doRefresh() async {
    final r = await tokens.refresh();
    if (r == null) throw Exception('no refresh token');
    final res = await Dio(BaseOptions(baseUrl: ApiConstants.baseUrl))
        .post(ApiConstants.refresh, data: {'refreshToken': r});
    final data = Map<String, dynamic>.from(res.data['data']);
    await tokens.save(data['accessToken'], data['refreshToken']);
    return data;
  }
}
