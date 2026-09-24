/// A person's combined "who owes whom" picture — ledger balance and loan
/// outstanding amounts added together, never re-derived from a second
/// balance calculation. [ledgerBalance] is read straight off
/// `Person.currentBalance` (positive = they owe you, negative = you owe
/// them — see `Person.isCreditor`/`Person.isDebtor`), and [loanGivenOutstanding]/
/// [loanTakenOutstanding] are the sums of `loanRemainingAmountProvider`
/// across this person's [LoanDirection.given]/[LoanDirection.taken] loans —
/// exactly the same figures `PersonLoansSummaryCard`'s "Money to
/// receive"/"Money to pay" rows already show, just additionally combined
/// here with the ledger balance into one net figure. Loans have no link to
/// `LedgerRepository` (confirmed: `LoanRepository`/`InstallmentPaymentRepository`
/// never write a `LedgerEntry`, except `PaymentAttributionService` when a
/// `Person` other than the account owner pays an installment — see its own
/// doc comment), so summing ledger balance and loan outstanding is always
/// additive across genuinely independent sources, never a double count of
/// the same underlying event.
class PersonLoanLedgerSummary {
  const PersonLoanLedgerSummary({
    required this.ledgerBalance,
    required this.loanGivenTotal,
    required this.loanGivenOutstanding,
    required this.loanTakenTotal,
    required this.loanTakenOutstanding,
  });

  /// `Person.currentBalance` — positive means they owe you (from ledger
  /// activity: split-expense settlements, "they paid for me", manual
  /// adjustments, and any `PaymentAttributionService`-posted entry).
  final double ledgerBalance;

  /// Sum of `Loan.loanAmount` across this person's non-closed
  /// [LoanDirection.given] loans — the original amount given, before any
  /// repayment.
  final double loanGivenTotal;

  /// Sum of `loanRemainingAmountProvider` across this person's
  /// [LoanDirection.given] loans (they owe you, from Lending).
  final double loanGivenOutstanding;

  /// Sum of `Loan.loanAmount` across this person's non-closed
  /// [LoanDirection.taken] loans — the original amount borrowed, before any
  /// repayment.
  final double loanTakenTotal;

  /// Sum of `loanRemainingAmountProvider` across this person's
  /// [LoanDirection.taken] loans (you owe them, from Lending).
  final double loanTakenOutstanding;

  /// Total money this person owes you — ledger's creditor side plus every
  /// outstanding loan you gave them.
  double get theyOweYou => (ledgerBalance > 0 ? ledgerBalance : 0) + loanGivenOutstanding;

  /// Total money you owe this person — ledger's debtor side plus every
  /// outstanding loan you took from them.
  double get youOweThem => (ledgerBalance < 0 ? -ledgerBalance : 0) + loanTakenOutstanding;

  /// Positive: they owe you, net. Negative: you owe them, net.
  double get net => theyOweYou - youOweThem;

  /// `true` when [net] is positive (they owe you, net) — mirrors
  /// `Person.isCreditor`'s sign convention.
  bool get isNetReceivable => net > 0;
}
