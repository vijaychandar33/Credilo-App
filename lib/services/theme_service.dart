import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyThemeMode = 'app_theme_mode';
const String _valueDark = 'dark';
const String _valueLight = 'light';

/// Persists and exposes app theme preference for post-login screens.
/// Pre-login (login, sign-up, OTP, profile creation) always uses dark; theme applies from dashboard onward.
class ThemeService {
  ThemeService._();

  static final ValueNotifier<ThemeMode> _notifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
  static bool _initialized = false;

  static ValueNotifier<ThemeMode> get notifier => _notifier;

  static ThemeMode get current => _notifier.value;

  /// Call from main() before runApp.
  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyThemeMode) ?? _valueDark;
    _notifier.value = stored == _valueLight ? ThemeMode.light : ThemeMode.dark;
    _initialized = true;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    if (_notifier.value == mode) return;
    _notifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode == ThemeMode.light ? _valueLight : _valueDark);
  }
}
