import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';
import 'expense_service.dart';
import 'settlement_card.dart';

/// Spec screen 5: Settlement — You owe / You will receive,
/// Settle Payment (UPI / Cash / Bank Transfer), payment history.
class SettlementScreen extends ConsumerStatefulWidget {
  final String? tripId;
  const SettlementScreen({super.key, this.tripId});

  @override
  ConsumerState<SettlementScreen> createState() => _State();
}

class _State extends ConsumerState<SettlementScreen> {
  String? _tripId;
  Map<String, dynamic>? _data;
  int _me = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tripId = widget.tripId;
    _load();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    final svc = ExpenseService(dio);
    try {
      String? tid = _tripId;
      tid ??= await _firstTripId(svc);
      if (!mounted) return;
      if (tid == null) {
        setState(() => _loading = false);
        return;
      }
      final data = await svc.settlements(tid);
      final meRes = await dio.get('/api/users/me');
      if (!mounted) return;
      setState(() {
        _tripId = tid;
        _data = data;
        _me = ((meRes.data['data']['id'] as num?) ?? 0).toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<String?> _firstTripId(ExpenseService svc) async {
    final trips = await svc.myTrips();
    if (trips.isEmpty) return null;
    return ((trips.first['id'] as num?) ?? 0).toInt().toString();
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_data?[key] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<void> _settlePayment(Map<String, dynamic> s,
      {required bool iOwe}) async {
    final otherId = ((s['userId'] as num?) ?? 0).toInt();
    final amount = ((s['amount'] as num?) ?? 0).toDouble();
    final other = (s['name'] ?? '').toString();
    String method = 'UPI';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _MethodSheet(
        title:
            'Settle ₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}',
        subtitle: iOwe ? 'You → $other' : '$other → You',
        onPick: (m) => Navigator.pop(ctx, true),
        onMethod: (m) => method = m,
      ),
    );
    if (ok != true || _tripId == null) return;
    try {
      final body = iOwe
          ? {'toUserId': otherId, 'amount': amount, 'method': method}
          : {
              'fromUserId': otherId,
              'toUserId': _me,
              'amount': amount,
              'method': method
            };
      final res = await ExpenseService(ref.read(dioClientProvider).dio)
          .recordPayment(_tripId!, body);
      bumpData(ref);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Settled ₹${((res['applied'] as num?) ?? amount)} via ${_label(method)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  static String _label(String m) {
    switch (m) {
      case 'BANK':
        return 'Bank Transfer';
      case 'CASH':
        return 'Cash';
      default:
        return 'UPI';
    }
  }

  @override
  Widget build(BuildContext context) {
    final youOwe = _list('youOwe');
    final youReceive = _list('youReceive');
    final plan = _list('settlements');
    final payments = _list('payments');
    return Scaffold(
      appBar: AppBar(title: const Text('Settlement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tripId == null
              ? const Center(child: Text('No trips yet.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (youOwe.isNotEmpty) ...[
                        const Text('You owe',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        for (final o in youOwe)
                          _dueCard(o, iOwe: true),
                        const SizedBox(height: 8),
                      ],
                      if (youReceive.isNotEmpty) ...[
                        const Text('You will receive',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        for (final o in youReceive)
                          _dueCard(o, iOwe: false),
                        const SizedBox(height: 8),
                      ],
                      if (youOwe.isEmpty && youReceive.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                'All settled up. No payments needed.'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text('Who pays whom',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      const SizedBox(height: 4),
                      for (final s in plan)
                        SettlementCard(
                          settlement: s,
                          onSettle: () => _settlePlanPayment(s),
                        ),
                      if (payments.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Payment history',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        for (final p in payments)
                          Card(
                            child: ListTile(
                              leading: const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green),
                              title: Text(
                                  "${p['from']} → ${p['to']}",
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600)),
                              subtitle: Text(
                                  '${_label((p['method'] ?? '').toString())} • ${((p['date'] ?? '').toString().split('T').first)}'),
                              trailing: Text(
                                  '₹${(p['amount'] as num?) ?? 0}',
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w700)),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _dueCard(Map<String, dynamic> o, {required bool iOwe}) {
    final amount = ((o['amount'] as num?) ?? 0).toDouble();
    final name = (o['name'] ?? '').toString();
    return Card(
      color: iOwe ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
      child: ListTile(
        leading: Icon(
            iOwe ? Icons.arrow_upward : Icons.arrow_downward,
            color: iOwe ? Colors.red : Colors.green),
        title: Text(iOwe ? 'You owe $name' : 'You will receive from $name',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: iOwe
                      ? Colors.red.shade700
                      : Colors.green.shade700),
            ),
            const SizedBox(width: 4),
            if (iOwe)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onPressed: () => _settlePayment(o, iOwe: true),
                child: const Text('Settle Payment'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _settlePlanPayment(Map<String, dynamic> s) async {
    if (_tripId == null) return;
    String method = 'UPI';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _MethodSheet(
        title:
            'Settle ₹${(s['amount'] as num?) ?? 0}',
        subtitle: "${s['from']} → ${s['to']}",
        onPick: (m) => Navigator.pop(ctx, true),
        onMethod: (m) => method = m,
      ),
    );
    if (ok != true) return;
    try {
      await ExpenseService(ref.read(dioClientProvider).dio)
          .recordPayment(_tripId!, {
        'toUserId': (s['toId'] as num?) ?? 0,
        'amount': (s['amount'] as num?) ?? 0,
        'method': method,
      });
      bumpData(ref);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Settled via ${_label(method)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }
}

/// Payment options sheet: UPI / Cash / Bank Transfer.
class _MethodSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final void Function(String method) onPick;
  final void Function(String method) onMethod;
  const _MethodSheet({
    required this.title,
    required this.subtitle,
    required this.onPick,
    required this.onMethod,
  });

  @override
  State<_MethodSheet> createState() => _MethodSheetState();
}

class _MethodSheetState extends State<_MethodSheet> {
  String _method = 'UPI';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          Text(widget.subtitle,
              style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 12),
          const Text('Payment Options',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'UPI', label: Text('UPI')),
              ButtonSegment(value: 'CASH', label: Text('Cash')),
              ButtonSegment(
                  value: 'BANK', label: Text('Bank Transfer')),
            ],
            selected: {_method},
            onSelectionChanged: (v) => setState(() {
              _method = v.first;
              widget.onMethod(_method);
            }),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => widget.onPick(_method),
            child: const Text('Settle Payment'),
          ),
        ],
      ),
    );
  }
}
