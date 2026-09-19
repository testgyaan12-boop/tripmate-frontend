import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Screen 4 — Share Trip Link bottom sheet: link preview, Copy /
/// WhatsApp / Telegram / Email / Close. Copy shows a success popup.
Future<void> showShareLinkSheet(BuildContext context,
    {required String link, required String tripName}) {
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _Sheet(link: link, tripName: tripName),
  );
}

class _Sheet extends StatelessWidget {
  final String link;
  final String tripName;
  const _Sheet({required this.link, required this.tripName});

  String get _message =>
      'Join my TripMate trip "$tripName"! $link';

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check,
                  color: Color(0xFF10B981), size: 34),
            ),
            const SizedBox(height: 12),
            const Text('Link Copied!',
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Trip invitation link copied to clipboard',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(String text, {String? subject}) async {
    await Share.share(text, subject: subject);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Share Trip Link',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                link,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            _Row(
              emoji: '📋',
              label: 'Copy Link',
              onTap: () => _copy(context),
            ),
            _Row(
              emoji: '💬',
              label: 'WhatsApp',
              onTap: () => _share(_message),
            ),
            _Row(
              emoji: '✈️',
              label: 'Telegram',
              onTap: () => _share(_message),
            ),
            _Row(
              emoji: '✉️',
              label: 'Email',
              onTap: () => _share(_message,
                  subject: 'Join my trip on TripMate'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const _Row(
      {required this.emoji,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Text(emoji,
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.chevron_right_outlined,
                color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}
