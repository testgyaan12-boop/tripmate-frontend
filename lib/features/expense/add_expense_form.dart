import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';
import 'expense_service.dart';

/// Spec add-expense form: title, amount, category, paid-by dropdown,
/// split-between checkboxes, Equal/Custom toggle, Save Expense.
/// Used by the add screen and (prefilled) by the edit flow.
class AddExpenseForm extends ConsumerStatefulWidget {
  final String tripId;
  final List<Map<String, dynamic>> members;
  final int me;

  /// When set, the form edits this expense instead of creating one.
  final Map<String, dynamic>? initial;

  const AddExpenseForm({
    super.key,
    required this.tripId,
    required this.members,
    required this.me,
    this.initial,
  });

  @override
  ConsumerState<AddExpenseForm> createState() => AddExpenseFormState();
}

class AddExpenseFormState extends ConsumerState<AddExpenseForm> {
  String _category = 'FUEL';
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _day = TextEditingController(text: '1');
  final _distance = TextEditingController();
  final _note = TextEditingController();
  late int _paidBy;
  String _split = 'EQUAL';
  final Set<int> _included = {};
  final Map<int, TextEditingController> _manualCtrls = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _paidBy = widget.me;
    for (final m in widget.members) {
      final id = _memberId(m);
      if (id != 0) {
        _included.add(id);
        _manualCtrls[id] = TextEditingController();
      }
    }
    final init = widget.initial;
    if (init != null) {
      _category = (init['category'] ?? 'FUEL').toString();
      if (!ExpenseService.categories.contains(_category)) {
        _category = 'OTHER';
      }
      _title.text = (init['title'] ?? '').toString();
      final amt = (init['amount'] as num?)?.toDouble();
      if (amt != null) {
        _amount.text =
            amt.truncateToDouble() == amt ? amt.toInt().toString() : '$amt';
      }
      _day.text =
          (((init['dayNo'] ?? 1) as num?) ?? 1).toInt().toString();
      final dist = (init['distanceKm'] as num?);
      if (dist != null) _distance.text = '$dist';
      _note.text = (init['notes'] ?? '').toString();
      _paidBy =
          ((init['paidBy'] as num?) ?? widget.me).toInt();
      _split = (init['splitType'] ?? 'EQUAL').toString();
      if (_split != 'EQUAL' && _split != 'MANUAL') _split = 'EQUAL';
      if (_split == 'MANUAL') _split = 'CUSTOM';
      final splits = ((init['splits'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (splits.isNotEmpty) {
        final manual = splits.any((s) =>
            _split == 'CUSTOM' ||
            (((s['amount'] as num?) ?? 0).toDouble() !=
                (((init['amount'] as num?) ?? 0).toDouble() /
                    splits.length)));
        if (manual) {
          _split = 'CUSTOM';
          for (final s in splits) {
            final uid = ((s['userId'] as num?) ?? 0).toInt();
            final a = ((s['amount'] as num?) ?? 0).toDouble();
            if (uid != 0) {
              _included.add(uid);
              _manualCtrls[uid]?.text =
                  a.truncateToDouble() == a ? a.toInt().toString() : '$a';
            }
          }
        } else {
          _included
            ..clear()
            ..addAll(splits
                .map((s) => ((s['userId'] as num?) ?? 0).toInt())
                .where((x) => x != 0));
        }
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _day.dispose();
    _distance.dispose();
    _note.dispose();
    for (final c in _manualCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _memberId(Map<String, dynamic> m) =>
      ((m['userId'] ?? m['user_id'] ?? m['id']) as num?)?.toInt() ?? 0;

  String _memberName(Map<String, dynamic> m) =>
      (m['name'] ?? m['userName'] ?? 'Member').toString();

  double get _manualSum {
    var s = 0.0;
    for (final id in _included) {
      s += double.tryParse(_manualCtrls[id]?.text.trim() ?? '') ?? 0;
    }
    return s;
  }

  bool get isCustom => _split == 'CUSTOM';

  Future<bool> save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_title.text.trim().isEmpty || amount == null || amount <= 0) {
      _snack('Enter a title and valid amount');
      return false;
    }
    if (_included.isEmpty) {
      _snack('Select at least one member to split with');
      return false;
    }
    Object? splitMembers;
    String splitType = 'EQUAL';
    if (isCustom) {
      splitType = 'MANUAL';
      if ((_manualSum - amount).abs() > 0.01) {
        _snack(
            'Custom split (₹${_manualSum.toStringAsFixed(0)}) must equal amount (₹${amount.toStringAsFixed(0)})');
        return false;
      }
      splitMembers = _included
          .map((id) => {
                'userId': id,
                'amount':
                    double.tryParse(_manualCtrls[id]?.text.trim() ?? '') ??
                        0,
              })
          .toList();
    } else if (_included.length != _manualCtrls.length) {
      splitMembers = _included.toList();
    }
    setState(() => _saving = true);
    final svc = ExpenseService(ref.read(dioClientProvider).dio);
    try {
      final payload = <String, dynamic>{
        'title': _title.text.trim(),
        'amount': amount,
        'category': _category,
        'paidBy': _paidBy,
        'dayNo': int.tryParse(_day.text.trim()) ?? 1,
        'distanceKm': double.tryParse(_distance.text.trim()),
        'notes':
            _note.text.trim().isEmpty ? null : _note.text.trim(),
        'splitType': splitType,
      };
      if (splitMembers != null) payload['splitMembers'] = splitMembers;
      final editingId = (widget.initial?['id'] as num?)?.toInt();
      if (editingId != null) {
        await svc.update(widget.tripId, editingId, payload);
      } else {
        await svc.create(widget.tripId, payload);
      }
      bumpData(ref);
      return true;
    } catch (e) {
      _snack(apiErrorMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(
              labelText: 'Expense Title (e.g. Petrol Mumbai Highway)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Amount ₹', border: OutlineInputBorder()),
                onChanged: (_) {
                  if (isCustom) setState(() {});
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _day,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Day', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(
              labelText: 'Category', border: OutlineInputBorder()),
          items: ExpenseService.categories
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(
                        '${ExpenseService.emojiFor(c)} ${ExpenseService.labelFor(c)}'),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _category = v ?? 'OTHER'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: widget.members.any((m) => _memberId(m) == _paidBy)
              ? _paidBy
              : null,
          decoration: const InputDecoration(
              labelText: 'Paid By', border: OutlineInputBorder()),
          items: widget.members
              .map((m) => DropdownMenuItem(
                    value: _memberId(m),
                    child: Text(_memberName(m)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _paidBy = v);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Split Between',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'EQUAL', label: Text('Equal')),
                ButtonSegment(value: 'CUSTOM', label: Text('Custom')),
              ],
              selected: {_split},
              onSelectionChanged: (s) =>
                  setState(() => _split = s.first),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final m in widget.members) _memberRow(m),
        if (isCustom)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Split total ₹${_manualSum.toStringAsFixed(0)}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569)),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _distance,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Distance covered (km, optional)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  if (await save() && context.mounted) {
                    Navigator.pop(context, true);
                  }
                },
          child: Text(_saving
              ? 'Saving…'
              : widget.initial == null
                  ? 'Save Expense'
                  : 'Update Expense'),
        ),
      ],
    );
  }

  Widget _memberRow(Map<String, dynamic> m) {
    final id = _memberId(m);
    final checked = _included.contains(id);
    return Row(
      children: [
        Checkbox(
          value: checked,
          onChanged: (v) => setState(() {
            if (v == true) {
              _included.add(id);
            } else {
              _included.remove(id);
            }
          }),
        ),
        Expanded(child: Text(_memberName(m))),
        if (isCustom && checked)
          SizedBox(
            width: 110,
            child: TextField(
              controller: _manualCtrls[id],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '₹',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
      ],
    );
  }
}
