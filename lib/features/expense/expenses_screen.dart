import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import 'expense_service.dart';
import 'expense_dashboard.dart';
import 'category_chart.dart';
import 'budget_progress.dart';
import 'expense_card.dart';

/// Spec screen 1+2+7: Expenses dashboard with trip selector, summary
/// cards, category chart, budget and the All Expenses list.
class ExpensesScreen extends ConsumerStatefulWidget {
  final String? initialTripId;
  const ExpensesScreen({super.key, this.initialTripId});

  @override
  ConsumerState<ExpensesScreen> createState() => _State();
}

class _State extends ConsumerState<ExpensesScreen> {
  String? _tripId;
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _expenses = [];
  Map<String, dynamic> _settle = {};
  Map<String, dynamic> _budget = {};
  int? _me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tripId = widget.initialTripId;
    _load();
  }

  @override
  void didUpdateWidget(covariant ExpensesScreen old) {
    super.didUpdateWidget(old);
    if (old.initialTripId != widget.initialTripId &&
        widget.initialTripId != null) {
      _tripId = widget.initialTripId;
      _load();
    }
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    final svc = ExpenseService(dio);
    try {
      final trips = await svc.myTrips();
      if (!mounted) return;
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
        svc.list(tid),
        svc.settlements(tid),
        svc.budget(tid),
        dio.get('/api/users/me'),
      ]);
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _tripId = tid;
        _expenses = res[0] as List<Map<String, dynamic>>;
        _settle = res[1] as Map<String, dynamic>;
        _budget = res[2] as Map<String, dynamic>;
        _me = (((res[3] as dynamic).data['data']['id'] as num?) ?? 0)
            .toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Map<String, dynamic>? get _myBalance {
    for (final m in (_settle['members'] as List?) ?? []) {
      final mm = Map<String, dynamic>.from(m as Map);
      if (((mm['userId'] as num?) ?? -1).toInt() == _me) return mm;
    }
    return null;
  }

  Map<String, double> get _categoryData {
    final out = <String, double>{};
    for (final e in _expenses) {
      final cat = (e['category'] ?? 'OTHER').toString();
      out[cat] =
          (out[cat] ?? 0) + (((e['amount'] as num?) ?? 0).toDouble());
    }
    return out;
  }

  String get _tripTitle {
    for (final t in _trips) {
      if (((t['id'] as num?) ?? -1).toInt().toString() == _tripId) {
        final s = (t['startName'] ?? '').toString();
        final d = (t['destName'] ?? '').toString();
        if (s.isNotEmpty && d.isNotEmpty) return '$s → $d';
        return (t['tripName'] ?? 'Trip').toString();
      }
    }
    return 'Select trip';
  }

  double get _total => _expenses.fold<double>(
      0, (s, e) => s + (((e['amount'] as num?) ?? 0).toDouble()));

  Future<void> _delete(Map<String, dynamic> e) async {
    final id = (e['id'] as num?)?.toInt();
    if (id == null || _tripId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('"${e['title']}" will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ExpenseService(ref.read(dioClientProvider).dio)
          .remove(_tripId!, id);
      _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(err))));
      }
    }
  }

  Future<void> _editBudget() async {
    final items = ((_budget['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cats = ['FUEL', 'STAY', 'FOOD', 'ACTIVITIES', 'TICKETS', 'SHOPPING'];
    final ctrls = <String, TextEditingController>{
      for (final c in cats)
        c: TextEditingController(
            text: _plannedOf(items, c) > 0
                ? _plannedOf(items, c).toStringAsFixed(0)
                : ''),
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Trip Budget',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final c in ctrls.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctrls[c],
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration: InputDecoration(
                        labelText:
                            '${ExpenseService.labelFor(c)} planned ₹',
                        border: const OutlineInputBorder()),
                  ),
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save budget'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (ok != true || _tripId == null) return;
    try {
      final payload = <Map<String, dynamic>>[];
      ctrls.forEach((cat, c) {
        final v = double.tryParse(c.text.trim()) ?? 0;
        if (v > 0) payload.add({'category': cat, 'planned': v});
      });
      await ExpenseService(ref.read(dioClientProvider).dio)
          .saveBudget(_tripId!, payload);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  double _plannedOf(List<Map<String, dynamic>> items, String cat) {
    for (final it in items) {
      if ((it['category'] ?? '').toString() == cat) {
        return ((it['planned'] as num?) ?? 0).toDouble();
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No trips yet.'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => context.push('/trips/new'),
                        child: const Text('Create a trip'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      _tripSelector(),
                      _tripTotal(),
                      _summary(),
                      CategoryChart(data: _categoryData),
                      BudgetProgress(
                          budget: _budget, onEdit: _editBudget),
                      const Padding(
                        padding:
                            EdgeInsets.fromLTRB(16, 10, 16, 2),
                        child: Text('All Expenses',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (_expenses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                              child: Text(
                                  'No expenses yet. Tap + to add one.')),
                        ),
                      ..._daySections(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: OutlinedButton.icon(
                          onPressed: _tripId == null
                              ? null
                              : () => context
                                  .push(
                                      '/expenses/settle?tripId=$_tripId')
                                  .then((_) => _load()),
                          icon: const Icon(
                              Icons.account_balance_wallet_outlined),
                          label: const Text('Open Settlement'),
                        ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: _tripId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context
                  .push('/expenses/new?tripId=$_tripId')
                  .then((_) => _load()),
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
            ),
    );
  }

  Widget _tripSelector() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: const Color(0xFFEFF6FF),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _tripId,
            isExpanded: true,
            icon: const Icon(Icons.expand_more_outlined),
            items: _trips.map((t) {
              final id =
                  ((t['id'] as num?) ?? 0).toInt().toString();
              final s = (t['startName'] ?? '').toString();
              final d = (t['destName'] ?? '').toString();
              return DropdownMenuItem(
                value: id,
                child: Text(
                  s.isNotEmpty && d.isNotEmpty
                      ? '$s → $d ${(t['tripName'] ?? '').toString().isEmpty ? '' : '(${(t['tripName'] ?? '').toString()})'}'
                      : (t['tripName'] ?? 'Trip').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null && v != _tripId) {
                context.go('/trips/$v/expenses');
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _tripTotal() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(_tripTitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Text('₹${_total.toStringAsFixed(_total.truncateToDouble() == _total ? 0 : 2)}',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2563EB))),
        ],
      ),
    );
  }

  Widget _summary() {
    final mine = _myBalance;
    final yourShare = ((mine?['totalOwed'] as num?) ?? 0).toDouble();
    final youPaid = ((mine?['totalPaid'] as num?) ?? 0).toDouble();
    final net = ((mine?['net'] as num?) ?? 0).toDouble();
    return ExpenseDashboard(
      total: _total,
      yourShare: yourShare,
      youPaid: youPaid,
      youGetBack: net > 0 ? net : 0,
    );
  }

  List<Widget> _daySections() {
    final groups = <int, List<Map<String, dynamic>>>{};
    for (final e in _expenses) {
      final day = ((e['dayNo'] ?? 1) as num).toInt();
      groups.putIfAbsent(day, () => []).add(e);
    }
    final days = groups.keys.toList()..sort();
    final out = <Widget>[];
    for (final d in days) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Text(d == 0 ? 'Whole trip' : 'Day $d',
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF475569))),
      ));
      for (final e in groups[d]!) {
        final id = (e['id'] as num?)?.toInt();
        out.add(ExpenseCard(
          expense: e,
          onDelete: () => _delete(e),
          onTap: id == null
              ? null
              : () => context
                  .push('/trips/$_tripId/expenses/$id')
                  .then((_) => _load()),
        ));
      }
    }
    return out;
  }
}
