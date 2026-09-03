import '../financial_event/transaction_status.dart';

/// The Phase 4 semantic classification of a financial-shaped SMS/event —
/// distinct from [TransactionStatus], which only covers the five outcomes
/// that apply once money has definitely moved or definitely failed to.
/// [reminder]/[upcoming]/[due] are the three "hasn't moved yet" states this
/// engine adds on top of that, none of which [TransactionStatus] can
/// represent on its own. [unknown] is the honest fallback when neither a
/// completed-transaction signal nor a reminder signal is present — never
/// defaulted to [completed].
///
/// This is the enum item 1-5 of the task's 14-item obligation taxonomy map
/// onto directly (via [ObligationSemanticBucketX.fromTransactionStatus]);
/// items 6-14 are [ObligationType], only meaningful once the bucket is
/// [reminder], [upcoming], or [due].
enum ObligationSemanticBucket {
  /// Money moved successfully — maps from [TransactionStatus.success].
  completed,

  /// Money movement was initiated but not yet confirmed —
  /// [TransactionStatus.pending].
  pending,

  /// Money movement was attempted and failed — [TransactionStatus.failed].
  failed,

  /// A prior charge was reversed — [TransactionStatus.reversed].
  reversed,

  /// A prior charge was refunded — [TransactionStatus.refunded].
  refund,

  /// A generic "you owe this" notice with no stronger due/scheduled signal.
  reminder,

  /// A future-tense scheduled debit ("will be debited on...", "scheduled
  /// for...") — money has not moved yet, but a specific future action is
  /// named.
  upcoming,

  /// An explicit due-date notice ("due on...", "payment due", "due date").
  due,

  /// Neither a completed-transaction signal nor a reminder signal was
  /// found — never treated as [completed] by default.
  unknown,
}

extension ObligationSemanticBucketX on ObligationSemanticBucket {
  /// The three buckets that represent money which has not moved yet — the
  /// only buckets [ObligationBuilder] is ever allowed to turn into a
  /// [FinancialObligation]. See Safety rule 1: "Reminder != transaction."
  static const outstandingBuckets = {
    ObligationSemanticBucket.reminder,
    ObligationSemanticBucket.upcoming,
    ObligationSemanticBucket.due,
  };

  bool get isOutstanding => outstandingBuckets.contains(this);

  /// The direct mapping for the four settled [TransactionStatus] outcomes
  /// this bucket can represent — [TransactionStatus.unknown] deliberately
  /// has no entry here, since "unknown" money-movement status must never be
  /// assumed [ObligationSemanticBucket.completed].
  static ObligationSemanticBucket? fromTransactionStatus(
    TransactionStatus status,
  ) {
    switch (status) {
      case TransactionStatus.success:
        return ObligationSemanticBucket.completed;
      case TransactionStatus.pending:
        return ObligationSemanticBucket.pending;
      case TransactionStatus.failed:
        return ObligationSemanticBucket.failed;
      case TransactionStatus.reversed:
        return ObligationSemanticBucket.reversed;
      case TransactionStatus.refunded:
        return ObligationSemanticBucket.refund;
      case TransactionStatus.unknown:
        return null;
    }
  }

  String get label {
    switch (this) {
      case ObligationSemanticBucket.completed:
        return 'Completed';
      case ObligationSemanticBucket.pending:
        return 'Pending';
      case ObligationSemanticBucket.failed:
        return 'Failed';
      case ObligationSemanticBucket.reversed:
        return 'Reversed';
      case ObligationSemanticBucket.refund:
        return 'Refund';
      case ObligationSemanticBucket.reminder:
        return 'Payment reminder';
      case ObligationSemanticBucket.upcoming:
        return 'Upcoming debit';
      case ObligationSemanticBucket.due:
        return 'Due payment';
      case ObligationSemanticBucket.unknown:
        return 'Unknown';
    }
  }
}
