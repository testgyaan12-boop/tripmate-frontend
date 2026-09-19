import 'package:flutter/material.dart';

/// One settlement row: who pays whom + Settle Payment button.
class SettlementCard extends StatelessWidget {
  final Map<String, dynamic> settlement;
  final VoidCallback onSettle;

  const SettlementCard(
      {super.key, required this.settlement, required this.onSettle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFEF3C7),
          child: Icon(Icons.swap_horiz, color: Color(0xFFD97706)),
        ),
        title: Text("${settlement['from']} → ${settlement['to']}",
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Pending'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('₹${(settlement['amount'] as num?) ?? 0}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(width: 4),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
              onPressed: onSettle,
              child: const Text('Settle Payment'),
            ),
          ],
        ),
      ),
    );
  }
}
