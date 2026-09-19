import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notification preferences, persisted locally.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _State();
}

class _State extends State<NotificationSettingsScreen> {
  bool _reminders = true;
  bool _votes = true;
  bool _members = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _reminders = p.getBool('tm_notif_reminders') ?? true;
      _votes = p.getBool('tm_notif_votes') ?? true;
      _members = p.getBool('tm_notif_members') ?? true;
      _loaded = true;
    });
  }

  Future<void> _set(String key, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
    if (!mounted) return;
    setState(() {
      if (key == 'tm_notif_reminders') _reminders = v;
      if (key == 'tm_notif_votes') _votes = v;
      if (key == 'tm_notif_members') _members = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/profile'),
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Trip reminders',
                            style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                            'Upcoming trip alerts',
                            style: TextStyle(fontSize: 12)),
                        value: _reminders,
                        onChanged: (v) =>
                            _set('tm_notif_reminders', v),
                      ),
                      SwitchListTile(
                        title: const Text('Votes on my places',
                            style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                            'Someone votes your place',
                            style: TextStyle(fontSize: 12)),
                        value: _votes,
                        onChanged: (v) =>
                            _set('tm_notif_votes', v),
                      ),
                      SwitchListTile(
                        title: const Text('New members',
                            style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                            'Someone joins my trip',
                            style: TextStyle(fontSize: 12)),
                        value: _members,
                        onChanged: (v) =>
                            _set('tm_notif_members', v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
