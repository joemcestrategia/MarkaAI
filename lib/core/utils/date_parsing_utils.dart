import 'package:intl/intl.dart';

class DateParsingUtils {
  /// Converts a visual date string (DD/MM/YYYY) to ISO-8601 (YYYY-MM-DD).
  static String? toIso8601(String? visualDate) {
    if (visualDate == null || visualDate.isEmpty) return null;
    try {
      // Handle DD/MM/YYYY
      if (visualDate.contains('/')) {
        final parts = visualDate.split('/');
        if (parts.length == 3) {
          final day = parts[0].padLeft(2, '0');
          final month = parts[1].padLeft(2, '0');
          final year = parts[2];
          return '$year-$month-$day';
        }
      }
      // Fallback: try standard DateTime parsing
      return DateTime.parse(visualDate).toIso8601String();
    } catch (e) {
      return null;
    }
  }

  /// Formats a DateTime to ISO-8601 string safely.
  static String formatIso(DateTime? dt) {
    if (dt == null) return DateTime.now().toIso8601String();
    return dt.toIso8601String();
  }
  
  /// Helper to parse Brazilian date format DD/MM/YYYY to DateTime
  static DateTime? fromBrFormat(String? brDate) {
    if (brDate == null || brDate.isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy').parse(brDate);
    } catch (e) {
      return null;
    }
  }
}
