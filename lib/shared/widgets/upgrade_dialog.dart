import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_error.dart';

/// Backend limit messages that deserve an Upgrade dialog instead of a
/// plain snackbar (trip/member/join caps, gallery storage, AI quota).
const _limitMarkers = [
  'Trip limit reached',
  'Member limit reached',
  'join max',
  'Gallery storage full',
  'Free AI plans used',
  'Free suggestions used',
];

bool isLimitError(Object e) {
  final m = apiErrorMessage(e);
  return _limitMarkers.any(m.contains);
}

bool isLimitMessage(String msg) => _limitMarkers.any(msg.contains);

/// Limit-reached paywall: Upgrade Now goes to the subscription screen.
Future<void> showLimitUpgradeDialog(BuildContext context, String message,
    {String title = 'Limit reached'}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text('$message\n\nUpgrade to Pro for unlimited.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Maybe later'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            context.go('/subscription');
          },
          child: const Text('Upgrade Now'),
        ),
      ],
    ),
  );
}
