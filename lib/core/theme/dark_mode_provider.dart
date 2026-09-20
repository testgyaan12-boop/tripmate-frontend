import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global dark-mode provider.
final darkModeProvider =
    ChangeNotifierProvider<DarkModeNotifier>((_) => DarkModeNotifier());

/// Persists dark-mode preference across sessions.
class DarkModeNotifier extends ChangeNotifier {
  static const _key = 'tm_dark_mode';
  bool _dark = false;
  bool get dark => _dark;

  DarkModeNotifier() {
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    _dark = sp.getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> toggle() async {
    _dark = !_dark;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_key, _dark);
  }
}
