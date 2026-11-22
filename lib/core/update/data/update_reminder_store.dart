import 'package:shared_preferences/shared_preferences.dart';

/// How long "Later" silences the optional-update prompt for one specific
/// release. A newer release always prompts again immediately.
const Duration kUpdateSnoozeDuration = Duration(hours: 24);

/// Remembers which release the user postponed and until when, so the optional
/// prompt reappears as a reminder on a later launch/resume instead of nagging
/// on every app open. Preferences only — nothing financial, nothing synced.
class UpdateReminderStore {
  UpdateReminderStore(this._prefs);

  final SharedPreferences _prefs;

  static const _codeKey = 'update_snoozed_version_code';
  static const _untilKey = 'update_snoozed_until_ms';

  bool isSnoozed(int versionCode, {DateTime? now}) {
    final code = _prefs.getInt(_codeKey);
    final untilMs = _prefs.getInt(_untilKey);
    if (code != versionCode || untilMs == null) return false;
    return (now ?? DateTime.now()).millisecondsSinceEpoch < untilMs;
  }

  Future<void> snooze(int versionCode, {DateTime? now}) async {
    final until = (now ?? DateTime.now()).add(kUpdateSnoozeDuration);
    await _prefs.setInt(_codeKey, versionCode);
    await _prefs.setInt(_untilKey, until.millisecondsSinceEpoch);
  }

  Future<void> clear() async {
    await _prefs.remove(_codeKey);
    await _prefs.remove(_untilKey);
  }
}
