import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import 'add_expense_form.dart';

/// Spec screen 3: full-screen Add Expense form for the selected trip.
class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? tripId;
  const AddExpenseScreen({super.key, this.tripId});

  @override
  ConsumerState<AddExpenseScreen> createState() => _State();
}

class _State extends ConsumerState<AddExpenseScreen> {
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _members = [];
  String? _tripId;
  int? _me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tripId = widget.tripId;
    _load();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final tripsRes = await dio.get('/api/trips/mine');
      if (!mounted) return;
      final trips = ((tripsRes.data['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (trips.isEmpty) {
        setState(() {
          _trips = [];
          _loading = false;
        });
        return;
      }
      final valid = trips.any((t) =>
          ((t['id'] as num?) ?? -1).toInt().toString() == _tripId);
      final tid = valid
          ? _tripId!
          : ((trips.first['id'] as num?) ?? 0).toInt().toString();
      final res = await Future.wait([
        dio.get('/api/trips/$tid/members/detailed'),
        dio.get('/api/users/me'),
      ]);
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _tripId = tid;
        _members = ((res[0].data['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _me = ((res[1].data['data']['id'] as num?) ?? 0).toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Expense')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tripId == null
              ? const Center(child: Text('No trips yet.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _tripId,
                        decoration: const InputDecoration(
                            labelText: 'Trip',
                            border: OutlineInputBorder()),
                        items: _trips.map((t) {
                          final id = ((t['id'] as num?) ?? 0)
                              .toInt()
                              .toString();
                          final s = (t['startName'] ?? '').toString();
                          final d = (t['destName'] ?? '').toString();
                          return DropdownMenuItem(
                            value: id,
                            child: Text(s.isNotEmpty && d.isNotEmpty
                                ? '$s → $d'
                                : (t['tripName'] ?? 'Trip')
                                    .toString()),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _tripId = v;
                              _loading = true;
                            });
                            _load();
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      AddExpenseForm(
                        key: ValueKey(_tripId),
                        tripId: _tripId!,
                        members: _members,
                        me: _me ?? 0,
                      ),
                    ],
                  ),
                ),
    );
  }
}
