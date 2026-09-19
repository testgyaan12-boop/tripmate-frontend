import 'package:flutter/material.dart';

/// Horizontal summary cards: Total Expense, Your Share, You Paid,
/// You Get Back. Green for receive, red for pending dues.
class ExpenseDashboard extends StatelessWidget {
  final double total;
  final double yourShare;
  final double youPaid;
  final double youGetBack;

  const ExpenseDashboard({
    super.key,
    required this.total,
    required this.yourShare,
    required this.youPaid,
    required this.youGetBack,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _card('Total Expense', total, const Color(0xFF2563EB)),
          _card('Your Share', yourShare, const Color(0xFFF59E0B)),
          _card('You Paid', youPaid, const Color(0xFF8B5CF6)),
          _card('You Get Back', youGetBack, const Color(0xFF10B981)),
        ],
      ),
    );
  }

  Widget _card(String label, double value, Color color) {
    return Container(
      width: 138,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(
              '₹${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}
