import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../shared/widgets/not_member_card.dart';
import 'expense_service.dart';
import 'expense_dashboard.dart';
import 'category_chart.dart';
import 'budget_progress.dart';
import 'expense_card.dart';

/// Spec Screen 1: mobile expense dashboard — photo trip card, summary
/// cards, donut chart, quick category chips, budget, recent expenses.
class ExpensesScreen extends ConsumerStatefulWidget {
  final String? initialTripId;
  const ExpensesScreen({super.key, this.initialTripId});

  @override
  ConsumerState<ExpensesScreen> createState() => _State();
}

class _State extends ConsumerState<ExpensesScreen> {
  String? _tripId;
  String? _chip;
  bool _notMember = false;
  bool _retried = false;
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _expenses = [];
  Map<String, dynamic> _settle = {};
  Map<String, dynamic> _budget = {};
  int? _me;
  bool _loading = true;

  static const _chips = [
    'FUEL',
    'FOOD',
    'STAY',
    'TICKETS',
    'SHOPPING',
    'OTHER',
  ];

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
      _chip = null;
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
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _tripId = tid;
      });
      try {
        final res = await Future.wait([
          svc.list(tid),
          svc.settlements(tid),
          svc.budget(tid),
          dio.get('/api/users/me'),
        ]);
        if (!mounted) return;
        setState(() {
          _expenses = res[0] as List<Map<String, dynamic>>;
          _settle = res[1] as Map<String, dynamic>;
          _budget = res[2] as Map<String, dynamic>;
          _me = (((res[3] as dynamic).data['data']['id'] as num?) ?? 0)
              .toInt();
          _loading = false;
          _notMember = false;
        });
      } catch (e) {
        if (!mounted) return;
        if (isNotMemberError(e) && !_retried) {
          _retried = true;
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) { _load(); return; }
        }
        if (isNotMemberError(e)) {
          setState(() {
            _loading = false;
            _notMember = true;
          });
        } else {
          if (!mounted) return;
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(apiErrorMessage(e))));
        }
      }
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

  Map<String, dynamic> get _trip {
    for (final t in _trips) {
      if (((t['id'] as num?) ?? -1).toInt().toString() == _tripId) {
        return t;
      }
    }
    return {};
  }

  String get _route {
    final s = (_trip['startName'] ?? '').toString();
    final d = (_trip['destName'] ?? '').toString();
    if (s.isNotEmpty && d.isNotEmpty) return '$s → $d';
    return (_trip['tripName'] ?? 'Trip').toString();
  }

  String get _tripMeta {
    final parts = <String>[];
    final name = (_trip['tripName'] ?? '').toString();
    if (name.isNotEmpty) parts.add(name);
    parts.add(_daysLabel);
    parts.add('$memberCount Members');
    return parts.join(' • ');
  }

  String get _daysLabel {
    final dc = (_trip['daysCount'] as num?)?.toInt();
    if (dc != null && dc > 0) return '$dc Days';
    try {
      final s = _trip['startDate']?.toString();
      final e = _trip['endDate']?.toString();
      if (s != null && e != null) {
        final days =
            DateTime.parse(e).difference(DateTime.parse(s)).inDays + 1;
        if (days > 0) return '$days Days';
      }
    } catch (_) {}
    return 'Trip';
  }

  int get memberCount => ((_settle['members'] as List?) ?? []).length;

  Map<String, double> get _categoryData {
    final out = <String, double>{};
    for (final e in _expenses) {
      final cat = (e['category'] ?? 'OTHER').toString();
      out[cat] =
          (out[cat] ?? 0) + (((e['amount'] as num?) ?? 0).toDouble());
    }
    return out;
  }

  double get _total => _expenses.fold<double>(
      0, (s, e) => s + (((e['amount'] as num?) ?? 0).toDouble()));

  List<Map<String, dynamic>> get _recent {
    final list = List<Map<String, dynamic>>.from(_expenses);
    list.sort((a, b) {
      final da = (a['expenseDate'] ?? a['createdAt'] ?? '').toString();
      final db = (b['expenseDate'] ?? b['createdAt'] ?? '').toString();
      final c = db.compareTo(da);
      if (c != 0) return c;
      return (((b['id'] as num?) ?? 0))
          .compareTo(((a['id'] as num?) ?? 0));
    });
    final filtered = _chip == null
        ? list
        : list.where((e) => (e['category'] ?? '').toString() == _chip).toList();
    return filtered.take(8).toList();
  }

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

  Future<void> _pickTrip() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select trip',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            for (final t in _trips)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.route_outlined,
                      color: Color(0xFF2563EB)),
                ),
                title: Text(
                    '${(t['startName'] ?? '').toString()} → ${(t['destName'] ?? '').toString()}',
                    style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text((t['tripName'] ?? '').toString()),
                trailing:
                    ((t['id'] as num?) ?? -1).toInt().toString() == _tripId
                        ? const Icon(Icons.check_circle,
                            color: Color(0xFF2563EB))
                        : null,
                onTap: () => Navigator.pop(
                    ctx,
                    ((t['id'] as num?) ?? 0).toInt().toString()),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (v != null && v != _tripId && mounted) {
      context.go('/trips/$v/expenses');
    }
  }

  Future<void> _editBudget() async {
    final items = ((_budget['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cats = [
      'FUEL',
      'STAY',
      'FOOD',
      'ACTIVITIES',
      'TICKETS',
      'SHOPPING'
    ];
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
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
              : _notMember
                  ? SingleChildScrollView(
                      padding:
                          const EdgeInsets.only(bottom: 90),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          _photoTripCard(),
                          NotMemberCard(
                              tripId: _tripId ?? '',
                              onRetry: _load),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 90),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _photoTripCard(),
                        _tripTotal(),
                        _summary(),
                        ExpenseCategoryChart(data: _categoryData),
                        _quickChips(),
                        BudgetProgressCard(
                            budget: _budget, onEdit: _editBudget),
                        const Padding(
                          padding:
                              EdgeInsets.fromLTRB(16, 10, 16, 2),
                          child: Text('Recent Expenses',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (_recent.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                                child: Text(
                                    'No expenses yet. Tap + to add one.')),
                          ),
                        for (final e in _recent)
                          ExpenseCard(
                            expense: e,
                            onDelete: () => _delete(e),
                            onTap: () {
                              final id =
                                  (e['id'] as num?)?.toInt();
                              if (id != null) {
                                context
                                    .push(
                                        '/trips/$_tripId/expenses/$id')
                                    .then((_) => _load());
                              }
                            },
                          ),
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
                            label:
                                const Text('Open Settlement'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      floatingActionButton: (_tripId == null || _notMember)
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

  Widget _photoTripCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _pickTrip,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Image.asset(
                'assets/images/trip_hero.jpg',
                height: 148,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              Container(
                height: 148,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 48,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_route,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(_tripMeta,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const Positioned(
                right: 12,
                bottom: 12,
                child: Icon(Icons.expand_more_outlined,
                    color: Colors.white, size: 28),
              ),
            ],
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
            child: Text(_route,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Text(
              '₹${_total.toStringAsFixed(_total.truncateToDouble() == _total ? 0 : 2)}',
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
    return ExpenseDashboardScreen(
      total: _total,
      yourShare: yourShare,
      youPaid: youPaid,
      youGetBack: net > 0 ? net : 0,
      expenseCount: _expenses.length,
    );
  }

  Widget _quickChips() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: _chips.map((c) {
          final selected = _chip == c;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              showCheckmark: false,
              avatar: Text(ExpenseService.emojiFor(c),
                  style: const TextStyle(fontSize: 15)),
              label: Text(ExpenseService.labelFor(c)),
              onSelected: (_) =>
                  setState(() => _chip = selected ? null : c),
            ),
          );
        }).toList(),
      ),
    );
  }
}
