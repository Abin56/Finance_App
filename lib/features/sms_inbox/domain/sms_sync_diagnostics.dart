import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Whether background Cloud Sync may upload, as last determined by the runtime
/// switch (`sms_background_upload_switch.dart`). Three honest states:
///
///  * [enabled]    — the switch authorizes this account on this device;
///  * [disabled]   — the switch was read and does NOT authorize it (no
///                   document, `enabled:false`, or another device) — the default;
///  * [unverified] — the switch could not be read (offline, signed out,
///                   permission denied, timeout…). Upload is NOT attempted
///                   (fail closed), but "off" would be a claim we can't back up.
enum SmsCloudSyncState { disabled, enabled, unverified }

/// Privacy-safe failure categories. These are the ONLY failure detail ever
/// stored or shown — never an exception message (which can echo ids, paths or
/// SMS-derived values).
enum SmsSyncFailureCategory {
  authUnavailable('auth_unavailable', 'not signed in, or sign-in unavailable'),
  permissionDenied('permission_denied', 'the server denied permission'),
  offline('offline', 'no connection'),
  timeout('timeout', 'the request timed out'),
  unknown('unknown', 'an unexpected error');

  const SmsSyncFailureCategory(this.code, this.label);

  /// Stable machine code persisted in local diagnostics.
  final String code;

  /// Plain-language fragment for the status UI.
  final String label;

  static SmsSyncFailureCategory? fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return code == null ? null : unknown;
  }
}

/// Maps any thrown object to a [SmsSyncFailureCategory] WITHOUT reading its
/// message text.
SmsSyncFailureCategory classifySmsSyncFailure(Object error) {
  if (error is TimeoutException) return SmsSyncFailureCategory.timeout;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return SmsSyncFailureCategory.permissionDenied;
      case 'unauthenticated':
        return SmsSyncFailureCategory.authUnavailable;
      case 'unavailable':
      case 'network-request-failed':
        return SmsSyncFailureCategory.offline;
      case 'deadline-exceeded':
        return SmsSyncFailureCategory.timeout;
    }
  }
  return SmsSyncFailureCategory.unknown;
}

/// Local, content-free health record for the background SMS pipeline. Written
/// by the headless worker once per run (plus one attempt marker), read by the
/// SMS Auto Sync card. Holds timestamps, counters and category codes only — no
/// SMS body/sender, uid, device id, or account/card details.
class SmsSyncDiagnostics {
  const SmsSyncDiagnostics({
    this.lastAttemptAt,
    this.lastScanSuccessAt,
    this.lastScanError,
    this.cloudState,
    this.cloudCheckedAt,
    this.cloudUnverifiedReason,
    this.lastUploadSuccessAt,
    this.lastUploadFailure,
    this.lastUploadFailureAt,
    this.consecutiveUploadFailures = 0,
    this.lastUploadSkippedNotOwned = 0,
  });

  /// After this many uploads in a row fail, the UI says retries are
  /// exhausted/repeating instead of "will retry". (Every background scan is
  /// one upload attempt; there is no separate retry loop.)
  static const int retryExhaustedThreshold = 5;

  final DateTime? lastAttemptAt;

  /// Local SMS scan only — independent of any upload.
  final DateTime? lastScanSuccessAt;
  final String? lastScanError;

  /// `null` until a run has reported it.
  final SmsCloudSyncState? cloudState;
  final DateTime? cloudCheckedAt;

  /// Why [cloudState] is [SmsCloudSyncState.unverified]; null otherwise.
  final SmsSyncFailureCategory? cloudUnverifiedReason;

  /// Cloud upload outcomes — separate from the local scan above.
  final DateTime? lastUploadSuccessAt;
  final SmsSyncFailureCategory? lastUploadFailure;
  final DateTime? lastUploadFailureAt;
  final int consecutiveUploadFailures;

  /// Pending candidates the latest upload step could not consider because
  /// they are not bound to the signed-in account. Replaced every upload run.
  final int lastUploadSkippedNotOwned;

  bool get uploadRetryExhausted =>
      consecutiveUploadFailures >= retryExhaustedThreshold;

  SmsSyncDiagnostics applyAttempt(DateTime now) => _copy(lastAttemptAt: now);

  /// Folds one finished run into the record. [scanSucceeded]/[scanError]
  /// describe the LOCAL scan. [cloudControlled] is whether the build consults
  /// the runtime switch at all; [gateState]/[gateFailure] are what it said
  /// (null when the scan failed before the gate was consulted). [uploadRan]
  /// and [uploadFailure] describe the upload step itself.
  SmsSyncDiagnostics applyRun({
    required DateTime now,
    required bool scanSucceeded,
    String? scanError,
    required bool cloudControlled,
    SmsCloudSyncState? gateState,
    SmsSyncFailureCategory? gateFailure,
    bool uploadRan = false,
    SmsSyncFailureCategory? uploadFailure,
    int uploaded = 0,
    int skippedNotOwned = 0,
  }) {
    var next = scanSucceeded
        ? _copy(lastScanSuccessAt: now, clearScanError: true)
        : _copy(lastScanError: scanError ?? 'scan_failed');

    if (!cloudControlled) {
      return next._copy(
        cloudState: SmsCloudSyncState.disabled,
        cloudCheckedAt: now,
        clearUnverified: true,
      );
    }
    if (gateState == null) return next; // scan failed before the gate ran

    next = next._copy(
      cloudState: gateState,
      cloudCheckedAt: now,
      cloudUnverifiedReason: gateState == SmsCloudSyncState.unverified
          ? (gateFailure ?? SmsSyncFailureCategory.unknown)
          : null,
      clearUnverified: gateState != SmsCloudSyncState.unverified,
    );

    if (gateState == SmsCloudSyncState.enabled && uploadRan) {
      // A run that wrote nothing while candidates were skipped as not owned
      // is a no-op, not an upload: "Last cloud upload" must not advance.
      final noOp = uploaded == 0 && skippedNotOwned > 0;
      next = uploadFailure == null
          ? next._copy(
              lastUploadSuccessAt: noOp ? null : now,
              consecutiveUploadFailures: 0,
              clearUploadFailure: true,
              lastUploadSkippedNotOwned: skippedNotOwned,
            )
          : next._copy(
              lastUploadFailure: uploadFailure,
              lastUploadFailureAt: now,
              consecutiveUploadFailures: consecutiveUploadFailures + 1,
            );
    }
    return next;
  }

  SmsSyncDiagnostics _copy({
    DateTime? lastAttemptAt,
    DateTime? lastScanSuccessAt,
    String? lastScanError,
    bool clearScanError = false,
    SmsCloudSyncState? cloudState,
    DateTime? cloudCheckedAt,
    SmsSyncFailureCategory? cloudUnverifiedReason,
    bool clearUnverified = false,
    DateTime? lastUploadSuccessAt,
    SmsSyncFailureCategory? lastUploadFailure,
    DateTime? lastUploadFailureAt,
    int? consecutiveUploadFailures,
    bool clearUploadFailure = false,
    int? lastUploadSkippedNotOwned,
  }) => SmsSyncDiagnostics(
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastScanSuccessAt: lastScanSuccessAt ?? this.lastScanSuccessAt,
    lastScanError: clearScanError
        ? null
        : (lastScanError ?? this.lastScanError),
    cloudState: cloudState ?? this.cloudState,
    cloudCheckedAt: cloudCheckedAt ?? this.cloudCheckedAt,
    cloudUnverifiedReason: clearUnverified
        ? null
        : (cloudUnverifiedReason ?? this.cloudUnverifiedReason),
    lastUploadSuccessAt: lastUploadSuccessAt ?? this.lastUploadSuccessAt,
    lastUploadFailure: clearUploadFailure
        ? null
        : (lastUploadFailure ?? this.lastUploadFailure),
    lastUploadFailureAt: clearUploadFailure
        ? null
        : (lastUploadFailureAt ?? this.lastUploadFailureAt),
    consecutiveUploadFailures:
        consecutiveUploadFailures ?? this.consecutiveUploadFailures,
    lastUploadSkippedNotOwned:
        lastUploadSkippedNotOwned ?? this.lastUploadSkippedNotOwned,
  );
}
