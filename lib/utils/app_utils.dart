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
      int hour = date.hour;
      final amPm = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final minute = date.minute.toString().padLeft(2, '0');
      return '$month $day, $year - $hour:$minute $amPm';
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
    final str = timeFrame.toString().toLowerCase();
    final numberRegex = RegExp(r'(\d*\.?\d+)');
    final match = numberRegex.firstMatch(str);
    if (match != null) {
      final value = double.tryParse(match.group(1)!) ?? 4.0;
      if (str.contains('min')) return Duration(minutes: value.toInt());
      if (str.contains('day')) return Duration(minutes: (value * 24 * 60).toInt());
      return Duration(minutes: (value * 60).toInt());
    }
    return const Duration(hours: 4);
  }
}
