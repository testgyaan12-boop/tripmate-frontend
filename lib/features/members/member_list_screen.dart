import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import '../../core/network/api_error.dart';
import '../../core/data/refresh.dart';
import 'widgets/people_widgets.dart';

/// Screen 2 — full member list with search. Tap a member for details
/// (own row also allows RSVP editing).
class MemberListScreen extends ConsumerStatefulWidget {
  final String tripId;
  const MemberListScreen({super.key, required this.tripId});

  @override
  ConsumerState<MemberListScreen> createState() => _State();
}

class _State extends ConsumerState<MemberListScreen> {
  List<Map<String, dynamic>> _members = [];
  String _query = '';
  int? _me;
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      final res = await Future.wait([
        dio.get('/api/trips/${widget.tripId}/members/detailed'),
        dio.get('/api/users/me'),
      ]);
      if (!mounted) return;
      setState(() {
        _members = ((res[0].data['data'] as List))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _me = ((res[1] as dynamic).data['data']['id'] as num?)?.toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = _members.where((m) {
      if (q.isEmpty) return true;
      final name = PeopleTheme.memberName(m).toLowerCase();
      final email = (m['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
    list.sort((a, b) {
      final ao = a['role'] == 'OWNER' ? 0 : 1;
      final bo = b['role'] == 'OWNER' ? 0 : 1;
      if (ao != bo) return ao - bo;
      return PeopleTheme.memberName(a)
          .compareTo(PeopleTheme.memberName(b));
    });
    return list;
  }

  Future<void> _setRsvp(String value) async {
    final dio = ref.read(dioClientProvider).dio;
    try {
      await dio.patch(
        '/api/trips/${widget.tripId}/members/rsvp',
        data: {'rsvp': value},
      );
      bumpData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pop(context);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  void _detail(Map<String, dynamic> m) {
    final isMe = PeopleTheme.memberId(m) == _me;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 34,
                backgroundColor: PeopleTheme.avatarColor(
                    PeopleTheme.memberId(m)),
                backgroundImage:
                    m['profileImage'] != null
                        ? NetworkImage(
                            m['profileImage'].toString())
                        : null,
                onBackgroundImageError:
                    m['profileImage'] != null
                        ? (_, _) {}
                        : null,
                child: m['profileImage'] == null
                    ? Text(
                        PeopleTheme.memberName(m).isNotEmpty
                            ? PeopleTheme.memberName(m)[0]
                                .toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 26),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            Text(PeopleTheme.memberName(m),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800)),
            if ((m['email'] ?? '').toString().isNotEmpty)
              Text((m['email'] ?? '').toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: PeopleTheme.sub)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m['role'] == 'OWNER' ? 'Trip Owner' : 'Member',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: PeopleTheme.blue),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: PeopleTheme.statusColor(
                            (m['rsvp'] ?? 'GOING').toString())
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    PeopleTheme.statusLabel(
                        (m['rsvp'] ?? 'GOING').toString()),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: PeopleTheme.statusColor(
                          (m['rsvp'] ?? 'GOING').toString()),
                    ),
                  ),
                ),
              ],
            ),
            if (isMe) ...[
              const SizedBox(height: 14),
              const Text('My status',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final o in const [
                    ('GOING', 'Going'),
                    ('MAYBE', 'Maybe'),
                    ('NOT_GOING', 'No'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlinedButton(
                          onPressed: () => _setRsvp(o.$1),
                          child: Text(o.$2),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: PeopleTheme.bg,
      appBar: AppBar(title: const Text('Members')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search members',
                      prefixIcon:
                          const Icon(Icons.search_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) =>
                        setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: list.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 60),
                            Center(
                                child: Text(
                                    'No members match your search.')),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 40),
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final m = list[i];
                              return MemberCard(
                                member: m,
                                isMe:
                                    PeopleTheme.memberId(m) ==
                                        _me,
                                onTap: () => _detail(m),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
