import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction_type.dart';
import '../../transactions/presentation/providers/transaction_providers.dart';
import '../data/merchant_memory_repository.dart';
import '../data/sms_inbox_repository.dart';
import '../domain/sms_inbox_item.dart';
import 'providers/sms_inbox_providers.dart';
import 'sms_import_completion.dart';

/// The shared answers the user gives once, then applied to every selected
/// SMS. Everything *per-message* — amount, date, merchant — still comes from
/// each SMS individually, which is what makes each one its own independent
/// transaction rather than a merged lump sum.
class SmsBulkConvertConfig {
  const SmsBulkConvertConfig({
    required this.type,
    required this.categoryId,
    required this.accountId,
    this.notes = '',
  });

  final TransactionType type;
  final String categoryId;
  final String accountId;
  final String notes;
}

/// What actually happened, so the user gets a truthful report rather than a
/// blanket "Done". A partial failure is normal (one bad row shouldn't undo
/// nine good ones), so these counts are reported, never swallowed.
class SmsBulkConvertResult {
  const SmsBulkConvertResult({required this.converted, required this.skipped, required this.failed});

  /// Genuinely created a transaction *and* marked its SMS imported.
  final int converted;

  /// Left untouched and still pending: either the parser couldn't extract an
  /// amount, or the message is a flagged duplicate. Never guessed at.
  final int skipped;

  /// The create call itself threw. Left pending so the user can retry.
  final int failed;

  int get total => converted + skipped + failed;
}

/// Converts many selected SMS in one pass, reusing the *existing*
/// `TransactionRepository.createTransaction` once per message — the same call
/// `AddExpenseScreen` makes for a single manual entry. No balance, category
/// or statement math is reimplemented here, and there is no bulk repository:
/// this is a loop over the existing engine, nothing more.
///
/// Scoped to Expense and Income deliberately. Every other conversion target
/// (Split, Loan, EMI, Bill, Transfer, Someone Paid Me) needs a *different*
/// person, loan, bill or counter-account per message, so there is no shared
/// answer to collect once — bulk-converting them would either demand per-SMS
/// editing anyway or quietly file records against the wrong entity. Those
/// stay single-convert. Adding a future type here means extending
/// [SmsBulkConvertConfig] and this switch — the selection, sheet and
/// reporting need no change.
/// Takes its repositories directly rather than a `Ref`, so the whole loop is
/// plain, driveable logic with no widget or provider scope needed to test it.
/// Reloading the inbox afterwards is deliberately the caller's job — see
/// [convert].
class SmsBulkConverter {
  const SmsBulkConverter(this._transactions, this._inbox, this._memories);

  final TransactionRepository _transactions;
  final SmsInboxRepository _inbox;
  final MerchantMemoryRepository _memories;

  /// Writes are sequential rather than a `Future.wait`: they hit the same
  /// account balance, and firing hundreds of concurrent writes at Firestore
  /// is how you get throttled mid-batch and end up half-converted.
  ///
  /// Does not refresh the inbox list — the caller does that *once* when this
  /// returns. Refreshing per message (as `markImported` on the notifier
  /// would) means a full reload per message, which over 500 of them is what
  /// freezes the screen.
  Future<SmsBulkConvertResult> convert(
    List<SmsInboxItem> items,
    SmsBulkConvertConfig config,
  ) async {
    var converted = 0;
    var skipped = 0;
    var failed = 0;

    for (final item in items) {
      // Enforced here, not just at the call site: a flagged duplicate is only
      // ever convertible one at a time from the review sheet, where the user
      // can see the original they'd be double-counting against. This is the
      // engine that writes real money, so the rule lives where no future
      // caller can route around it.
      if (item.isDuplicate) {
        skipped++;
        continue;
      }

      final amount = item.parsed?.amount;
      // An SMS the parser couldn't pull an amount from has nothing to create
      // a transaction from. Inventing one — or defaulting to zero — would
      // write a bogus record into the user's real balances.
      if (amount == null || amount <= 0) {
        skipped++;
        continue;
      }

      try {
        final merchant = item.parsed?.merchantOrSender;
        final created = await _transactions.createTransaction(
          type: config.type,
          amount: amount,
          dateTime: item.rawMessage.date,
          accountId: config.accountId,
          categoryId: config.categoryId,
          description: merchant ?? '',
          notes: config.notes,
        );

        // The transaction above is real and saved — this row is a success
        // from here on, regardless of what happens next. Marking the SMS
        // imported (and learning the merchant/category) is best-effort:
        // `linkSmsImportViaRepositories` swallows its own failures so a
        // linking hiccup can never be reported as `failed` (which would
        // invite a retry that creates a second transaction for this SMS —
        // the transaction already exists).
        converted++;
        await linkSmsImportViaRepositories(
          inboxRepository: _inbox,
          memoryRepository: _memories,
          smsId: item.id,
          linkedEntityId: created.id,
          merchant: merchant,
          learnCategoryType: config.type,
          learnCategoryId: config.categoryId,
        );
      } catch (_) {
        failed++;
      }
    }

    return SmsBulkConvertResult(converted: converted, skipped: skipped, failed: failed);
  }
}

final smsBulkConverterProvider = Provider<SmsBulkConverter>((ref) {
  return SmsBulkConverter(
    ref.watch(transactionRepositoryProvider),
    ref.watch(smsInboxRepositoryProvider),
    ref.watch(merchantMemoryRepositoryProvider),
  );
});
