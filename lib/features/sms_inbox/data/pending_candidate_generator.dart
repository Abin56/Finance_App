import 'dart:async';

import '../domain/account_card_matcher.dart';
import '../domain/sms_import_status.dart';
import '../domain/transaction_candidate_builder.dart';
import 'sms_inbox_repository.dart';
import 'transaction_candidate_dao.dart';

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
