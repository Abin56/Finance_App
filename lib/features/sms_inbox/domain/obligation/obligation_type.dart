/// What kind of outstanding obligation a [FinancialObligation] describes —
/// items 6-14 of the task's 14-item taxonomy (items 1-5 are settled
/// outcomes, covered by [ObligationSemanticBucket] mapping onto the
/// existing `TransactionStatus`). Only meaningful when the obligation's
/// [ObligationSemanticBucket] is `reminder`, `upcoming`, or `due` — a
/// completed/pending/failed/reversed/refund event never gets one of these.
enum ObligationType {
  /// A generic "please pay" / "kindly pay" notice with no more specific
  /// subtype detected.
  paymentReminder,

  /// A future-tense scheduled debit ("will be debited on...") with no more
  /// specific subtype (EMI/loan/credit card/bill/subscription) detected.
  upcomingDebit,

  /// An explicit due-date notice with no more specific subtype detected.
  duePayment,

  /// An EMI installment obligation.
  emiObligation,

  /// A loan repayment obligation (not already identified as an EMI).
  loanObligation,

  /// A credit card bill/statement due obligation.
  creditCardDue,

  /// A utility/service bill due obligation.
  billDue,

  /// A subscription renewal obligation (streaming, SaaS, etc).
  subscriptionRenewal,

  /// The message reads as an outstanding obligation, but its subtype could
  /// not be determined — never guessed at.
  unknownObligation,
}

extension ObligationTypeX on ObligationType {
  static ObligationType fromName(String? name) {
    if (name == null) return ObligationType.unknownObligation;
    return ObligationType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ObligationType.unknownObligation,
    );
  }

  String get label {
    switch (this) {
      case ObligationType.paymentReminder:
        return 'Payment reminder';
      case ObligationType.upcomingDebit:
        return 'Upcoming debit';
      case ObligationType.duePayment:
        return 'Due payment';
      case ObligationType.emiObligation:
        return 'EMI';
      case ObligationType.loanObligation:
        return 'Loan repayment';
      case ObligationType.creditCardDue:
        return 'Credit card due';
      case ObligationType.billDue:
        return 'Bill due';
      case ObligationType.subscriptionRenewal:
        return 'Subscription renewal';
      case ObligationType.unknownObligation:
        return 'Obligation';
    }
  }
}
