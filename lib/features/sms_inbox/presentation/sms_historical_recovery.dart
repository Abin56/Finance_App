import '../data/captured_uid_resolver.dart';
import '../data/sms_inbox_repository.dart';
import '../data/transaction_candidate_dao.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_inbox_item.dart';
import 'sms_candidate_cloud_sync.dart';

/// Ids of the SMS rows the one-time historical recovery may bind: pending,
/// not a flagged duplicate, not bound to ANY account yet, and backed by a
/// local review candidate (otherwise there is nothing to upload). Rows owned
/// by another account are never eligible. Pure.
List<String> smsRecoveryEligibleIds(
  Iterable<SmsInboxItem> items,
  Set<String> candidateSmsItemIds,
) => [
  for (final item in items)
    if (item.status == SmsImportStatus.pending &&
        !item.isDuplicate &&
        item.capturedForUid == null &&
        candidateSmsItemIds.contains(item.id))
      item.id,
];

enum SmsRecoveryOutcome {
  /// Rows bound (if any) and every upload target attempted.
  completed,

  /// Nobody is signed in right now — nothing was changed.
  notSignedIn,

  /// The signed-in account is not the one the user confirmed — nothing was
  /// changed.
  accountChanged,

  /// Rows were bound locally, but the cloud could not be reached, so no
  /// upload was attempted. Safe to retry.
  offline,
}

/// What one [SmsHistoricalRecovery.run] actually did. Counts only.
class SmsHistoricalRecoveryResult {
  const SmsHistoricalRecoveryResult({
    required this.outcome,
    this.linked = 0,
    this.uploaded = 0,
    this.alreadyHandled = 0,
    this.notLinked = 0,
    this.failed = 0,
  });

  final SmsRecoveryOutcome outcome;

  /// Rows newly bound to the account this run (0 on a repeat run).
  final int linked;

  /// Cloud candidate documents written this run.
  final int uploaded;

  /// Skipped because the web already imported/dismissed them (tombstone, V1
  /// or V2) or a legacy V1 document already exists.
  final int alreadyHandled;

  /// Pending candidates still not bound to this account (e.g. owned by
  /// another account). Never uploaded.
  final int notLinked;

  /// Upload attempts that failed; the rows stay bound and pending locally,
  /// so running recovery again retries exactly these.
  final int failed;

  /// True only when at least one document was really written. A run that
  /// uploaded nothing is never a successful upload.
  bool get didUpload => uploaded > 0;

  /// Whether running again could still achieve something.
  bool get canRetry =>
      outcome == SmsRecoveryOutcome.offline ||
      (outcome == SmsRecoveryOutcome.completed && failed > 0);
}

/// Plain-language summary for the user — counts only, and never calls a
/// run that wrote nothing an upload.
String describeSmsRecoveryResult(SmsHistoricalRecoveryResult r) {
  String n(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';
  switch (r.outcome) {
    case SmsRecoveryOutcome.notSignedIn:
      return 'You are not signed in. Nothing was changed.';
    case SmsRecoveryOutcome.accountChanged:
      return 'The signed-in account changed. Nothing was changed.';
    case SmsRecoveryOutcome.offline:
      return [
        if (r.linked > 0)
          'Linked ${n(r.linked, 'message', 'messages')} to this account.',
        "Couldn't reach FlowFi cloud, so nothing was uploaded. "
            'Try again when you are online.',
      ].join(' ');
    case SmsRecoveryOutcome.completed:
      return [
        if (r.linked > 0)
          'Linked ${n(r.linked, 'message', 'messages')} to this account.',
        r.didUpload
            ? 'Uploaded ${n(r.uploaded, 'candidate', 'candidates')} to '
                  'Transaction Inbox.'
            : 'Nothing was uploaded.',
        if (r.alreadyHandled > 0)
          'Skipped ${r.alreadyHandled} already imported or dismissed on '
              'the web.',
        if (r.failed > 0)
          '${n(r.failed, 'upload', 'uploads')} failed — tap Retry upload.',
        if (r.notLinked > 0)
          'Left ${r.notLinked} not linked to this account untouched.',
      ].join(' ');
  }
}

/// One-time, user-confirmed recovery of SMS candidates captured before
/// ownership binding existed (all `captured_for_uid` NULL).
///
/// Safety properties:
///  * binds only rows the SQL guard in [SmsInboxDao.claimUnowned] still sees
///    as unowned + pending + non-duplicate — another account's rows can never
///    be reassigned, and a repeat run binds nothing new;
///  * binds only to [run]'s `confirmedUid`, and only if that is still the
///    signed-in account at the moment of binding;
///  * uploads through the existing tombstone-aware, V1/V2-aware
///    [SmsCandidateCloudSync] — nothing here writes Firestore directly;
///  * never deletes or rewrites local SMS data beyond `captured_for_uid`, and
///    never creates financial transactions.
class SmsHistoricalRecovery {
  const SmsHistoricalRecovery(
    this._inboxRepository,
    this._candidateDao, {
    required this.cloudSyncFor,
    required this.isCloudReachable,
    this.capturedUidResolver = defaultCapturedUidResolver,
    this.uploadTimeout = const Duration(seconds: 20),
  });

  final SmsInboxRepository _inboxRepository;
  final TransactionCandidateDao _candidateDao;

  /// Builds a sync scoped to `users/{uid}/...` for exactly this uid.
  final SmsCandidateCloudSync Function(String uid) cloudSyncFor;

  /// A fresh server read for this uid; `false` means offline/unverifiable.
  final Future<bool> Function(String uid) isCloudReachable;

  final CapturedUidResolver capturedUidResolver;
  final Duration uploadTimeout;

  Future<List<String>> eligibleIds() async {
    final items = await _inboxRepository.getAll();
    final candidateIds = {
      for (final c in await _candidateDao.getAll()) c.smsItemId,
    };
    return smsRecoveryEligibleIds(items, candidateIds);
  }

  Future<SmsHistoricalRecoveryResult> run(String confirmedUid) async {
    final current = capturedUidResolver();
    if (current == null) {
      return const SmsHistoricalRecoveryResult(
        outcome: SmsRecoveryOutcome.notSignedIn,
      );
    }
    if (current != confirmedUid) {
      return const SmsHistoricalRecoveryResult(
        outcome: SmsRecoveryOutcome.accountChanged,
      );
    }

    final linked = await _inboxRepository.claimUnowned(
      await eligibleIds(),
      confirmedUid,
    );

    if (!await isCloudReachable(confirmedUid)) {
      return SmsHistoricalRecoveryResult(
        outcome: SmsRecoveryOutcome.offline,
        linked: linked,
      );
    }

    final SmsCandidateSyncResult result;
    try {
      result = await cloudSyncFor(confirmedUid).sync(
        continueOnUploadError: true,
        uploadTimeout: uploadTimeout,
      );
    } catch (_) {
      // Listing/cleaning the cloud collection failed before any upload.
      return SmsHistoricalRecoveryResult(
        outcome: SmsRecoveryOutcome.offline,
        linked: linked,
      );
    }
    return SmsHistoricalRecoveryResult(
      outcome: SmsRecoveryOutcome.completed,
      linked: linked,
      uploaded: result.synced,
      alreadyHandled: result.skippedHandled,
      notLinked: result.skippedNotOwned,
      failed: result.failed,
    );
  }
}
