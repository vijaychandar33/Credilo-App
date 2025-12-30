import 'package:shared_preferences/shared_preferences.dart';

class ClosingCycleService {
  static const String _keyUseCustomClosing = 'use_custom_closing_time';
  static const String _keyClosingHour = 'closing_hour';
  static const String _keyClosingMinute = 'closing_minute';

  // Default closing time is 12 AM (midnight)
  static const int defaultClosingHour = 0;
  static const int defaultClosingMinute = 0;

  /// Get whether custom closing time is enabled
  static Future<bool> isCustomClosingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseCustomClosing) ?? false;
  }

  /// Set whether custom closing time is enabled
  static Future<void> setCustomClosingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseCustomClosing, enabled);
  }

  /// Get the closing hour (0-23)
  static Future<int> getClosingHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyClosingHour) ?? defaultClosingHour;
  }

  /// Get the closing minute (0-59)
  static Future<int> getClosingMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyClosingMinute) ?? defaultClosingMinute;
  }

  /// Set the closing time
  static Future<void> setClosingTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyClosingHour, hour);
    await prefs.setInt(_keyClosingMinute, minute);
  }

  /// Get the business date for a given DateTime based on the closing cycle
  /// 
  /// If custom closing is enabled and the current time is before the closing time,
  /// it returns the previous day's date. Otherwise, it returns the current date.
  /// 
  /// Example: If closing time is 6 AM and current time is 3 AM, it returns yesterday's date.
  static Future<DateTime> getBusinessDate([DateTime? dateTime]) async {
    final now = dateTime ?? DateTime.now();
    final useCustom = await isCustomClosingEnabled();
    
    if (!useCustom) {
      // Default behavior: use calendar date
      return DateTime(now.year, now.month, now.day);
    }

    final closingHour = await getClosingHour();
    final closingMinute = await getClosingMinute();
    
    // Create a DateTime for today at the closing time
    final closingTimeToday = DateTime(now.year, now.month, now.day, closingHour, closingMinute);
    
    // If current time is before closing time today, it's still the previous business day
    if (now.isBefore(closingTimeToday)) {
      // Return yesterday's date
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    } else {
      // Return today's date
      return DateTime(now.year, now.month, now.day);
    }
  }

  /// Get the current business date (synchronous version using cached values)
  /// This is less accurate but faster - use getBusinessDate() for accuracy
  static DateTime getBusinessDateSync([DateTime? dateTime, bool? useCustom, int? closingHour, int? closingMinute]) {
    final now = dateTime ?? DateTime.now();
    final useCustomClosing = useCustom ?? false;
    
    if (!useCustomClosing) {
      return DateTime(now.year, now.month, now.day);
    }

    final hour = closingHour ?? defaultClosingHour;
    final minute = closingMinute ?? defaultClosingMinute;
    
    final closingTimeToday = DateTime(now.year, now.month, now.day, hour, minute);
    
    if (now.isBefore(closingTimeToday)) {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    } else {
      return DateTime(now.year, now.month, now.day);
    }
  }
}

