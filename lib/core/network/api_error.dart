import 'package:dio/dio.dart';

/// Turns technical failures into human-readable messages.
/// Backend validation/business errors surface their `message` field
/// (e.g. "Free limit reached (2 trips). Premium required.") instead of
/// raw DioException dumps.
String apiErrorMessage(Object e,
    {String fallback = 'Something went wrong'}) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map &&
        data['message'] is String &&
        (data['message'] as String).isNotEmpty) {
      return data['message'] as String;
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Request timed out. Check your connection and retry.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Cannot reach the server. Is the backend running?';
      default:
        break;
    }
    if (e.response != null) {
      if (e.response!.statusCode == 403) {
        return 'Session expired. Please login again.';
      }
      return 'Request failed (${e.response!.statusCode}). Try again.';
    }
    return fallback;
  }
  return e.toString().replaceFirst('Exception: ', '');
}
