import 'package:dio/dio.dart';

/// HTTP client for the exact expense module APIs.
class ExpenseService {
  final Dio dio;
  ExpenseService(this.dio);

  static List<Map<String, dynamic>> _list(dynamic v) =>
      ((v as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  /// Enriched expenses: splits, paidByName, splitCount, status.
  Future<List<Map<String, dynamic>>> list(String tripId) async {
    final r = await dio.get('/api/trips/$tripId/expenses');
    return _list(r.data['data']);
  }

  Future<Map<String, dynamic>> create(
          String tripId, Map<String, dynamic> body) async {
    final r =
        await dio.post('/api/trips/$tripId/expenses', data: body);
    return Map<String, dynamic>.from(r.data['data'] as Map);
  }

  Future<Map<String, dynamic>> update(
      String tripId, int id, Map<String, dynamic> body) async {
    final r =
        await dio.put('/api/trips/$tripId/expenses/$id', data: body);
    return Map<String, dynamic>.from(r.data['data'] as Map);
  }

  Future<void> remove(String tripId, int id) =>
      dio.delete('/api/trips/$tripId/expenses/$id');

  Future<Map<String, dynamic>> markSettled(
      String tripId, int id, bool settled) async {
    final r = await dio.patch('/api/trips/$tripId/expenses/$id/settle',
        data: {'settled': settled});
    return Map<String, dynamic>.from(r.data['data'] as Map);
  }

  /// Spec endpoint: totalSpent, youOwe, youReceive, settlements,
  /// members, payments.
  Future<Map<String, dynamic>> settlements(String tripId) async {
    final r = await dio.get('/api/trips/$tripId/settlements');
    return Map<String, dynamic>.from(r.data['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> recordPayment(
      String tripId, Map<String, dynamic> body) async {
    final r = await dio.post('/api/trips/$tripId/settlements/record',
        data: body);
    return Map<String, dynamic>.from(r.data['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> budget(String tripId) async {
    final r = await dio.get('/api/trips/$tripId/budget');
    return Map<String, dynamic>.from(r.data['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> saveBudget(
      String tripId, List<Map<String, dynamic>> items) async {
    final r = await dio.put('/api/trips/$tripId/budget',
        data: {'items': items});
    return Map<String, dynamic>.from(r.data['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> mySummary() async {
    final r = await dio.get('/api/users/me/expenses/summary');
    return Map<String, dynamic>.from(r.data['data'] as Map? ?? {});
  }

  Future<List<Map<String, dynamic>>> myTrips() async {
    final r = await dio.get('/api/trips/mine');
    return _list(r.data['data']);
  }

  /// Spec categories with emoji, label and icon data key.
  static const categories = [
    'FUEL',
    'FOOD',
    'STAY',
    'TICKETS',
    'SHOPPING',
    'OTHER',
  ];

  static String labelFor(String category) {
    switch (category) {
      case 'MISC':
        return 'Other';
      case 'ENTRY_FEE':
        return 'Tickets';
      case 'TRANSPORT':
      case 'TAXI':
        return 'Travel';
      case 'ACTIVITIES':
        return 'Activities';
      case 'TOLL':
        return 'Toll';
      case 'PARKING':
        return 'Parking';
      default:
        return category
            .replaceAll('_', ' ')
            .toLowerCase()
            .replaceFirstMapped(
                RegExp(r'^\w'), (m) => m.group(0)!.toUpperCase());
    }
  }

  static String emojiFor(String category) {
    switch (category) {
      case 'FUEL':
        return '⛽';
      case 'FOOD':
        return '🍔';
      case 'STAY':
        return '🏨';
      case 'TICKETS':
      case 'ENTRY_FEE':
        return '🎫';
      case 'SHOPPING':
        return '🛒';
      default:
        return '🛠';
    }
  }
}
