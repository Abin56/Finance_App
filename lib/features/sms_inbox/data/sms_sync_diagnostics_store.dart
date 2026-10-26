import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sms_sync_diagnostics.dart';

/// Local-only persistence for [SmsSyncDiagnostics] (SharedPreferences, never
/// Firestore). The headless worker writes it at most once per scan run
/// (attempt marker + final outcome); the foreground card reads it. Every method
/// swallows storage errors: diagnostics must never break scanning or the UI.
///
/// Stores only timestamps, counters and category codes — see
/// [SmsSyncDiagnostics].
class SmsSyncDiagnosticsStore {
  const SmsSyncDiagnosticsStore();

  static const _p = 'sms_sync_diag_';
  static const kLastAttempt = '${_p}last_attempt_ms';
  static const kLastScanSuccess = '${_p}last_scan_success_ms';
  static const kLastScanError = '${_p}last_scan_error';
  static const kCloudState = '${_p}cloud_state';
  static const kCloudChecked = '${_p}cloud_checked_ms';
  static const kCloudUnverified = '${_p}cloud_unverified';
  static const kLastUploadSuccess = '${_p}last_upload_success_ms';
  static const kLastUploadFailure = '${_p}last_upload_failure';
  static const kLastUploadFailureAt = '${_p}last_upload_failure_ms';
  static const kConsecutiveFailures = '${_p}consecutive_upload_failures';
  static const kUploadSkippedNotOwned = '${_p}upload_skipped_not_owned';

  Future<SmsSyncDiagnostics> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The worker runs in another engine; refresh this isolate's cache.
      await prefs.reload();
      DateTime? at(String key) {
        final ms = prefs.getInt(key);
        return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      }

      SmsCloudSyncState? state;
      final stateName = prefs.getString(kCloudState);
      for (final value in SmsCloudSyncState.values) {
        if (value.name == stateName) state = value;
      }
      return SmsSyncDiagnostics(
        lastAttemptAt: at(kLastAttempt),
        lastScanSuccessAt: at(kLastScanSuccess),
        lastScanError: prefs.getString(kLastScanError),
        cloudState: state,
        cloudCheckedAt: at(kCloudChecked),
        cloudUnverifiedReason: SmsSyncFailureCategory.fromCode(
          prefs.getString(kCloudUnverified),
        ),
        lastUploadSuccessAt: at(kLastUploadSuccess),
        lastUploadFailure: SmsSyncFailureCategory.fromCode(
          prefs.getString(kLastUploadFailure),
        ),
        lastUploadFailureAt: at(kLastUploadFailureAt),
        consecutiveUploadFailures: prefs.getInt(kConsecutiveFailures) ?? 0,
        lastUploadSkippedNotOwned: prefs.getInt(kUploadSkippedNotOwned) ?? 0,
      );
    } catch (_) {
      return const SmsSyncDiagnostics();
    }
  }

  /// Applies [update] to the stored record and persists it. One local write
  /// burst per call.
  Future<void> update(
    SmsSyncDiagnostics Function(SmsSyncDiagnostics current) update,
  ) async {
    try {
      final next = update(await read());
      final prefs = await SharedPreferences.getInstance();
      Future<void> putInt(String key, DateTime? v) async => v == null
          ? prefs.remove(key)
          : prefs.setInt(key, v.millisecondsSinceEpoch);
      Future<void> putStr(String key, String? v) async =>
          v == null ? prefs.remove(key) : prefs.setString(key, v);

      await putInt(kLastAttempt, next.lastAttemptAt);
      await putInt(kLastScanSuccess, next.lastScanSuccessAt);
      await putStr(kLastScanError, next.lastScanError);
      await putStr(kCloudState, next.cloudState?.name);
      await putInt(kCloudChecked, next.cloudCheckedAt);
      await putStr(kCloudUnverified, next.cloudUnverifiedReason?.code);
      await putInt(kLastUploadSuccess, next.lastUploadSuccessAt);
      await putStr(kLastUploadFailure, next.lastUploadFailure?.code);
      await putInt(kLastUploadFailureAt, next.lastUploadFailureAt);
      await prefs.setInt(kConsecutiveFailures, next.consecutiveUploadFailures);
      await prefs.setInt(kUploadSkippedNotOwned, next.lastUploadSkippedNotOwned);
    } catch (_) {
      // Diagnostics are best-effort by design.
    }
  }
}
