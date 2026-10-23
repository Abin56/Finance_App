import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/captured_uid_resolver.dart';
import '../data/sms_inbox_repository.dart';
import '../data/sms_transaction_candidate_repository.dart';
import '../data/transaction_candidate_dao.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_transaction_candidate_cloud.dart';

/// What one [SmsCandidateCloudSync.sync] call did — reported so a caller (or
/// a test) never has to guess, same transparency posture as
/// `SmsBulkConvertResult`.
class SmsCandidateSyncResult {
  const SmsCandidateSyncResult({
    required this.synced,
    required this.removed,
    this.skippedHandled = 0,
  });

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

  Future<SmsCandidateSyncResult> sync() async {
    final currentUid = capturedUidResolver();
    final items = await _inboxRepository.getAll();
    final itemById = {for (final item in items) item.id: item};

    final localCandidates = await _localDao.getAll();
    final targetCandidates = localCandidates.where((candidate) {
      final item = itemById[candidate.smsItemId];
      return item != null &&
          item.status == SmsImportStatus.pending &&
          !item.isDuplicate &&
          currentUid != null &&
          item.capturedForUid == currentUid;
    }).toList();
    final targetIds = targetCandidates.map((c) => c.smsItemId).toSet();

    final existingCloud = await _cloudRepository.getAll();
    final toRemove = existingCloud.where((doc) => !targetIds.contains(doc.id));
    for (final doc in toRemove) {
      await _cloudRepository.deleteById(doc.id);
    }

    var uploaded = 0;
    var skippedHandled = 0;
    for (final candidate in targetCandidates) {
      final rawLastFour =
          itemById[candidate.smsItemId]!.parsed?.maskedAccountOrCard;
      final cloudDoc = SmsTransactionCandidateCloud.fromLocal(
        candidate,
        rawLastFour: rawLastFour,
      );
      if (await _uploadUnlessHandled(cloudDoc)) {
        uploaded++;
      } else {
        skippedHandled++;
      }
    }

    return SmsCandidateSyncResult(
      synced: uploaded,
      removed: toRemove.length,
      skippedHandled: skippedHandled,
    );
  }

  /// Writes [cloudDoc] unless a tombstone already exists for its id —
  /// returns `true` if it was written, `false` if skipped as already
  /// handled.
  ///
  /// RACE-SAFE BY CONSTRUCTION, not merely "checked first": the tombstone
  /// read and the candidate write happen inside one `runTransaction`, so
  /// Firestore's own optimistic-concurrency guarantee — "if a document read
  /// during a transaction is modified by another client while the
  /// transaction is in flight, the transaction is retried" — applies to the
  /// tombstone read itself. If the web app's own atomic delete+tombstone
  /// batch (`markHandled`) commits while this transaction is in flight, this
  /// transaction is forced to retry, re-read the now-existing tombstone, and
  /// abort the write — exactly the guarantee
  /// `docs/sms-background-cloud-sync-architecture.md` §2 called for. This is
  /// the same mechanism (not merely the same intent) the web side's
  /// `firestore.rules` `!exists(tombstone)` guard on `create` backs up
  /// server-side — belt and suspenders, not two different stories.
  ///
  /// When [tombstoneCollection] is `null` (a pre-Phase-D call site that
  /// never opted in), this falls back to the original unconditional
  /// overwrite. That remains safe for exactly the reason
  /// `kSmsAutoSyncCloudUploadEnabled` stayed `false` until now: the ONLY
  /// caller of this method in production is the foreground
  /// `SmsCandidateCloudSync.sync()` path, which a human is actively looking
  /// at (they just opened the SMS Inbox screen) — the resurrection risk this
  /// transaction closes is specifically the UNATTENDED background path,
  /// which never calls this method at all without a configured
  /// [tombstoneCollection] (see `sms_background_entry.dart`).
  Future<bool> _uploadUnlessHandled(SmsTransactionCandidateCloud cloudDoc) async {
    final tombstones = tombstoneCollection;
    if (tombstones == null) {
      await _cloudRepository.add(cloudDoc.id, cloudDoc);
      return true;
    }

    final firestore = _cloudRepository.collection.firestore;
    final candidateRef = _cloudRepository.collection.doc(cloudDoc.id);
    final tombstoneRef = tombstones.doc(cloudDoc.id);

    var wroteCandidate = false;
    await firestore.runTransaction((tx) async {
      final tombstoneSnapshot = await tx.get(tombstoneRef);
      if (tombstoneSnapshot.exists) {
        wroteCandidate = false;
        return;
      }
      tx.set(candidateRef, cloudDoc);
      wroteCandidate = true;
    });
    return wroteCandidate;
  }
}
