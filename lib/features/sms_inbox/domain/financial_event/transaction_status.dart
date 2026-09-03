/// The real-world lifecycle status of the money movement a [FinancialEvent]
/// describes — distinct from [FinancialEventStatus], which tracks where the
/// *event* sits in FlowFi's own review pipeline. This is "did the bank
/// actually move the money," not "has the user looked at this yet."
///
/// Critical for the "never invent a transaction from a failed/pending SMS"
/// rule: only [success] (or [unknown], conservatively) should ever let
/// [FinancialEvent.moneyMovement] be true.
enum TransactionStatus { pending, success, failed, reversed, refunded, unknown }

extension TransactionStatusX on TransactionStatus {
  static TransactionStatus fromName(String? name) {
    if (name == null) return TransactionStatus.unknown;
    return TransactionStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => TransactionStatus.unknown,
    );
  }

  String get label {
    switch (this) {
      case TransactionStatus.pending:
        return 'Pending';
      case TransactionStatus.success:
        return 'Successful';
      case TransactionStatus.failed:
        return 'Failed';
      case TransactionStatus.reversed:
        return 'Reversed';
      case TransactionStatus.refunded:
        return 'Refunded';
      case TransactionStatus.unknown:
        return 'Unknown';
    }
  }
}
