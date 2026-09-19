import 'package:flutter/material.dart';
import 'expense_service.dart';

/// Spec BudgetProgressCard: estimated total, overall progress
/// (Spent ₹X / ₹Y) and per-category planned vs spent bars.
class BudgetProgressCard extends StatelessWidget {
  final Map<String, dynamic> budget;
  final VoidCallback onEdit;

  const BudgetProgressCard(
      {super.key, required this.budget, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final items = ((budget['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final totalPlanned =
        ((budget['totalPlanned'] as num?) ?? 0).toDouble();
    final totalSpent =
        ((budget['totalSpent'] as num?) ?? 0).toDouble();
    final progress = ((budget['progress'] as num?) ?? 0).toDouble();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Trip Budget',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label:
                      Text(totalPlanned > 0 ? 'Edit' : 'Create Budget'),
                ),
              ],
            ),
            if (totalPlanned <= 0)
              const Text(
                  'Plan your trip spending: Fuel, Stay, Food, Activities…',
                  style: TextStyle(color: Color(0xFF64748B))),
            if (totalPlanned > 0) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  color: progress >= 1
                      ? Colors.red
                      : progress >= 0.8
                          ? Colors.orange
                          : const Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Spent: ₹${totalSpent.toStringAsFixed(0)} / ₹${totalPlanned.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                          ExpenseService.emojiFor(
                              (it['category'] ?? '').toString()),
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    ExpenseService.labelFor(
                                        (it['category'] ?? '')
                                            .toString()),
                                    style:
                                        const TextStyle(fontSize: 13)),
                                Text(
                                  '₹${((it['spent'] as num?) ?? 0).toStringAsFixed(0)} / ₹${((it['planned'] as num?) ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (((it['progress'] as num?) ??
                                            0)
                                        .toDouble())
                                    .clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor:
                                    Colors.grey.shade200,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
