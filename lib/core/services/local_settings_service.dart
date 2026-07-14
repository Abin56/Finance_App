import 'package:shared_preferences/shared_preferences.dart';

/// Local-only key/value settings (app-lock flags, theme mode) that never
/// touch Firestore — these are per-device preferences, not synced user data.
/// Mirrors the synchronous-after-init read pattern the old Hive settings
/// box had: call [init] once at startup, then every getter below is
/// synchronous, so callers like `Notifier.build()` need no changes.
class LocalSettingsService {
  LocalSettingsService._();

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _instance {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('LocalSettingsService.init() must be called before use.');
    }
    return prefs;
  }

  static bool getBool(String key, {bool defaultValue = false}) =>
      _instance.getBool(key) ?? defaultValue;

  static Future<void> setBool(String key, bool value) => _instance.setBool(key, value);

  static int getInt(String key, {int defaultValue = 0}) =>
      _instance.getInt(key) ?? defaultValue;

  static Future<void> setInt(String key, int value) => _instance.setInt(key, value);

  static int? getIntOrNull(String key) => _instance.getInt(key);

  static String? getString(String key) => _instance.getString(key);

  static Future<void> setString(String key, String value) => _instance.setString(key, value);

  static Future<void> removeKey(String key) => _instance.remove(key);
}
