import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../auth/presentation/auth_provider.dart'
    show dioClientProvider;
import '../../../../core/network/api_error.dart';
import '../../../expense/expense_service.dart';
import '../../../expense/expense_card.dart';

/// Personal tracker section: this month's travel spending + recent expenses.
class MyExpensesSection extends ConsumerStatefulWidget {
  const MyExpensesSection({super.key});

  @override
  ConsumerState<MyExpensesSection> createState() => _State();
}

class _State extends ConsumerState<MyExpensesSection> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ExpenseService(ref.read(dioClientProvider).dio)
          .mySummary();
      if (!mounted) return;
      setState(() {
        _data = data;
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
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final month =
        ((_data?['monthPaid'] as num?) ?? 0).toDouble();
    final total =
        ((_data?['totalPaid'] as num?) ?? 0).toDouble();
    final recent = ((_data?['recent'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cats = ((_data?['monthByCategory'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xFF0F766E),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This Month — Travel Spending',
                    style: TextStyle(color: Colors.white70)),
                Text('₹${month.toStringAsFixed(month.truncateToDouble() == month ? 0 : 2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    'All-time paid ₹${total.toStringAsFixed(total.truncateToDouble() == total ? 0 : 2)}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Category Breakdown',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        if (cats.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No spending this month.'),
            ),
          ),
        Card(
          child: Column(
            children: [
              for (final c in cats)
                ListTile(
                  dense: true,
                  leading: Text(
                      ExpenseService.emojiFor(
                          (c['category'] ?? 'OTHER').toString()),
                      style: const TextStyle(fontSize: 20)),
                  title: Text(ExpenseService.labelFor(
                      (c['category'] ?? 'OTHER').toString())),
                  trailing: Text(
                      '₹${((c['amount'] as num?) ?? 0).toStringAsFixed(0)}',
                      style:
                          const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Recent Expenses',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        if (recent.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No expenses yet.'),
            ),
          ),
        for (final r in recent)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    const Color(0xFF2563EB).withValues(alpha: 0.12),
                child: Icon(
                    ExpenseCard.iconFor(
                        (r['category'] ?? 'OTHER').toString()),
                    color: const Color(0xFF2563EB),
                    size: 20),
              ),
              title: Text((r['title'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${(r['tripName'] ?? '').toString()} • ${_date(r['date'])}'),
              trailing: Text(
                  '₹${((r['amount'] as num?) ?? 0).toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => context
                  .go('/trips/${r['tripId']}/expenses'),
            ),
          ),
      ],
    );
  }

  String _date(dynamic v) {
    if (v == null) return '';
    try {
      return DateFormat('dd MMM yyyy')
          .format(DateTime.parse(v.toString()).toLocal());
    } catch (_) {
      return v.toString().split('T').first;
    }
  }
}
