import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppUtils {
  static Future<void> sendNotification({
    required String title,
    required String body,
    String recipientRole = 'all',
    String? recipientId,
    String? organizationId,
    String status = 'unread',
  }) async {
    try {
      await Supabase.instance.client.from('notifications').insert({
        'title': title,
        'body': body,
        'status': status,
        'recipient_role': recipientRole,
        'recipient_id': recipientId,
        'organization_id': organizationId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Notification dispatch notice: $e');
    }
  }

  static String formatDateTime(dynamic dateStr) {
    if (dateStr == null) return 'Not set';
    try {
      final date = DateTime.parse(dateStr.toString()).toLocal();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final month = months[date.month - 1];
      final day = date.day.toString().padLeft(2, '0');
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$month $day, $year - $hour:$minute';
    } catch (_) {
      return dateStr.toString();
    }
  }

  static void showTopToast(BuildContext context, String message, {bool isError = false}) {
    try {
      final overlay = Overlay.of(context, rootOverlay: true);

      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) => Positioned(
          top: 24,
          left: MediaQuery.of(context).size.width > 800
              ? MediaQuery.of(context).size.width * 0.2
              : 16,
          right: MediaQuery.of(context).size.width > 800
              ? MediaQuery.of(context).size.width * 0.2
              : 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isError ? const Color(0xFFDC2626) : const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      overlay.insert(entry);

      Future.delayed(const Duration(seconds: 4), () {
        try {
          entry.remove();
        } catch (_) {}
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF6366F1),
        ),
      );
    }
  }

  static Duration parseDuration(dynamic raw) {
    final text = (raw ?? '').toString().toLowerCase();
    final m = RegExp(r'(\d*\.?\d+)').firstMatch(text);
    if (m == null) return const Duration(hours: 4);
    final n = double.tryParse(m.group(1)!) ?? 4.0;
    if (text.contains('min')) return Duration(minutes: n.round());
    if (text.contains('day')) return Duration(minutes: (n * 10 * 60).round());
    return Duration(minutes: (n * 60).round());
  }

  static String _clock(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minutes = d.minute.toString().padLeft(2, '0');
    return '$hour12:$minutes ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  ///  "Jan 5, 2026, 8:00 AM – 10:00 AM"
  /// If the end falls on another day, the end date is shown too.
  static String formatEventRange(dynamic proposedDate, dynamic timeFrame) {
    if (proposedDate == null || proposedDate.toString().trim().isEmpty) return 'Not set';
    try {
      final start = DateTime.parse(proposedDate.toString()).toLocal();
      final end = start.add(parseDuration(timeFrame));
      final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final endText = sameDay
          ? _clock(end)
          : '${months[end.month - 1]} ${end.day}, ${end.year}, ${_clock(end)}';
      return '${formatDateTime(proposedDate)} – $endText';
    } catch (_) {
      return formatDateTime(proposedDate);
    }
  }

  static bool isEventDone(Map<String, dynamic> a) {
    final s = (a['status'] ?? '').toString();
    if (s == 'Completed') return true;
    if (s != 'Scheduled') return false;
    final raw = a['proposed_date']?.toString() ?? '';
    if (raw.trim().isEmpty) return false;
    try {
      final start = DateTime.parse(raw).toLocal();
      final end = start.add(parseDuration(a['time_frame']));
      return end.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static String formatTimeFrame(dynamic timeFrame) {
    if (timeFrame == null || timeFrame.toString().trim().isEmpty) {
      return '2 Hours';
    }
    final raw = timeFrame.toString().trim();
    final lower = raw.toLowerCase();

    final numberRegex = RegExp(r'(\d*\.?\d+)');
    final match = numberRegex.firstMatch(raw);

    if (match != null) {
      final valStr = match.group(1)!;
      final val = double.tryParse(valStr) ?? 1.0;
      final intVal = val.toInt();

      if (lower.contains('day')) {
        return intVal == 1 ? '1 Day' : '$intVal Days';
      }
      if (lower.contains('hour') || lower.contains('hr')) {
        return intVal == 1 ? '1 Hour' : '$intVal Hours';
      }

      if (val >= 24) {
        final days = (val / 24).round();
        return days == 1 ? '1 Day' : '$days Days';
      } else {
        return intVal == 1 ? '1 Hour' : '$intVal Hours';
      }
    }

    return raw;
  }
}
