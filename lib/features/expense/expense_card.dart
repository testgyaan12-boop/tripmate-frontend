import 'package:flutter/material.dart';
import 'expense_service.dart';

/// Spec expense card: title, Added by, Amount, Date, Split N People,
/// Settled/Pending status. Tap opens the detail screen.
class ExpenseCard extends StatelessWidget {
  final Map<String, dynamic> expense;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const ExpenseCard({
    super.key,
    required this.expense,
    required this.onDelete,
    this.onTap,
  });

  static IconData iconFor(String category) {
    switch (category) {
      case 'STAY':
        return Icons.hotel_outlined;
      case 'FOOD':
        return Icons.restaurant_outlined;
      case 'FUEL':
        return Icons.local_gas_station_outlined;
      case 'SHOPPING':
        return Icons.shopping_bag_outlined;
      case 'TICKETS':
      case 'ENTRY_FEE':
        return Icons.confirmation_number_outlined;
      case 'ACTIVITIES':
        return Icons.attractions_outlined;
      case 'TOLL':
        return Icons.toll_outlined;
      case 'PARKING':
        return Icons.local_parking_outlined;
      case 'TRANSPORT':
      case 'TAXI':
        return Icons.directions_bus_outlined;
      default:
        return Icons.receipt_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = (expense['category'] ?? 'OTHER').toString();
    final amount = ((expense['amount'] as num?) ?? 0).toDouble();
    final settled = (expense['status'] ?? 'Pending').toString() == 'Settled';
    final splits = ((expense['splits'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor:
              const Color(0xFF2563EB).withValues(alpha: 0.12),
          child: Text(ExpenseService.emojiFor(category),
              style: const TextStyle(fontSize: 20)),
        ),
        title: Text((expense['title'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Added by ${(expense['paidByName'] ?? expense['addedByName'] ?? '').toString()} • ${_date()}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                    'Split: ${splits.length} ${splits.length == 1 ? 'Person' : 'People'}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF475569))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: settled
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    settled ? 'Settled' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: settled
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _date() {
    final v = expense['expenseDate'] ?? expense['createdAt'];
    if (v == null) return '';
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
