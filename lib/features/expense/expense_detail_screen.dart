import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';
import 'expense_service.dart';
import 'split_member_card.dart';
import 'add_expense_form.dart';

/// Spec screen 4: expense detail with big amount, Paid By / Date /
/// Category, per-member Paid/Pending splits, Edit / Delete / Mark Settled.
class ExpenseDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String expenseId;
  const ExpenseDetailScreen(
      {super.key, required this.tripId, required this.expenseId});

  @override
  ConsumerState<ExpenseDetailScreen> createState() => _State();
}

class _State extends ConsumerState<ExpenseDetailScreen> {
  Map<String, dynamic>? _expense;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        ExpenseService(dio).list(widget.tripId),
        dio.get('/api/trips/${widget.tripId}/members/detailed'),
      ]);
      if (!mounted) return;
      final all = res[0] as List<Map<String, dynamic>>;
      final found = all.where(
          (e) => (e['id'] as num?)?.toInt().toString() == widget.expenseId);
      setState(() {
        _expense = found.isEmpty ? null : found.first;
        _members = ((res[1] as dynamic).data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  bool get _settled =>
      (_expense?['status'] ?? 'Pending').toString() == 'Settled';

  Future<void> _toggleSettled() async {
    final id = (_expense?['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await ExpenseService(ref.read(dioClientProvider).dio)
          .markSettled(widget.tripId, id, !_settled);
      bumpData(ref);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(!_settled
                  ? 'Marked as settled'
                  : 'Marked as pending')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _edit() async {
    final meRes =
        await ref.read(dioClientProvider).dio.get('/api/users/me');
    final me = ((meRes.data['data']['id'] as num?) ?? 0).toInt();
    if (!mounted) return;
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
              const Text('Edit expense',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              AddExpenseForm(
                tripId: widget.tripId,
                members: _members,
                me: me,
                initial: _expense,
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      bumpData(ref);
      _load();
    }
  }

  Future<void> _delete() async {
    final id = (_expense?['id'] as num?)?.toInt();
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('"${_expense?['title']}" will be removed.'),
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
          .remove(widget.tripId, id);
      bumpData(ref);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _expense;
    return Scaffold(
      appBar: AppBar(
        title: Text(e == null
            ? 'Expense'
            : (e['title'] ?? 'Expense').toString()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : e == null
              ? const Center(child: Text('Expense not found'))
              : _body(e),
    );
  }

  Widget _body(Map<String, dynamic> e) {
    final amount = ((e['amount'] as num?) ?? 0).toDouble();
    final splits = ((e['splits'] as List?) ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _headerImage((e['category'] ?? 'OTHER').toString()),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF2563EB),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text((e['title'] ?? '').toString(),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                    '₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _row('Paid By', (e['paidByName'] ?? '').toString()),
        _row('Date', _date(e)),
        _row('Category',
            ExpenseService.labelFor((e['category'] ?? '').toString())),
        if ((e['distanceKm'] as num?) != null)
          _row('Distance',
              '${((e['distanceKm'] as num?) ?? 0).toStringAsFixed(1)} km'),
        if ((e['notes'] ?? '').toString().isNotEmpty)
          _row('Note', (e['notes'] ?? '').toString()),
        const SizedBox(height: 12),
        Text('Split: ${splits.length} ${splits.length == 1 ? 'Person' : 'People'}',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        for (final s in splits)
          SplitMemberCard(
            name: (s['name'] ?? '').toString(),
            share: ((s['amount'] as num?) ?? 0).toDouble(),
            isPaid: (s['status'] ?? 'PENDING').toString() == 'PAID',
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _toggleSettled,
            icon: Icon(_settled
                ? Icons.undo_outlined
                : Icons.check_circle_outline),
            label: Text(
                _settled ? 'Mark as Pending' : 'Mark Settled'),
          ),
        ),
      ],
    );
  }

  /// Category header photo (Fuel / Stay / Food / default travel).
  Widget _headerImage(String category) {
    String asset = 'assets/images/trip_hero.jpg';
    if (category == 'FUEL') {
      asset = 'assets/images/splash_road.jpg';
    } else if (category == 'STAY') {
      asset = 'assets/images/trip_goa.jpg';
    } else if (category == 'FOOD') {
      asset = 'assets/images/auth_travel.jpg';
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Image.asset(asset,
              height: 170, width: double.infinity, fit: BoxFit.cover),
          Container(
            height: 170,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 12,
            child: Text(
                ExpenseService.labelFor(category),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _date(Map<String, dynamic> e) {
    final v = e['expenseDate'] ?? e['createdAt'];
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return v.toString().split('T').first;
    }
  }
}
