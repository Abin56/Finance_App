import '../data/sms_inbox_repository.dart';
import '../data/sms_transaction_candidate_repository.dart';
import '../data/transaction_candidate_dao.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_transaction_candidate_cloud.dart';

/// What one [SmsCandidateCloudSync.sync] call did — reported so a caller (or
/// a test) never has to guess, same transparency posture as
/// `SmsBulkConvertResult`.
class SmsCandidateSyncResult {
  const SmsCandidateSyncResult({required this.synced, required this.removed});

  /// Cloud documents created or overwritten this run.
  final int synced;

  /// Cloud documents deleted this run because their SMS is no longer
  /// pending/non-duplicate locally.
  final int removed;
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
class SmsCandidateCloudSync {
  const SmsCandidateCloudSync(
    this._cloudRepository,
    this._localDao,
    this._inboxRepository,
  );

  final SmsTransactionCandidateRepository _cloudRepository;
  final TransactionCandidateDao _localDao;
  final SmsInboxRepository _inboxRepository;

  Future<SmsCandidateSyncResult> sync() async {
    final items = await _inboxRepository.getAll();
    final itemById = {for (final item in items) item.id: item};

    final localCandidates = await _localDao.getAll();
    final targetCandidates = localCandidates.where((candidate) {
      final item = itemById[candidate.smsItemId];
      return item != null &&
          item.status == SmsImportStatus.pending &&
          !item.isDuplicate;
    }).toList();
    final targetIds = targetCandidates.map((c) => c.smsItemId).toSet();

    final existingCloud = await _cloudRepository.getAll();
    final toRemove = existingCloud.where((doc) => !targetIds.contains(doc.id));
    for (final doc in toRemove) {
      await _cloudRepository.deleteById(doc.id);
    }

    for (final candidate in targetCandidates) {
      final rawLastFour =
          itemById[candidate.smsItemId]!.parsed?.maskedAccountOrCard;
      final cloudDoc = SmsTransactionCandidateCloud.fromLocal(
        candidate,
        rawLastFour: rawLastFour,
      );
      await _cloudRepository.add(cloudDoc.id, cloudDoc);
    }

    return SmsCandidateSyncResult(
      synced: targetCandidates.length,
      removed: toRemove.length,
    );
  }
}
