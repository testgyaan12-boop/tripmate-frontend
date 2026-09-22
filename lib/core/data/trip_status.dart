/// Centralized trip status & progress logic.
/// Used by Dashboard, Trip Cards, and anywhere trip state is displayed.
library;

import 'package:intl/intl.dart';

class TripStatus {
  /// Returns the status label based on backend status, dates, and current time.
  /// - Finalized: backend status is FINALIZED
  /// - Upcoming: start date is in the future
  /// - Completed: end date has passed
  /// - Planning: default (trip is in progress or no dates set)
  static String statusLabel(Map<String, dynamic> trip) {
    if ((trip['status'] ?? '') == 'FINALIZED') return 'Finalized';
    final now = DateTime.now();
    try {
      if (trip['startDate'] != null &&
          DateTime.parse(trip['startDate'].toString()).isAfter(now)) {
        return 'Upcoming';
      }
      if (trip['endDate'] != null &&
          DateTime.parse(trip['endDate'].toString()).isBefore(now)) {
        return 'Completed';
      }
    } catch (_) {}
    return 'Planning';
  }

  /// Color for the status chip.
  static int statusColor(String label) {
    switch (label) {
      case 'Upcoming':
        return 0xFF2563EB; // blue
      case 'Planning':
        return 0xFFF59E0B; // amber
      case 'Completed':
        return 0xFF10B981; // green
      case 'Finalized':
        return 0xFF8B5CF6; // purple
      default:
        return 0xFF94A3B8; // grey
    }
  }

  /// Calculates trip planning progress (0.0 – 1.0).
  ///
  /// Weight breakdown:
  /// - Base:          20% (trip created)
  /// - Places:        30% (at least 1 place added)
  /// - Itinerary:     30% (at least 1 itinerary item)
  /// - Members:       20% (2+ members, not just owner)
  /// - Finalized:    100% (backend status FINALIZED)
  static double progress({
    required String status,
    required int places,
    required int itineraryItems,
    required int members,
  }) {
    if (status == 'FINALIZED') return 1.0;
    final p = 0.2 +
        (places > 0 ? 0.3 : 0) +
        (itineraryItems > 0 ? 0.3 : 0) +
        (members > 1 ? 0.2 : 0);
    return p.clamp(0.0, 1.0);
  }

  /// Format travel date range: "21 Sep - 25 Sep"
  static String dateLabel(Map<String, dynamic> trip) {
    final s = trip['startDate']?.toString();
    final e = trip['endDate']?.toString();
    if (s == null && e == null) return '';
    String fmt(String? v) {
      if (v == null) return '';
      try {
        final d = DateTime.parse(v);
        return DateFormat('d MMM').format(d);
      } catch (_) {
        return v;
      }
    }
    final a = fmt(s);
    final b = fmt(e);
    if (a.isNotEmpty && b.isNotEmpty) return '$a - $b';
    if (a.isNotEmpty) return a;
    return b;
  }

  /// Full date display: "21 September 2026"
  static String fullDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      return DateFormat('d MMMM yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  /// Days count: prefer explicit field, else calculate from dates.
  static int daysCount(Map<String, dynamic> trip) {
    if (trip['daysCount'] != null) {
      return (trip['daysCount'] as num).toInt();
    }
    final s = trip['startDate']?.toString();
    final e = trip['endDate']?.toString();
    if (s != null && e != null) {
      final days = DateTime.parse(e).difference(DateTime.parse(s)).inDays + 1;
      if (days > 0) return days;
    }
    return 1;
  }

  /// Route label: "Mumbai → Ooty"
  static String route(Map<String, dynamic> trip) {
    final s = (trip['startName'] ?? '').toString();
    final d = (trip['destName'] ?? '').toString();
    if (s.isNotEmpty && d.isNotEmpty) return '$s → $d';
    if (s.isNotEmpty) return s;
    if (d.isNotEmpty) return d;
    return 'No route set';
  }

  /// Distance label: "450 KM"
  static String kmLabel(Map<String, dynamic> trip) {
    final km = trip['totalKm'];
    return km == null ? '–' : '${(km as num).round()} KM';
  }
}
