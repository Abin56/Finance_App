import 'dart:async';

import '../domain/account_card_matcher.dart';
import '../domain/sms_import_status.dart';
import '../domain/transaction_candidate_builder.dart';
import 'financial_event_dao.dart';
import 'sms_inbox_repository.dart';
import 'transaction_candidate_dao.dart';

/// Repairs pending SMS that were stored before the parser could read their
/// account last-4 (e.g. `A/cXX9585`): back-fills the last-4, then drops the
/// stale unmatched candidate and unconverted event so
/// [generateMissingTransactionCandidates] (and the event generator) rebuild
/// them against the user's accounts. Cloud sync then replaces the stale
/// "Not matched" document, because the rebuilt candidate has a different
/// identity (it now carries a last-4). Returns how many SMS were repaired.
///
/// When [matcher] is given it ALSO re-matches candidates that are still
/// unmatched (no account/card): a candidate is matched exactly once, when
/// built, so one built before the account existed, was edited, or finished
/// loading would otherwise stay "Not matched" forever — locally and on the
/// web. Only an unmatched candidate that now resolves is replaced; a matched
/// one is never touched. [matcher] is only invoked when something is
/// unmatched, and if it throws nothing is written.
Future<int> repairStaleAccountFields({
  required SmsInboxRepository inboxRepository,
  required TransactionCandidateDao candidateDao,
  FinancialEventDao? eventDao,
  FutureOr<AccountCardMatcher> Function()? matcher,
}) async {
  final repairedIds = await inboxRepository.reparseMissingAccountFields();
  if (repairedIds.isNotEmpty) {
    await candidateDao.deleteBySmsItemIds(repairedIds);
    await eventDao?.deleteUnconvertedForSmsIds(repairedIds);
  }

  var rematched = 0;
  if (matcher != null) {
    final unmatched = (await candidateDao.getAll())
        .where((c) => c.matchedAccountId == null && c.matchedCardId == null)
        .toList();
    if (unmatched.isNotEmpty) {
      final pending = {
        for (final item in await inboxRepository.getByStatus(
          SmsImportStatus.pending,
        ))
          item.id: item,
      };
      final stillUnmatched = unmatched
          .where((c) => pending[c.smsItemId]?.parsed != null)
          .toList();
      if (stillUnmatched.isNotEmpty) {
        final builder = TransactionCandidateBuilder(await matcher());
        final rematchedIds = <String>[];
        for (final candidate in stillUnmatched) {
          final rebuilt = builder.build(pending[candidate.smsItemId]!);
          if (rebuilt == null || rebuilt.matchedAccountId == null) continue;
          await candidateDao.deleteBySmsItemIds([candidate.smsItemId]);
          await candidateDao.upsert(rebuilt);
          rematchedIds.add(candidate.smsItemId);
        }
        await eventDao?.deleteUnconvertedForSmsIds(rematchedIds);
        rematched = rematchedIds.length;
      }
    }
  }
  return repairedIds.length + rematched;
}

/// Builds and persists a `TransactionCandidate` for every parsed, pending SMS
/// that doesn't have one yet, returning how many were built.
///
/// Shared by the SMS Inbox screen and the background `SmsScanWorker` run so
/// both produce identical candidates — before this was shared, only the
/// screen built them, so a background scan stored new SMS locally but had
/// nothing new to upload until the user opened SMS Inbox.
///
/// [matcher] is only invoked when there is something to build, so a run with
/// no new SMS never reads accounts/cards. If it throws, nothing is written:
/// a candidate built without real account data would keep a blank match
/// forever (existing rows are never rebuilt), so it is better to leave the
/// SMS for a later run.
Future<int> generateMissingTransactionCandidates({
  required SmsInboxRepository inboxRepository,
  required TransactionCandidateDao dao,
  required FutureOr<AccountCardMatcher> Function() matcher,
}) async {
  final alreadyBuilt = await dao.existingSmsItemIds();
  final pending = await inboxRepository.getByStatus(SmsImportStatus.pending);
  final toBuild = pending
      .where((item) => item.parsed != null && !alreadyBuilt.contains(item.id))
      .toList();
  if (toBuild.isEmpty) return 0;

  final builder = TransactionCandidateBuilder(await matcher());
  var built = 0;
  for (final item in toBuild) {
    final candidate = builder.build(item);
    if (candidate == null) continue;
    await dao.upsert(candidate);
    built++;
  }
  return built;
}
