import 'package:flutter/material.dart';

/// Shared premium widgets for the People feature.
class PeopleTheme {
  static const blue = Color(0xFF2563EB);
  static const green = Color(0xFF10B981);
  static const ink = Color(0xFF0F172A);
  static const sub = Color(0xFF64748B);
  static const bg = Color(0xFFF8FAFC);

  static const avatarColors = [
    Color(0xFF2563EB),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF10B981),
  ];

  static Color avatarColor(int id) =>
      avatarColors[id % avatarColors.length];

  static Color statusColor(String rsvp) {
    switch (rsvp) {
      case 'GOING':
        return green;
      case 'MAYBE':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFF43F5E);
    }
  }

  static String statusLabel(String rsvp) {
    switch (rsvp) {
      case 'GOING':
        return 'Going';
      case 'MAYBE':
        return 'Maybe';
      default:
        return 'Not Going';
    }
  }

  static String memberName(Map<String, dynamic> m) {
    final n = (m['name']?.toString() ?? '').trim();
    if (n.isNotEmpty) return n;
    return 'Traveller ${m['userId']}';
  }

  static int memberId(Map<String, dynamic> m) =>
      ((m['userId'] ?? m['user_id'] ?? m['id']) as num?)?.toInt() ?? 0;

  static String daysLabel(Map<String, dynamic> trip) {
    final dc = (trip['daysCount'] as num?)?.toInt();
    if (dc != null && dc > 0) return '$dc Days';
    try {
      final s = trip['startDate']?.toString();
      final e = trip['endDate']?.toString();
      if (s != null && e != null) {
        final days =
            DateTime.parse(e).difference(DateTime.parse(s)).inDays + 1;
        if (days > 0) return '$days Days';
      }
    } catch (_) {}
    return '';
  }
}

/// Large scenic trip header: photo, route, name, days • members.
class TripHeaderCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final int memberCount;
  const TripHeaderCard(
      {super.key, required this.trip, required this.memberCount});

  @override
  Widget build(BuildContext context) {
    final s = (trip['startName'] ?? '').toString();
    final d = (trip['destName'] ?? '').toString();
    final route = s.isNotEmpty && d.isNotEmpty
        ? '$s → $d'
        : (trip['tripName'] ?? 'Trip').toString();
    final days = PeopleTheme.daysLabel(trip);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Image.asset(
            'assets/images/trip_hero.jpg',
            height: 168,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          Container(
            height: 168,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.68),
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(route,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  [
                    (trip['tripName'] ?? 'Road Trip').toString(),
                    if (days.isNotEmpty) days,
                    '$memberCount Members',
                  ].join(' • '),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal avatar strip: first 4 members + "+N More".
class MemberAvatarList extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final int? me;
  final void Function(Map<String, dynamic> member)? onTap;
  const MemberAvatarList(
      {super.key, required this.members, this.me, this.onTap});

  @override
  Widget build(BuildContext context) {
    final shown = members.take(4).toList();
    final more = members.length - shown.length;
    return Row(
      children: [
        for (final m in shown)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _AvatarName(
                member: m,
                onTap:
                    onTap == null ? null : () => onTap!(m)),
          ),
        if (more > 0)
          Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                    const Color(0xFFEFF6FF),
                child: Text('+$more',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: PeopleTheme.blue)),
              ),
              const SizedBox(height: 4),
              const Text('More',
                  style: TextStyle(
                      fontSize: 11,
                      color: PeopleTheme.sub)),
            ],
          ),
      ],
    );
  }
}

class _AvatarName extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback? onTap;
  const _AvatarName({required this.member, this.onTap});

  @override
  Widget build(BuildContext context) {
    final id = PeopleTheme.memberId(member);
    final name = PeopleTheme.memberName(member);
    final img = member['profileImage'] as String?;
    final isOwner = member['role'] == 'OWNER';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: PeopleTheme.avatarColor(id),
                backgroundImage:
                    img != null ? NetworkImage(img) : null,
                onBackgroundImageError:
                    img != null ? (_, _) {} : null,
                child: img == null
                    ? Text(
                        name.isNotEmpty
                            ? name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20),
                      )
                    : null,
              ),
              if (isOwner)
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.workspace_premium,
                        size: 12, color: Color(0xFFF59E0B)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 62,
            child: Text(
              '${name.split(' ').first}${isOwner ? '\nOwner' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isOwner ? FontWeight.w700 : FontWeight.w500,
                color: isOwner
                    ? PeopleTheme.blue
                    : PeopleTheme.sub,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trip invitation link card with copy + share (+ owner refresh).
class InviteCard extends StatelessWidget {
  final String link;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final bool showRefresh;
  final VoidCallback onRefresh;
  const InviteCard({
    super.key,
    required this.link,
    required this.onCopy,
    required this.onShare,
    required this.showRefresh,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trip Invitation Link',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: PeopleTheme.sub,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      link,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy link',
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  tooltip: 'Share link',
                ),
                if (showRefresh) ...[
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'New link (old one stops working)',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full member row: avatar, name, email, role, status chip, arrow.
class MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool isMe;
  final VoidCallback? onTap;
  const MemberCard({
    super.key,
    required this.member,
    required this.isMe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id = PeopleTheme.memberId(member);
    final name = PeopleTheme.memberName(member);
    final email = (member['email'] ?? '').toString();
    final img = member['profileImage'] as String?;
    final isOwner = member['role'] == 'OWNER';
    final rsvp = (member['rsvp'] ?? 'GOING').toString();
    final statusColor = PeopleTheme.statusColor(rsvp);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    PeopleTheme.avatarColor(id),
                backgroundImage:
                    img != null ? NetworkImage(img) : null,
                onBackgroundImageError:
                    img != null ? (_, _) {} : null,
                child: img == null
                    ? Text(
                        name.isNotEmpty
                            ? name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isMe)
                          Container(
                            margin:
                                const EdgeInsets.only(left: 6),
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: PeopleTheme.blue,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: PeopleTheme.sub,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          isOwner ? 'Trip Owner' : 'Member',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: PeopleTheme.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(
                                alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: Text(
                            PeopleTheme.statusLabel(rsvp),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_outlined,
                  color: PeopleTheme.sub),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary / secondary rounded button used across People screens.
class ShareButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const ShareButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: primary
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

/// Join-trip preview card used on the join screen.
class JoinTripCard extends StatelessWidget {
  final Map<String, dynamic> preview;
  final String dates;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onDecline;
  const JoinTripCard({
    super.key,
    required this.preview,
    required this.dates,
    required this.busy,
    required this.onJoin,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final s = (preview['startName'] ?? '').toString();
    final d = (preview['destName'] ?? '').toString();
    final route = s.isNotEmpty && d.isNotEmpty
        ? '$s → $d'
        : (preview['tripName'] ?? 'Trip').toString();
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Image.asset(
                'assets/images/trip_hero.jpg',
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(route,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    Text(
                        (preview['tripName'] ?? 'Road Trip')
                            .toString(),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dates.isNotEmpty)
                  _meta(Icons.calendar_month_outlined, dates),
                _meta(Icons.group_outlined,
                    '${preview['memberCount'] ?? 0} Members'),
                if ((preview['invitedBy'] ?? '')
                    .toString()
                    .isNotEmpty)
                  _meta(Icons.mail_outline,
                      'Invited by ${preview['invitedBy']} (Trip Owner)'),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    onPressed: busy ? null : onJoin,
                    child:
                        Text(busy ? 'Joining…' : 'Join Trip'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: PeopleTheme.sub),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
