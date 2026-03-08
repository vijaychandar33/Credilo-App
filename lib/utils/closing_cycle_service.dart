import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/branch_closing_cycle.dart';
import '../services/database_service.dart';

/// Per-branch custom closing cycle. Online-first: Supabase is source of truth.
/// SharedPreferences is used only as a cache for faster access (return cache first, refresh from Supabase in background).
class ClosingCycleService {
  static const int defaultClosingHour = 1;
  static const int defaultClosingMinute = 0;

  static const _cachePrefix = 'branch_closing_cycle_';
  static final _db = DatabaseService();

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<BranchClosingCycle?> _readCache(String branchId) async {
    if (branchId.isEmpty) return null;
    try {
      final prefs = await _prefs();
      final json = prefs.getString('$_cachePrefix$branchId');
      if (json == null) return null;
      final map = jsonDecode(json) as Map<String, dynamic>;
      return BranchClosingCycle(
        branchId: branchId,
        useCustomClosing: map['use_custom_closing'] as bool? ?? false,
        closingHour: (map['closing_hour'] as num?)?.toInt() ?? defaultClosingHour,
        closingMinute: (map['closing_minute'] as num?)?.toInt() ?? defaultClosingMinute,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String branchId, BranchClosingCycle cycle) async {
    try {
      final prefs = await _prefs();
      await prefs.setString('$_cachePrefix$branchId', jsonEncode({
        'use_custom_closing': cycle.useCustomClosing,
        'closing_hour': cycle.closingHour,
        'closing_minute': cycle.closingMinute,
      }));
    } catch (_) {}
  }

  /// Refresh cache from Supabase in background (fire-and-forget).
  static void _refreshFromSupabase(String branchId) {
    Future(() async {
      try {
        final cycle = await _db.getBranchClosingCycleOrDefault(branchId);
        await _writeCache(branchId, cycle);
      } catch (e) {
        debugPrint('ClosingCycleService background refresh error: $e');
      }
    });
  }

  /// Get full closing cycle. Returns cache immediately for speed if present, then refreshes from Supabase in background.
  /// If no cache, fetches from Supabase and caches. Online-first.
  static Future<BranchClosingCycle> getBranchClosingCycleOrDefault(String branchId) async {
    if (branchId.isEmpty) return BranchClosingCycle(branchId: '');

    final prefs = await _prefs();
    final hasCache = prefs.containsKey('$_cachePrefix$branchId');

    if (hasCache) {
      final cached = await _readCache(branchId);
      if (cached != null) {
        _refreshFromSupabase(branchId);
        return cached;
      }
    }

    final cycle = await _db.getBranchClosingCycleOrDefault(branchId);
    await _writeCache(branchId, cycle);
    return cycle;
  }

  /// Get whether custom closing time is enabled for this branch.
  static Future<bool> isCustomClosingEnabled(String branchId) async {
    if (branchId.isEmpty) return false;
    final cycle = await getBranchClosingCycleOrDefault(branchId);
    return cycle.useCustomClosing;
  }

  /// Set whether custom closing time is enabled for this branch. Online-only: Supabase first, then update cache.
  static Future<void> setCustomClosingEnabled(String branchId, bool enabled) async {
    if (branchId.isEmpty) return;
    final cycle = await getBranchClosingCycleOrDefault(branchId);
    var hour = cycle.closingHour;
    var minute = cycle.closingMinute;
    if (enabled && (hour == 0)) {
      hour = defaultClosingHour;
      minute = defaultClosingMinute;
    }
    final updated = BranchClosingCycle(
      branchId: branchId,
      useCustomClosing: enabled,
      closingHour: hour,
      closingMinute: minute,
    );
    await _db.upsertBranchClosingCycle(updated);
    await _writeCache(branchId, updated);
  }

  /// Get the closing hour (0-23) for this branch.
  static Future<int> getClosingHour(String branchId) async {
    if (branchId.isEmpty) return defaultClosingHour;
    final cycle = await getBranchClosingCycleOrDefault(branchId);
    return cycle.closingHour == 0 ? defaultClosingHour : cycle.closingHour;
  }

  /// Get the closing minute (0-59) for this branch.
  static Future<int> getClosingMinute(String branchId) async {
    if (branchId.isEmpty) return defaultClosingMinute;
    final cycle = await getBranchClosingCycleOrDefault(branchId);
    return cycle.closingMinute;
  }

  /// Set the closing time for this branch. Online-only: Supabase first, then update cache.
  static Future<void> setClosingTime(String branchId, int hour, int minute) async {
    if (branchId.isEmpty) return;
    final cycle = await getBranchClosingCycleOrDefault(branchId);
    final updated = BranchClosingCycle(
      branchId: branchId,
      useCustomClosing: cycle.useCustomClosing,
      closingHour: hour,
      closingMinute: minute,
    );
    await _db.upsertBranchClosingCycle(updated);
    await _writeCache(branchId, updated);
  }

  /// Get the business date for a given DateTime based on this branch's closing cycle.
  static Future<DateTime> getBusinessDate(String branchId, [DateTime? dateTime]) async {
    final now = dateTime ?? DateTime.now();
    if (branchId.isEmpty) return DateTime(now.year, now.month, now.day);

    final useCustom = await isCustomClosingEnabled(branchId);
    if (!useCustom) {
      return DateTime(now.year, now.month, now.day);
    }

    final closingHour = await getClosingHour(branchId);
    final closingMinute = await getClosingMinute(branchId);
    final closingTimeToday = DateTime(now.year, now.month, now.day, closingHour, closingMinute);

    if (now.isBefore(closingTimeToday)) {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    }
    return DateTime(now.year, now.month, now.day);
  }

  /// Synchronous business date when you already have the cycle values (e.g. from cache).
  static DateTime getBusinessDateSync(
    DateTime? dateTime,
    bool useCustom,
    int closingHour,
    int closingMinute,
  ) {
    final now = dateTime ?? DateTime.now();
    if (!useCustom) return DateTime(now.year, now.month, now.day);

    final hour = closingHour == 0 ? defaultClosingHour : closingHour;
    final minute = closingMinute;
    final closingTimeToday = DateTime(now.year, now.month, now.day, hour, minute);

    if (now.isBefore(closingTimeToday)) {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    }
    return DateTime(now.year, now.month, now.day);
  }
}
