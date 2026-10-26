import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/captured_uid_resolver.dart';
import '../data/sms_inbox_repository.dart';
import '../data/sms_transaction_candidate_repository.dart';
import '../data/transaction_candidate_dao.dart';
import '../domain/sms_candidate_cloud_identity.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_transaction_candidate_cloud.dart';
import '../domain/sms_transaction_direction.dart';

/// Where an in-flight [SmsCandidateCloudSync.sync] is. [total] is the real
/// number of upload targets, so a percentage derived from it is honest.
class SmsCandidateSyncProgress {
  const SmsCandidateSyncProgress({
    required this.total,
    required this.done,
    required this.uploaded,
    required this.skipped,
    required this.failed,
  });

  final int total;
  final int done;
  final int uploaded;

  /// Already in the cloud, or already imported/dismissed on the web.
  final int skipped;
  final int failed;
}

/// What one [SmsCandidateCloudSync.sync] call did — reported so a caller (or
/// a test) never has to guess, same transparency posture as
/// `SmsBulkConvertResult`.
class SmsCandidateSyncResult {
  const SmsCandidateSyncResult({
    required this.synced,
    required this.removed,
    this.skippedHandled = 0,
    this.skippedNotOwned = 0,
    this.failed = 0,
    this.alreadySynced = 0,
  });

  /// Targets whose cloud document already existed, so nothing was written.
  final int alreadySynced;

  /// Cloud documents created or overwritten this run.
  final int synced;

  /// Cloud documents deleted this run because their SMS is no longer
  /// pending/non-duplicate locally.
  final int removed;

  /// Local candidates that were NOT uploaded because a tombstone already
  /// existed for that id — the web app already imported or dismissed this
  /// exact candidate (Phase D, 2026-10-24). Zero whenever no
  /// `tombstoneCollection` was configured (pre-Phase-D call sites).
  final int skippedHandled;

  /// Pending, non-duplicate local candidates that were NOT upload targets
  /// because their `capturedForUid` is not the signed-in uid (unowned legacy
  /// rows, or rows bound to another account). They are deliberately never
  /// rebound or uploaded — but they are counted, so a run that uploaded
  /// nothing because everything was ineligible is never reported as a
  /// successful upload.
  final int skippedNotOwned;

  /// Upload targets whose write threw (offline, timeout, denied). Only ever
  /// non-zero when [SmsCandidateCloudSync.sync] was called with
  /// `continueOnUploadError: true`; otherwise the first failure throws.
  /// Local rows are untouched either way, so a later run retries them.
  final int failed;
}

/// Keeps `users/{uid}/smsTransactionCandidates` mirroring exactly the local
/// candidates that still need a decision — never more, never less.
///
/// A cloud document exists for an SMS if and only if that SMS is currently
/// [SmsImportStatus.pending] and not a flagged duplicate locally. This is
/// the "derive cloud status from existing local state" choice documented on
/// [SmsTransactionCandidateCloud]: no `candidateStatus` field, no second
/// lifecycle to keep in sync with `SmsInboxItem.status` — existence *is* the
/// status. Once the user converts, ignores, or the dedup rules flag an SMS
/// as a duplicate, its cloud candidate (if any) is deleted on the next sync,
/// because there is nothing left to review.
///
/// Idempotent by construction: [SmsTransactionCandidateCloud.id] is the
/// stable local `SmsInboxItem.id`, so re-uploading the same candidate is
/// always an overwrite of the same document, never a duplicate — see
/// `SmsTransactionCandidateRepository`.
///
/// Takes its repositories directly rather than a `Ref`, mirroring
/// `SmsBulkConverter` — plain, driveable logic with no widget/provider scope
/// needed to test it. Never touches local storage: a failure partway
/// through (a `permanentlyDelete`/`add` call throwing) leaves every local
/// `SmsInboxItem`/`TransactionCandidate` exactly as it was, so the caller's
/// try/catch can swallow it without any risk to local data — see
/// `SmsInboxItemsNotifier._syncCandidatesToCloud`.
///
/// UID ISOLATION (Phase C, 2026-10-24): [_cloudRepository] is already scoped
/// to one Firebase user's own `smsTransactionCandidates` path by whoever
/// constructs it (the signed-in user's own collection reference) — but the
/// local `sms_inbox`/`sms_transaction_candidates` tables are device-wide,
/// not partitioned per user. Without an explicit check, a device that had
/// User A signed in, captured some SMS, then switched to User B would
/// upload User A's still-pending candidates into User B's Firestore path the
/// next time this ran. [capturedUidResolver] closes that: a local candidate
/// is only ever a sync target when its `SmsInboxItem.capturedForUid` equals
/// the uid [capturedUidResolver] returns right now, and a `null` on either
/// side (unowned legacy row, or nobody currently signed in) never matches —
/// `null == null` is deliberately NOT treated as a match. An already-synced
/// cloud candidate that no longer matches (the signed-in user changed since
/// it was uploaded) is removed by the existing [toRemove] step below exactly
/// like any other "no longer a valid target" candidate — it was never a
/// correct cross-account upload to begin with.
class SmsCandidateCloudSync {
  const SmsCandidateCloudSync(
    this._cloudRepository,
    this._localDao,
    this._inboxRepository, {
    this.capturedUidResolver = defaultCapturedUidResolver,
    this.tombstoneCollection,
  });

  final SmsTransactionCandidateRepository _cloudRepository;
  final TransactionCandidateDao _localDao;
  final SmsInboxRepository _inboxRepository;

  /// Who this sync call is uploading on behalf of — see the class doc.
  /// Overridable in tests; production code always uses the real
  /// [defaultCapturedUidResolver] default.
  final CapturedUidResolver capturedUidResolver;

  /// `users/{uid}/smsCandidateTombstones`, same uid scope as
  /// [_cloudRepository]'s own collection — the Phase D tombstone-awareness
  /// this class was missing (see §2/§3 of
  /// `docs/sms-background-cloud-sync-architecture.md`). `null` at any call
  /// site (none of the pre-Phase-D ones were updated to pass one) falls
  /// back to the old, unconditional-overwrite upload — see
  /// [_uploadUnlessHandled]'s doc comment for exactly why that's still safe,
  /// not merely "not yet migrated."
  final CollectionReference<Map<String, dynamic>>? tombstoneCollection;

  /// [continueOnUploadError] keeps going past a failed candidate write and
  /// counts it in [SmsCandidateSyncResult.failed] instead of throwing — used
  /// by the explicit historical recovery so it can report real per-item
  /// counts. [uploadTimeout] bounds each write (Firestore transactions can
  /// stall offline); a timed-out write counts as failed and is safe to retry
  /// because the document id is deterministic.
  Future<SmsCandidateSyncResult> sync({
    bool continueOnUploadError = false,
    Duration? uploadTimeout,

    /// Live progress for the phone's own UI and FlowFi Web's presence:
    /// called once the targets are counted (`done == 0`) and after each one.
    void Function(SmsCandidateSyncProgress progress)? onProgress,
  }) async {
    final currentUid = capturedUidResolver();
    final items = await _inboxRepository.getAll();
    final itemById = {for (final item in items) item.id: item};

    final localCandidates = await _localDao.getAll();
    final pendingCandidates = localCandidates.where((candidate) {
      final item = itemById[candidate.smsItemId];
      return item != null &&
          item.status == SmsImportStatus.pending &&
          !item.isDuplicate;
    }).toList();
    final targetCandidates = pendingCandidates
        .where(
          (candidate) =>
              currentUid != null &&
              itemById[candidate.smsItemId]!.capturedForUid == currentUid,
        )
        .toList();
    final skippedNotOwned = pendingCandidates.length - targetCandidates.length;

    // Built from each target's OWN cloud identity (Phase F1,
    // 2026-10-24) — not raw `smsItemId` — because a reference-numbered
    // candidate's document id is content-derived and may differ from its
    // local row id. Comparing against raw local ids here would make this
    // method wrongly treat a still-pending, already-uploaded candidate as
    // "no longer a valid target" and delete it every single sync.
    //
    // [_legacyV1IdIfApplicable] is computed alongside every V2 doc — see
    // [_uploadUnlessHandled]'s versioned-compatibility doc comment (V1/V2
    // hardening, 2026-10-24) for why both are checked together before a
    // write.
    final targets = [
      for (final candidate in targetCandidates)
        (
          cloudDoc: SmsTransactionCandidateCloud.fromLocal(
            candidate,
            sender: itemById[candidate.smsItemId]!.rawMessage.address,
            rawLastFour:
                itemById[candidate.smsItemId]!.parsed?.maskedAccountOrCard,
          ),
          legacyV1Id: _legacyV1IdIfApplicable(
            sender: itemById[candidate.smsItemId]!.rawMessage.address,
            referenceNumber: candidate.referenceNumber,
            amount: candidate.amount,
            direction: candidate.direction,
          ),
        ),
    ];
    // Includes each target's `legacyV1Id` too (when present) — otherwise
    // this removal step would delete a still-relevant V1 document out from
    // under `_uploadUnlessHandled`'s own V1-compatibility check below,
    // before it ever runs. A V1 document for a still-pending local
    // candidate is a valid target exactly as much as its V2 counterpart —
    // this sync() intentionally leaves it alone rather than migrating or
    // deleting it (see `_uploadUnlessHandled`'s doc comment).
    final targetCloudIds = {
      for (final target in targets) ...[
        target.cloudDoc.id,
        if (target.legacyV1Id != null) target.legacyV1Id!,
      ],
    };

    final existingCloud = await _cloudRepository.getAll();
    final toRemove = existingCloud.where(
      (doc) => !targetCloudIds.contains(doc.id),
    );
    for (final doc in toRemove) {
      await _cloudRepository.deleteById(doc.id);
    }

    var uploaded = 0;
    var skippedHandled = 0;
    var alreadySynced = 0;
    var failed = 0;
    var consecutiveFailures = 0;
    final existingIds = {for (final doc in existingCloud) doc.id};
    void progress(int done) => onProgress?.call(
      SmsCandidateSyncProgress(
        total: targets.length,
        done: done,
        uploaded: uploaded,
        skipped: skippedHandled + alreadySynced,
        failed: failed,
      ),
    );
    progress(0);
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      // Already in the cloud (same stable id): nothing to send. This is what
      // makes a repeat scan — every app open — cheap, and an interrupted
      // initial sync resumable: only what's missing is uploaded.
      if (existingIds.contains(target.cloudDoc.id) ||
          (target.legacyV1Id != null &&
              existingIds.contains(target.legacyV1Id))) {
        alreadySynced++;
        progress(i + 1);
        continue;
      }
      try {
        var write = _uploadUnlessHandled(
          target.cloudDoc,
          legacyV1Id: target.legacyV1Id,
        );
        if (uploadTimeout != null) write = write.timeout(uploadTimeout);
        if (await write) {
          uploaded++;
        } else {
          skippedHandled++;
        }
        consecutiveFailures = 0;
      } catch (_) {
        if (!continueOnUploadError) rethrow;
        failed++;
        // Connection most likely lost: stop instead of timing out on every
        // remaining item. The rest are reported failed, not attempted.
        if (++consecutiveFailures >= 3) {
          failed += targets.length - i - 1;
          progress(targets.length);
          break;
        }
      }
      progress(i + 1);
    }

    return SmsCandidateSyncResult(
      synced: uploaded,
      removed: toRemove.length,
      skippedHandled: skippedHandled,
      alreadySynced: alreadySynced,
      skippedNotOwned: skippedNotOwned,
      failed: failed,
    );
  }

  /// The V1-formula id for this candidate, or `null` when V1 and V2 would
  /// compute the exact same id anyway (no reference number — both fall
  /// back to the same `legacyPerDeviceId`, so there is nothing separate to
  /// check). `null` here means "no distinct legacy id to consult," not "no
  /// legacy risk" — see [_uploadUnlessHandled].
  String? _legacyV1IdIfApplicable({
    required String sender,
    required String? referenceNumber,
    required double amount,
    required SmsTransactionDirection direction,
  }) {
    if (referenceNumber == null || referenceNumber.trim().isEmpty) return null;
    return SmsCandidateCloudIdentity.forReferencedTransactionV1(
      sender: sender,
      referenceNumber: referenceNumber,
      amount: amount,
      direction: direction,
    );
  }

  /// Writes [cloudDoc] (at its V2 id) unless EITHER its own V2 tombstone
  /// exists, OR — when [legacyV1Id] is given — the legacy V1 tombstone or a
  /// legacy V1 candidate document already exists for the same underlying
  /// transaction. Returns `true` if the V2 doc was written, `false` if
  /// skipped as already handled (V1 or V2) or already present as a legacy
  /// V1 document.
  ///
  /// VERSIONED COMPATIBILITY (Phase F1 hardening, 2026-10-24): V2 narrowed
  /// V1's collision formula by adding the masked account/card last-4 (see
  /// `SmsCandidateCloudIdentity`), which means a candidate already
  /// handled — or already uploaded — under V1's id would NOT be found by a
  /// V2-only tombstone/candidate check, because V1 and V2 compute different
  /// ids for the same reference-numbered transaction. [legacyV1Id] (built by
  /// [sync] from the SAME local candidate, via
  /// `SmsCandidateCloudIdentity.forReferencedTransactionV1`) closes that
  /// gap: this method never writes a V2 document for a transaction that
  /// already has EITHER a V1 tombstone OR a still-existing V1 candidate
  /// document, satisfying "do not create duplicate V1/V2 candidates for the
  /// same transaction" without ever touching, deleting, or migrating the V1
  /// document itself — it is simply left exactly as it was. `null` means
  /// "V1 and V2 compute the same id for this candidate" (the no-reference-
  /// number conservative-fallback case), so there is nothing distinct to
  /// check.
  ///
  /// RACE-SAFE BY CONSTRUCTION, not merely "checked first": every read
  /// above and the candidate write happen inside ONE `runTransaction`, so
  /// Firestore's own optimistic-concurrency guarantee — "if a document read
  /// during a transaction is modified by another client while the
  /// transaction is in flight, the transaction is retried" — applies to
  /// every one of those reads, not just the V2 tombstone. If the web app's
  /// own atomic delete+tombstone batch (`markHandled`) commits a V2
  /// tombstone while this transaction is in flight, this transaction is
  /// forced to retry, re-read the now-existing tombstone, and abort the
  /// write — exactly the guarantee
  /// `docs/sms-background-cloud-sync-architecture.md` §2 called for, now
  /// extended to cover the V1 reads too. This is the same mechanism (not
  /// merely the same intent) the web side's `firestore.rules`
  /// `!exists(tombstone)` guard on `create` backs up server-side for the V2
  /// id specifically — belt and suspenders, not two different stories; see
  /// this class's own review notes for why the rule does not need to know
  /// about the V1 id (nothing is ever newly created AT a V1 id).
  ///
  /// When [tombstoneCollection] is `null` (a pre-Phase-D call site that
  /// never opted in), this falls back to the original unconditional
  /// overwrite, ignoring [legacyV1Id] entirely. That remains safe for
  /// exactly the reason background upload stayed off
  /// until now: the ONLY caller of this method in production is the
  /// foreground `SmsCandidateCloudSync.sync()` path, which a human is
  /// actively looking at (they just opened the SMS Inbox screen) — the
  /// resurrection risk this transaction closes is specifically the
  /// UNATTENDED background path, which never calls this method at all
  /// without a configured [tombstoneCollection] (see
  /// `sms_background_entry.dart`).
  Future<bool> _uploadUnlessHandled(
    SmsTransactionCandidateCloud cloudDoc, {
    String? legacyV1Id,
  }) async {
    final tombstones = tombstoneCollection;
    if (tombstones == null) {
      await _cloudRepository.add(cloudDoc.id, cloudDoc);
      return true;
    }

    final firestore = _cloudRepository.collection.firestore;
    final candidateRef = _cloudRepository.collection.doc(cloudDoc.id);
    final tombstoneRef = tombstones.doc(cloudDoc.id);
    // Only genuinely distinct from the V2 refs when `legacyV1Id` is
    // non-null and differs from `cloudDoc.id` — see this method's doc
    // comment for when that's the case.
    final legacyCandidateRef = legacyV1Id == null
        ? null
        : _cloudRepository.collection.doc(legacyV1Id);
    final legacyTombstoneRef = legacyV1Id == null
        ? null
        : tombstones.doc(legacyV1Id);

    var wroteCandidate = false;
    await firestore.runTransaction((tx) async {
      final tombstoneSnapshot = await tx.get(tombstoneRef);
      if (tombstoneSnapshot.exists) {
        wroteCandidate = false;
        return;
      }
      if (legacyTombstoneRef != null) {
        final legacyTombstoneSnapshot = await tx.get(legacyTombstoneRef);
        if (legacyTombstoneSnapshot.exists) {
          wroteCandidate = false;
          return;
        }
      }
      if (legacyCandidateRef != null) {
        final legacyCandidateSnapshot = await tx.get(legacyCandidateRef);
        if (legacyCandidateSnapshot.exists) {
          // A V1 document for this exact transaction is already live —
          // writing a second, V2-id document would duplicate it, not
          // replace it (they're different document ids). Leave the V1
          // document exactly as it is; nothing here deletes or migrates
          // it. The next sync() naturally stops re-attempting this once
          // the V1 row's own lifecycle (import/dismiss) removes it.
          wroteCandidate = false;
          return;
        }
      }
      tx.set(candidateRef, cloudDoc);
      wroteCandidate = true;
    });
    return wroteCandidate;
  }
}
