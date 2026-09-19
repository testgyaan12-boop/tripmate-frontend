import 'package:flutter/material.dart';

/// One member's share row: avatar, name, amount, Paid/Pending chip.
class SplitMemberCard extends StatelessWidget {
  final String name;
  final double share;
  final bool isPaid;

  const SplitMemberCard({
    super.key,
    required this.name,
    required this.share,
    required this.isPaid,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              const Color(0xFF2563EB).withValues(alpha: 0.12),
          child: Text(
              name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2563EB))),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                '₹${share.toStringAsFixed(share.truncateToDouble() == share ? 0 : 2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isPaid
                    ? Colors.green.shade100
                    : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isPaid ? 'Paid' : 'Pending',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isPaid
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
