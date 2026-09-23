import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/dark_mode_provider.dart';

/// Dark mode toggle icon — reuse in any AppBar actions.
class DarkModeToggle extends ConsumerWidget {
  const DarkModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      onPressed: () => ref.read(darkModeProvider).toggle(),
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        color: isDark ? const Color(0xFFF59E0B) : const Color(0xFF64748B),
      ),
    );
  }
}

/// Notification bell icon — reuse in any AppBar actions.
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      onPressed: () => context.go('/notifications'),
      icon: Icon(
        Icons.notifications_outlined,
        color: isDark ? Colors.white70 : const Color(0xFF64748B),
      ),
    );
  }
}

/// Home top bar: profile avatar plus a "Hello name" greeting beside it,
// actions pinned right. Name comes exact from the profile (/api/users/me).
class TripMateHomeTopBar extends ConsumerWidget {
  final Map<String, dynamic> user;
  const TripMateHomeTopBar({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (user['name'] ?? 'Traveller').toString();
    final img = user['profileImage'] as String?;
    void openProfile() => context.go('/profile');
    return Row(
      children: [
        GestureDetector(
          onTap: openProfile,
          child: CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF2563EB),
            backgroundImage: img != null ? NetworkImage(img) : null,
            child: img == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: openProfile,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hello, $name 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                Text(
                  'Where to next?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        const DarkModeToggle(),
        const SizedBox(width: 4),
        const NotificationsButton(),
      ],
    );
  }
}
