import 'sms_sync_diagnostics.dart';

/// Plain-language reading of [SmsSyncDiagnostics] for the SMS Auto Sync card.
/// Local scanning and cloud upload are reported separately so a healthy scan is
/// never mistaken for a working upload (or vice versa). Contains no ids, no
/// message content — only fixed phrases and category labels.
class SmsSyncHealth {
  const SmsSyncHealth({
    required this.lastAttemptAt,
    required this.lastScanSuccessAt,
    required this.cloudLabel,
    this.cloudNote,
    this.showUploadRow = false,
    this.lastUploadSuccessAt,
    this.uploadNote,
    this.uploadNoteIsError = false,
  });

  final DateTime? lastAttemptAt;
  final DateTime? lastScanSuccessAt;

  /// Short value for the "Cloud Sync" row.
  final String cloudLabel;

  /// One muted sentence under the rows (why unverified / what "off" means).
  final String? cloudNote;

  /// Upload rows only make sense once Cloud Sync is enabled.
  final bool showUploadRow;
  final DateTime? lastUploadSuccessAt;
  final String? uploadNote;
  final bool uploadNoteIsError;
}

/// [nativeLastSuccessAt] is the native worker's own last-success time, used only
/// as a fallback for builds/runs that predate the Dart-side record.
SmsSyncHealth describeSmsSyncHealth(
  SmsSyncDiagnostics d, {
  DateTime? nativeLastSuccessAt,
}) {
  final scanOk = d.lastScanSuccessAt ?? nativeLastSuccessAt;
  switch (d.cloudState) {
    case SmsCloudSyncState.enabled:
      final failure = d.lastUploadFailure;
      String? note;
      if (failure != null) {
        note = d.uploadRetryExhausted
            ? "Cloud upload has failed ${d.consecutiveUploadFailures} times in a row (${failure.label}). Messages are still captured on this device."
            : "Last cloud upload failed: ${failure.label}. It will be retried on the next scan.";
      }
      final notOwned = d.lastUploadSkippedNotOwned;
      if (failure == null && notOwned > 0) {
        note =
            "$notOwned pending message${notOwned == 1 ? '' : 's'} on this device can't be uploaded because they aren't linked to the signed-in account. They stay on this device.";
      }
      return SmsSyncHealth(
        lastAttemptAt: d.lastAttemptAt,
        lastScanSuccessAt: scanOk,
        cloudLabel: 'On',
        showUploadRow: true,
        lastUploadSuccessAt: d.lastUploadSuccessAt,
        uploadNote: note,
        uploadNoteIsError: failure != null || notOwned > 0,
      );
    case SmsCloudSyncState.unverified:
      final reason = d.cloudUnverifiedReason ?? SmsSyncFailureCategory.unknown;
      return SmsSyncHealth(
        lastAttemptAt: d.lastAttemptAt,
        lastScanSuccessAt: scanOk,
        cloudLabel: "Can't verify",
        cloudNote:
            "Cloud Sync status couldn't be checked (${reason.label}), so nothing is uploaded. Scanning on this device is unaffected.",
      );
    case SmsCloudSyncState.disabled:
      return SmsSyncHealth(
        lastAttemptAt: d.lastAttemptAt,
        lastScanSuccessAt: scanOk,
        cloudLabel: 'Off',
        cloudNote: 'Messages stay on this device until Cloud Sync is enabled.',
      );
    case null:
      return SmsSyncHealth(
        lastAttemptAt: d.lastAttemptAt,
        lastScanSuccessAt: scanOk,
        cloudLabel: 'Not checked yet',
      );
  }
}
