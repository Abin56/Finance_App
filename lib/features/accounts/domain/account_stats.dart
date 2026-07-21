/// One account's aggregated activity — everything the Account Details
/// screen's stats section shows. Fields beyond the four Transaction-derived
/// ones below are intentionally absent until a feature exposes a reliable
/// account-level summary of its own (see `accountStatsProvider`'s doc
/// comment) — the UI renders whatever this model supplies rather than
/// assuming a fixed stat set, so adding e.g. `creditCardPayments` later is
/// a provider change, not an Account Details redesign.
class AccountStats {
  const AccountStats({
    required this.income,
    required this.expense,
    required this.transfersIn,
    required this.transfersOut,
    required this.currentMonthExpense,
  });

  final double income;
  final double expense;
  final double transfersIn;
  final double transfersOut;

  /// Sum of non-transfer expenses dated in the current calendar month —
  /// backs the Account Details screen's "Monthly Spending" card.
  final double currentMonthExpense;
}
