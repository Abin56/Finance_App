import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transactions/domain/transaction_type.dart';
import '../data/merchant_memory_repository.dart';
import '../data/sms_inbox_repository.dart';
import '../domain/sms_prefill.dart';
import 'providers/sms_inbox_providers.dart';

/// Runs [action] — the "mark this SMS imported" step — swallowing any
/// failure instead of letting it propagate.
///
/// Every SMS conversion target (Add Expense, Money Received, Transfer,
/// Bill/EMI/Loan payment, Split/Assign Expense, and bulk convert) used to
/// run this step *inside* the same `try` block that guarded the actual
/// financial save. That meant a failure here — after the real record
/// already existed — surfaced as "Could not save" (single-convert) or
/// counted the row as `failed` (bulk convert), both of which invite a user
/// retry that creates a second, duplicate record from the same SMS. This is
/// the one place that failure mode is fixed for every caller: [action]'s
/// exception is caught and logged, never rethrown.
Future<void> _swallowLinkingFailure(String smsId, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    debugPrint('SMS import linking failed for SMS $smsId: $e');
  }
}

/// Riverpod entry point for the single-convert screens/sheets — marks
/// [smsPrefill]'s SMS imported via [smsInboxItemsProvider] (so the inbox
/// list UI refreshes) and, when [learnCategoryType]/[learnCategoryId] are
/// given, records the merchant→category choice via [merchantMemoriesProvider].
/// Callers must only call this after their own save has genuinely
/// succeeded — same contract `SmsInboxRepository.markImported` documents.
/// No-ops when [smsPrefill] is null (a plain, non-SMS entry).
Future<void> completeSmsImport(
  WidgetRef ref, {
  required SmsPrefill? smsPrefill,
  required String linkedEntityId,
  String? linkedEntityRoute,
  TransactionType? learnCategoryType,
  String? learnCategoryId,
}) async {
  if (smsPrefill == null) return;
  await _swallowLinkingFailure(smsPrefill.smsId, () async {
    await ref.read(smsInboxItemsProvider.notifier).markImported(
          smsPrefill.smsId,
          linkedEntityId: linkedEntityId,
          linkedEntityRoute: linkedEntityRoute,
        );
    if (learnCategoryType != null && learnCategoryId != null) {
      await ref.read(merchantMemoriesProvider.notifier).record(
            merchant: smsPrefill.merchantOrSender,
            transactionType: learnCategoryType,
            categoryId: learnCategoryId,
          );
    }
  });
}

/// Repository-level equivalent of [completeSmsImport] for callers that
/// don't have a [WidgetRef] — currently `SmsBulkConverter`, which holds its
/// repositories directly so its conversion loop stays plain, testable logic.
Future<void> linkSmsImportViaRepositories({
  required SmsInboxRepository inboxRepository,
  required MerchantMemoryRepository memoryRepository,
  required String smsId,
  required String linkedEntityId,
  String? merchant,
  TransactionType? learnCategoryType,
  String? learnCategoryId,
}) async {
  await _swallowLinkingFailure(smsId, () async {
    await inboxRepository.markImported(smsId, linkedEntityId: linkedEntityId);
    if (learnCategoryType != null && learnCategoryId != null) {
      await memoryRepository.record(merchant: merchant, transactionType: learnCategoryType, categoryId: learnCategoryId);
    }
  });
}
