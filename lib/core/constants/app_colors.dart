import 'package:flutter/material.dart';

/// Dark-mode-aware colors. Usage: `AppColors.card(context)`
class AppColors {
  static bool _isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static const primary = Color(0xFF2563EB);

  // ── Backgrounds ──
  static Color scaffold(BuildContext c) =>
      _isDark(c) ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  static Color card(BuildContext c) =>
      _isDark(c) ? const Color(0xFF1E293B) : Colors.white;
  static Color cardBorder(BuildContext c) =>
      _isDark(c) ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  static Color inputFill(BuildContext c) =>
      _isDark(c) ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  static Color chipFill(BuildContext c) =>
      _isDark(c) ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

  // ── Text ──
  static Color textPrimary(BuildContext c) =>
      _isDark(c) ? Colors.white : const Color(0xFF0F172A);
  static Color textSecondary(BuildContext c) =>
      _isDark(c) ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color textMuted(BuildContext c) =>
      _isDark(c) ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  // ── Accent (same in both modes) ──
  static const blue = Color(0xFF2563EB);
  static const green = Color(0xFF10B981);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
}
