import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../../../features/cash_flow/presentation/providers/cash_flow_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../domain/dashboard_financial_summary.dart';
import '../../domain/date_range_strategy.dart';
import 'upcoming_due_provider.dart';

/// Composes [DashboardFinancialSummary] purely from `ref.watch` over
/// existing feature-owned providers — zero independent calculation. See
/// [DashboardFinancialSummary]'s own field docs for the exact source of each
/// figure. Deliberately a plain `Provider` (not a service/cache class):
/// Riverpod's provider graph already memoizes every one of these reads, so a
/// second caching layer on top would be redundant.
final dashboardFinancialSummaryProvider = Provider<DashboardFinancialSummary>((ref) {
  final netWorth = ref.watch(netWorthProvider);

  final cashFlow = ref.watch(cashFlowThisMonthProvider);

  final outstandingDebt = ref.watch(totalCreditCardOutstandingProvider) + ref.watch(totalAmountToPayProvider);

  // upcomingDueProvider is keyed by an explicit cycle window; SalaryCycleFull
  // (default anchorDay 17) is the same default cycle EMI/Loan/People already
  // share (see `loanCycleAnchor`/`emiCycleAnchor`/`personCycleAnchor`), so
  // this reuses that existing convention rather than inventing a new window.
  final range = const SalaryCycleFull().resolve(DateTime.now());
  final upcomingItems = ref.watch(upcomingDueProvider((start: range.start, end: range.end)));

  var upcomingObligationsTotal = 0.0;
  var overdueObligationsTotal = 0.0;
  for (final item in upcomingItems) {
    if (item.isCarriedOver) {
      overdueObligationsTotal += item.remaining;
    } else {
      upcomingObligationsTotal += item.remaining;
    }
  }

  return DashboardFinancialSummary(
    netWorth: netWorth,
    moneyIn: cashFlow.moneyIn,
    moneyOut: cashFlow.moneyOut,
    netCashFlow: cashFlow.net,
    outstandingDebt: outstandingDebt,
    upcomingObligationsTotal: upcomingObligationsTotal,
    overdueObligationsTotal: overdueObligationsTotal,
  );
});
