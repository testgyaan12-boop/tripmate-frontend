import 'package:flutter/material.dart';

/// Shared building blocks for the travel-identity profile page.

class ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onEditPhoto;
  const ProfileHeader(
      {super.key, required this.user, required this.onEditPhoto});

  String get _memberSince {
    try {
      final c = user['createdAt']?.toString();
      if (c == null) return '';
      return DateTime.parse(c).year.toString();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? 'Traveller').toString();
    final email = (user['email'] ?? '').toString();
    final city = (user['city']?.toString() ?? '').isNotEmpty
        ? user['city'].toString()
        : null;
    final img = user['profileImage'] as String?;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: const Color(0xFF2563EB),
              backgroundImage: img != null ? NetworkImage(img) : null,
              onBackgroundImageError: img != null ? (_, _) {} : null,
              child: img == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Material(
                color: const Color(0xFF10B981),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onEditPhoto,
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(Icons.edit,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(email,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            if (city != null)
              _Meta(icon: Icons.location_on_outlined, text: '$city, India'),
            if (_memberSince.isNotEmpty)
              _Meta(
                  icon: Icons.calendar_month_outlined,
                  text: 'Member since $_memberSince'),
          ],
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF64748B))),
      ],
    );
  }
}

class StatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  const StatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            _Stat(
                icon: Icons.route,
                color: const Color(0xFF2563EB),
                value: '${stats['tripsCreated'] ?? 0}',
                label: 'Trips\nCreated'),
            _Stat(
                icon: Icons.place_outlined,
                color: const Color(0xFF10B981),
                value: '${stats['placesVisited'] ?? 0}',
                label: 'Places\nVisited'),
            _Stat(
                icon: Icons.group_outlined,
                color: const Color(0xFF8B5CF6),
                value: '${stats['friendsMet'] ?? 0}',
                label: 'Friends\nJoined'),
            _Stat(
                icon: Icons.how_to_vote_outlined,
                color: const Color(0xFFF59E0B),
                value: '${stats['votesGiven'] ?? 0}',
                label: 'Votes\nGiven'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              height: 1.25,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class TripHistoryCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final int members;
  final VoidCallback onOpen;
  const TripHistoryCard({
    super.key,
    required this.trip,
    required this.members,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final done = (trip['status'] ?? '') == 'FINALIZED';
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.route,
                  color: Color(0xFF2563EB)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trip['startName'] ?? ''} → ${trip['destName'] ?? ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${done ? 'Completed' : (trip['status'] ?? 'Planning')}'
                    ' · $members members',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpen,
              child: const Text('View Trip'),
            ),
          ],
        ),
      ),
    );
  }
}

class AchievementBadge extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool unlocked;
  const AchievementBadge({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unlocked ? 1 : 0.45,
      child: Card(
        margin: EdgeInsets.zero,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: unlocked
                      ? const Color(0xFFFFF7ED)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(emoji,
                    style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Text(subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        )),
                  ],
                ),
              ),
              if (unlocked)
                const Icon(Icons.verified,
                    color: Color(0xFF10B981), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class PreferenceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const PreferenceChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 20),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF64748B))),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? danger;
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.danger,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: danger ?? const Color(0xFF2563EB)),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: danger,
          ),
        ),
        subtitle:
            subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
        trailing: danger != null
            ? null
            : const Icon(Icons.chevron_right,
                color: Color(0xFF94A3B8)),
        onTap: onTap,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}
