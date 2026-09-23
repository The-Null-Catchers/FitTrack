import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive device preferences.
class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppPreferences> create() async =>
      AppPreferences(await SharedPreferences.getInstance());

  static const String _themeKey = 'fittrack.theme_mode';
  static const String _localeKey = 'fittrack.locale';
  static const String _unitsKey = 'fittrack.unit_system';
  static const String _lastSyncKey = 'fittrack.last_sync_at';
  static const String _onboardedKey = 'fittrack.onboarding_seen';
  static const String _restSoundKey = 'fittrack.rest_timer_sound';

  ThemeMode get themeMode => switch (_prefs.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeKey, mode.name);

  /// `null` means "follow the device language".
  Locale? get locale {
    final String? code = _prefs.getString(_localeKey);
    return code == null || code.isEmpty ? null : Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    if (locale == null) {
      await _prefs.remove(_localeKey);
      return;
    }
    await _prefs.setString(_localeKey, locale.languageCode);
  }

  bool get useImperial => _prefs.getBool(_unitsKey) ?? false;

  Future<void> setUseImperial(bool value) => _prefs.setBool(_unitsKey, value);

  DateTime? get lastSyncAt {
    final String? raw = _prefs.getString(_lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncAt(DateTime value) =>
      _prefs.setString(_lastSyncKey, value.toUtc().toIso8601String());

  bool get hasSeenIntro => _prefs.getBool(_onboardedKey) ?? false;

  Future<void> setHasSeenIntro(bool value) =>
      _prefs.setBool(_onboardedKey, value);

  bool get restTimerSound => _prefs.getBool(_restSoundKey) ?? true;

  Future<void> setRestTimerSound(bool value) =>
      _prefs.setBool(_restSoundKey, value);
}
