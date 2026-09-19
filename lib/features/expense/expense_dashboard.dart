import 'package:flutter/material.dart';

/// Spec ExpenseDashboardScreen: four horizontal summary cards with
/// icon, amount and small status text.
class ExpenseDashboardScreen extends StatelessWidget {
  final double total;
  final double yourShare;
  final double youPaid;
  final double youGetBack;
  final int expenseCount;

  const ExpenseDashboardScreen({
    super.key,
    required this.total,
    required this.yourShare,
    required this.youPaid,
    required this.youGetBack,
    required this.expenseCount,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _card('Total Expense', total, const Color(0xFF2563EB),
              Icons.wallet_outlined, '$expenseCount expenses'),
          _card('Your Share', yourShare, const Color(0xFFF59E0B),
              Icons.pie_chart_outline, 'your portion'),
          _card('You Paid', youPaid, const Color(0xFF8B5CF6),
              Icons.arrow_upward_outlined, 'paid by you'),
          _card(
              'You Get Back',
              youGetBack,
              const Color(0xFF10B981),
              Icons.arrow_downward_outlined,
              youGetBack > 0 ? "you'll receive" : 'all settled'),
        ],
      ),
    );
  }

  Widget _card(String label, double value, Color color, IconData icon,
      String status) {
    return Container(
      width: 148,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '₹${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(status,
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
