import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';

/// Keys for "What to show" items. Must match usage in home_screen and branch_what_to_show_screen.
class BranchVisibilityKeys {
  static const String creditExpense = 'credit_expense';
  static const String cashDailyExpense = 'cash_daily_expense';
  static const String onlineDailyExpense = 'online_daily_expense';
  static const String cashBalance = 'cash_balance';
  static const String card = 'card';
  static const String onlineSales = 'online_sales';
  static const String upi = 'upi';
  static const String due = 'due';
  static const String cashClosing = 'cash_closing';
  static const String safeManagement = 'safe_management';

  static List<String> get all => [
        creditExpense,
        cashDailyExpense,
        onlineDailyExpense,
        cashBalance,
        card,
        onlineSales,
        upi,
        due,
        cashClosing,
        safeManagement,
      ];

  /// Display label for each key (for "What to show" screen).
  static String label(String key) {
    switch (key) {
      case creditExpense:
        return 'Credit expense';
      case cashDailyExpense:
        return 'Cash daily expense';
      case onlineDailyExpense:
        return 'Online daily expense';
      case cashBalance:
        return 'Cash balance';
      case card:
        return 'Card';
      case onlineSales:
        return 'Online sales';
      case upi:
        return 'UPI';
      case due:
        return 'Due';
      case cashClosing:
        return 'Cash closing';
      case safeManagement:
        return 'Safe management';
      default:
        return key;
    }
  }

  /// Map from visibility key to home_screen section title (for filtering).
  static String sectionTitle(String key) {
    switch (key) {
      case creditExpense:
        return 'Credit Expense';
      case cashDailyExpense:
        return 'Cash Daily Expense';
      case onlineDailyExpense:
        return 'Online Daily Expense';
      case cashBalance:
        return 'Cash Balance';
      case card:
        return 'Card';
      case onlineSales:
        return 'Online Sales';
      case upi:
        return 'UPI';
      case due:
        return 'Due';
      case cashClosing:
        return 'Cash Closing';
      case safeManagement:
        return 'Safe Management';
      default:
        return key;
    }
  }
}

/// Per-branch "What to show" visibility. Online-first: Supabase is source of truth.
/// SharedPreferences is used only as a cache for faster access (return cache first, refresh from Supabase in background).
class BranchVisibilityService {
  static const _prefix = 'branch_visibility_';
  static final _db = DatabaseService();

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<Map<String, bool>> _readCache(String branchId) async {
    final result = <String, bool>{};
    for (final key in BranchVisibilityKeys.all) {
      result[key] = true;
    }
    try {
      final prefs = await _prefs();
      final json = prefs.getString('$_prefix$branchId');
      if (json == null) return result;
      final map = jsonDecode(json) as Map<String, dynamic>;
      for (final key in BranchVisibilityKeys.all) {
        if (map.containsKey(key)) {
          result[key] = map[key] as bool? ?? true;
        }
      }
    } catch (_) {}
    return result;
  }

  static Future<void> _writeCache(String branchId, Map<String, bool> visibility) async {
    try {
      final prefs = await _prefs();
      await prefs.setString('$_prefix$branchId', jsonEncode(visibility));
    } catch (_) {}
  }

  /// Refresh cache from Supabase in background (fire-and-forget).
  static void _refreshFromSupabase(String branchId) {
    Future(() async {
      try {
        final fromDb = await _db.getBranchVisibility(branchId);
        final result = <String, bool>{};
        for (final key in BranchVisibilityKeys.all) {
          result[key] = fromDb[key] ?? true;
        }
        await _writeCache(branchId, result);
      } catch (e) {
        debugPrint('BranchVisibilityService background refresh error: $e');
      }
    });
  }

  /// Returns whether the section [key] is visible for [branchId]. Default true.
  static Future<bool> isVisible(String branchId, String key) async {
    final all = await getAll(branchId);
    return all[key] ?? true;
  }

  /// Get all visibility settings. Returns cache immediately for speed if present, then refreshes from Supabase in background.
  /// If no cache, fetches from Supabase and caches. Online-first; cache is for faster access only.
  static Future<Map<String, bool>> getAll(String branchId) async {
    final prefs = await _prefs();
    final hasCache = prefs.containsKey('$_prefix$branchId');

    if (hasCache) {
      final cached = await _readCache(branchId);
      _refreshFromSupabase(branchId);
      return cached;
    }

    try {
      final fromDb = await _db.getBranchVisibility(branchId);
      final result = <String, bool>{};
      for (final key in BranchVisibilityKeys.all) {
        result[key] = fromDb[key] ?? true;
      }
      await _writeCache(branchId, result);
      return result;
    } catch (e) {
      debugPrint('BranchVisibilityService.getAll error: $e');
      rethrow;
    }
  }

  /// Set visibility for one key. Online-only: writes to Supabase first, then updates cache on success.
  static Future<void> set(String branchId, String key, bool visible) async {
    await _db.setBranchVisibility(branchId, key, visible);
    final all = await _readCache(branchId);
    all[key] = visible;
    await _writeCache(branchId, all);
  }

  /// Set all visibility for a branch. Online-only: writes to Supabase first, then updates cache on success.
  static Future<void> setAll(String branchId, Map<String, bool> visibility) async {
    final all = <String, bool>{};
    for (final key in BranchVisibilityKeys.all) {
      all[key] = visibility[key] ?? true;
    }
    await _db.setAllBranchVisibility(branchId, all);
    await _writeCache(branchId, all);
  }
}
