import 'package:flutter/material.dart';

class AppUtils {
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
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.clearSnackBars();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF6366F1),
        duration: const Duration(seconds: 4),
        dismissDirection: DismissDirection.up,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: MediaQuery.of(context).size.width * 0.25,
          right: MediaQuery.of(context).size.width * 0.25,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1),
        ),
        elevation: 8,
      ),
    );
  }

  static Duration parseDuration(dynamic timeFrame) {
    if (timeFrame == null || timeFrame.toString().isEmpty) {
      return const Duration(hours: 4);
    }
    final str = timeFrame.toString().toUpperCase();
    
    // Check for time range like "08:00 AM - 10:00 AM"
    final rangeRegex = RegExp(r'(\d{1,2}:\d{2}\s?[AP]M)\s?-\s?(\d{1,2}:\d{2}\s?[AP]M)');
    final rangeMatch = rangeRegex.firstMatch(str);
    if (rangeMatch != null) {
      try {
        final startStr = rangeMatch.group(1)!;
        final endStr = rangeMatch.group(2)!;
        
        final start = _parseTimeOfDay(startStr);
        final end = _parseTimeOfDay(endStr);
        
        int startMinutes = start.hour * 60 + start.minute;
        int endMinutes = end.hour * 60 + end.minute;
        
        if (endMinutes < startMinutes) {
          endMinutes += 24 * 60; // Next day
        }
        
        return Duration(minutes: endMinutes - startMinutes);
      } catch (_) {}
    }

    final numberRegex = RegExp(r'(\d*\.?\d+)');
    final match = numberRegex.firstMatch(str.toLowerCase());
    if (match != null) {
      final value = double.tryParse(match.group(1)!) ?? 4.0;
      if (str.toLowerCase().contains('min')) return Duration(minutes: value.toInt());
      if (str.toLowerCase().contains('day')) return Duration(minutes: (value * 24 * 60).toInt());
      return Duration(minutes: (value * 60).toInt());
    }
    return const Duration(hours: 4);
  }

  static TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(RegExp(r'[:\s]'));
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);
    final amPm = parts.last.toUpperCase();
    
    if (amPm == 'PM' && hour != 12) hour += 12;
    if (amPm == 'AM' && hour == 12) hour = 0;
    
    return TimeOfDay(hour: hour, minute: minute);
  }
}
