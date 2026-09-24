/// A single, pure composition of figures already computed by other
/// feature-owned providers — the "Dashboard financial summary". Every field
/// below is a direct read (or a simple addition of two already-final
/// numbers) from an existing source; nothing here re-sums accounts,
/// re-filters transactions, or re-derives a due/overdue classification.
/// See [DashboardFinancialSummary] field docs for each figure's exact
/// source provider, and
/// `lib/core/dashboard/presentation/providers/dashboard_financial_summary_provider.dart`
/// for how they're composed via `ref.watch`.
///
/// Soft-deletes, `excludeFromCalculations` transactions, and transfers are
/// already handled at the stream/repository level by the underlying source
/// providers (confirmed by the prior Dashboard audit) — this model performs
/// no additional filtering of its own.
class DashboardFinancialSummary {
  const DashboardFinancialSummary({
    required this.netWorth,
    required this.moneyIn,
    required this.moneyOut,
    required this.netCashFlow,
    required this.outstandingDebt,
    required this.upcomingObligationsTotal,
    required this.overdueObligationsTotal,
  });

  /// Sum of every account's `currentBalance` — read straight off
  /// `netWorthProvider` (`lib/features/accounts/presentation/providers/account_providers.dart`).
  /// Not resummed here.
  ///
  /// `totalLiabilities`/`totalAssets` are deliberately omitted: the Accounts
  /// feature exposes no per-account type/liability-vs-asset split provider
  /// today (only the flat `currentBalance` sum via `netWorthProvider`), and
  /// building one would be a new calculation, not a composition of an
  /// existing source — out of scope per this task's own rule.
  final double netWorth;

  /// This calendar month's total income lines — read from
  /// `cashFlowThisMonthProvider.moneyIn`
  /// (`lib/features/cash_flow/presentation/providers/cash_flow_providers.dart`).
  final double moneyIn;

  /// This calendar month's total expense/payment lines — read from
  /// `cashFlowThisMonthProvider.moneyOut`.
  final double moneyOut;

  /// `moneyIn - moneyOut` — read from `cashFlowThisMonthProvider.net`
  /// directly (not recomputed from [moneyIn]/[moneyOut] here, so this can
  /// never drift from what the Cash Flow feature itself reports).
  final double netCashFlow;

  /// `totalCreditCardOutstandingProvider + totalAmountToPayProvider` — a
  /// plain addition of two already-final totals
  /// (`lib/features/credit_cards/presentation/providers/credit_card_providers.dart`
  /// and `lib/features/lending/presentation/providers/loan_providers.dart`),
  /// not a recalculation of either.
  final double outstandingDebt;

  /// Sum of `UpcomingDueItem.remaining` across every item `upcomingDueProvider`
  /// classifies as *not* carried-over (i.e. due within the current cycle,
  /// not yet overdue) — reuses that provider's own `isCarriedOver`
  /// classification verbatim; no new due/overdue date comparison is
  /// performed here.
  final double upcomingObligationsTotal;

  /// Sum of `UpcomingDueItem.remaining` across every item `upcomingDueProvider`
  /// flags `isCarriedOver: true` (i.e. still unpaid from a prior pay
  /// cycle) — same source and same reused flag as
  /// [upcomingObligationsTotal].
  final double overdueObligationsTotal;
}
