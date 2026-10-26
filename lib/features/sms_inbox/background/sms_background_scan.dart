import 'dart:async';

import '../data/sms_inbox_repository.dart';
import '../domain/sms_read_exception.dart';
import '../domain/sms_sync_diagnostics.dart';
import '../presentation/sms_candidate_cloud_sync.dart';

/// Result of one background scan (and, since Phase D, the upload attempt
/// that may follow it), reported back to the native worker.
class SmsBackgroundScanResult {
  const SmsBackgroundScanResult.success(
    this.newItems, {
    this.uploaded = 0,
    this.uploadSkippedHandled = 0,
    this.uploadSkippedNotOwned = 0,
    this.uploadError,
    this.uploadFailure,
  }) : success = true,
       error = null;
  const SmsBackgroundScanResult.failure(this.error)
    : success = false,
      newItems = 0,
      uploaded = 0,
      uploadSkippedHandled = 0,
      uploadSkippedNotOwned = 0,
      uploadError = null,
      uploadFailure = null;

  final bool success;
  final int newItems;

  /// Short machine code ("permission" / "scan_failed") — never message text
  /// or an exception message, which could echo SMS content.
  final String? error;

  /// Candidates uploaded to Firestore this run — always `0` while
  /// the runtime upload switch is off (the upload step is never
  /// even attempted; see [runBackgroundSmsScan]'s `cloudSyncBuilder` param).
  final int uploaded;

  /// Candidates NOT uploaded because a tombstone already existed for that
  /// id (already handled on the web) — see `SmsCandidateCloudSync`.
  final int uploadSkippedHandled;

  /// Pending candidates left out of the upload because they are not bound to
  /// the signed-in uid — see `SmsCandidateSyncResult.skippedNotOwned`.
  final int uploadSkippedNotOwned;

  /// Short machine code for an upload-step failure ("upload_failed") —
  /// never swallowed into [error], because a scan can succeed (new SMS were
  /// captured locally, which is the part that must never be lost) even
  /// while the separate, best-effort upload step fails.
  final String? uploadError;

  /// Privacy-safe category for [uploadError] (never an exception message).
  final SmsSyncFailureCategory? uploadFailure;

  Map<String, Object?> toMap() => {
    'success': success,
    'newItems': newItems,
    'error': error,
    'uploaded': uploaded,
    'uploadSkippedHandled': uploadSkippedHandled,
    'uploadSkippedNotOwned': uploadSkippedNotOwned,
    'uploadError': uploadError,
    'uploadFailure': uploadFailure?.code,
  };
}

/// Runs the same `scanInbox()` a manual scan runs — identical filter, bank
/// parsers and dedup — and nothing else, UNLESS [cloudSyncBuilder] is
/// provided (Phase D): the scan itself still never touches Firestore, but
/// after it succeeds, [cloudSyncBuilder] is asked to build a
/// `SmsCandidateCloudSync` scoped to a verified signed-in uid and `sync()`
/// is attempted as a separate, best-effort step.
///
/// `cloudSyncBuilder` is `null` in production today
/// (runtime switch off by default — see `sms_background_entry
/// .dart`, which is the only real caller), so this still behaves exactly as
/// it always has: local-capture-only, no Firestore, no candidate upload, no
/// financial records. The parameter exists (rather than the upload call
/// being hardcoded here) so `sms_background_entry.dart` — the one place
/// that knows whether a verified uid is actually available in THIS isolate
/// — decides whether an attempt is even worth making, not this function.
///
/// A scan success is reported even if the upload step throws: local capture
/// (newItems) is never put at risk by a Firestore problem, and the two are
/// always surfaced as separate fields rather than one conflated boolean.
Future<SmsBackgroundScanResult> runBackgroundSmsScan(
  SmsInboxRepository repository, {
  FutureOr<SmsCandidateCloudSync?> Function()? cloudSyncBuilder,
  void Function(SmsCandidateSyncProgress progress)? onUploadProgress,
}) async {
  int newItems;
  try {
    newItems = await repository.scanInbox();
  } on SmsPermissionUnavailableException {
    return const SmsBackgroundScanResult.failure('permission');
  } catch (_) {
    return const SmsBackgroundScanResult.failure('scan_failed');
  }

  if (cloudSyncBuilder == null) {
    return SmsBackgroundScanResult.success(newItems);
  }

  // The builder reads the runtime upload switch. If it throws, upload is
  // simply not attempted (fail closed) — never an upload, never a scan failure.
  SmsCandidateCloudSync? cloudSync;
  try {
    cloudSync = await cloudSyncBuilder();
  } catch (_) {
    return SmsBackgroundScanResult.success(newItems);
  }
  if (cloudSync == null) {
    // No verified uid available in this isolate (signed out, Auth
    // unavailable, or Firebase never initialized) — upload is simply never
    // attempted. Not an error: local capture already succeeded above.
    return SmsBackgroundScanResult.success(newItems);
  }

  try {
    final syncResult = await cloudSync.sync(onProgress: onUploadProgress);
    return SmsBackgroundScanResult.success(
      newItems,
      uploaded: syncResult.synced,
      uploadSkippedHandled: syncResult.skippedHandled,
      uploadSkippedNotOwned: syncResult.skippedNotOwned,
    );
  } catch (error) {
    // The scan already succeeded and is reported as such — only the upload
    // half failed. WorkManager's own retry/backoff (native side) covers
    // transient network/permission failures on the NEXT scheduled run;
    // nothing here needs its own retry loop.
    return SmsBackgroundScanResult.success(
      newItems,
      uploadError: 'upload_failed',
      uploadFailure: classifySmsSyncFailure(error),
    );
  }
}
