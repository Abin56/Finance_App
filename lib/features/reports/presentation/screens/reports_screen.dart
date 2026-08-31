import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/fiscal_year_controller.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../../insights/presentation/providers/insight_generation_provider.dart';
import '../../../insights/presentation/widgets/insight_card.dart';
import '../../domain/reports_period.dart';
import '../providers/category_spending_breakdown_provider.dart';
import '../widgets/cash_flow_chart.dart';
import '../widgets/category_spending_pie_chart.dart';
import '../widgets/credit_card_report_section.dart';
import '../widgets/emi_report_section.dart';
import '../widgets/financial_health_section.dart';
import '../widgets/monthly_comparison_chart.dart';
import '../widgets/monthly_financial_report_card.dart';
import '../widgets/reports_category_list.dart';
import '../widgets/spending_trend_chart.dart';
import '../widgets/reports_my_expense_card.dart';
import '../widgets/reports_overview_card.dart';
import '../widgets/reports_period_chips.dart';

/// Reports & analytics home — overview totals, a weekly cash-flow chart,
/// spending broken down by category, a quick insight, and (once at least
/// one EMI exists) the EMI report section. Every number is derived
/// client-side from the same transaction/category streams the rest of the
/// app already watches, filtered to the selected [ReportsPeriod].
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportsPeriod _period = ReportsPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(calculableTransactionsProvider);
    final emis = ref.watch(emisStreamProvider).value ?? const [];
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];

    final fiscalYearStartMonth = ref.watch(fiscalYearStartMonthProvider);
    final now = DateTime.now();
    final range = _period.rangeFor(now, fiscalYearStartMonth: fiscalYearStartMonth);
    // Transfers between the user's own accounts aren't real income/expense —
    // excluded so a transfer's two legs don't inflate both totals. Every
    // Reports figure/chart on this screen must filter from this same list
    // (via `_period.reportDateFor`, not a re-derived date) so nothing can
    // silently disagree about which transactions are "in period".
    final periodTransactions =
        transactions.where((t) => range.contains(_period.reportDateFor(t)) && !t.isTransfer).toList();

    final previousRange = _previousRangeFor(_period, now, fiscalYearStartMonth);
    final previousTransactions =
        transactions.where((t) => previousRange.contains(_period.reportDateFor(t)) && !t.isTransfer).toList();

    double totalFor(List<Transaction> list, TransactionType type) =>
        list.where((t) => t.type == type).fold(0.0, (total, t) => total + t.amount);

    final income = totalFor(periodTransactions, TransactionType.income);
    final expenses = totalFor(periodTransactions, TransactionType.expense);
    final prevIncome = totalFor(previousTransactions, TransactionType.income);
    final prevExpenses = totalFor(previousTransactions, TransactionType.expense);
    final netSavings = income - expenses;
    final prevNetSavings = prevIncome - prevExpenses;

    final myExpenseBreakdown = ref.watch(myExpenseBreakdownForTransactionsProvider(periodTransactions));
    final moneyToReceive = ref.watch(totalPendingSplitAmountProvider);
    final moneyReceived = ref.watch(moneyReceivedForRangeProvider((start: range.start, end: range.end)));

    final categoryEntries = ref.watch(categorySpendingBreakdownProvider((range: range, period: _period)));
    final insightArgs = (range: range, previousRange: previousRange, period: _period);
    final insights = ref.watch(generalInsightsProvider(insightArgs));

    return Scaffold(
      backgroundColor: AppClay.background(context),
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(child: transactions.isEmpty && emis.isEmpty
          ? const EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: 'No reports yet',
              subtitle: 'Reports will appear once you add transactions.',
            )
          : ListView(
              padding: const EdgeInsets.all(AppSizes.lg),
              children: [
                ReportsPeriodChips(
                  selected: _period,
                  onChanged: (p) => setState(() => _period = p),
                  periods: const [
                    ReportsPeriod.today,
                    ReportsPeriod.thisWeek,
                    ReportsPeriod.thisMonth,
                    ReportsPeriod.lastMonth,
                    ReportsPeriod.thisYear,
                    ReportsPeriod.financialYear,
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                const SectionHeader(title: 'Overview'),
                ReportsOverviewCard(
                  income: income,
                  expenses: expenses,
                  incomeChangePercent: _percentChange(income, prevIncome),
                  expensesChangePercent: _percentChange(expenses, prevExpenses),
                  netSavingsChangePercent: _percentChange(netSavings, prevNetSavings),
                ),
                const SizedBox(height: AppSizes.lg),
                const SectionHeader(title: 'Monthly Financial Report'),
                MonthlyFinancialReportCard(
                  periodStart: range.start,
                  periodEnd: range.end,
                  income: income,
                  expenses: expenses,
                ),
                const SizedBox(height: AppSizes.lg),
                const SectionHeader(title: 'My Expense'),
                ReportsMyExpenseCard(
                  breakdown: myExpenseBreakdown,
                  moneyToReceive: moneyToReceive,
                  moneyReceived: moneyReceived,
                ),
                const SizedBox(height: AppSizes.lg),
                const SectionHeader(title: 'Cash Flow'),
                CashFlowChart(
                  periodStart: range.start,
                  periodEnd: range.end,
                  transactions: periodTransactions,
                  period: _period,
                ),
                const SizedBox(height: AppSizes.lg),
                SpendingTrendChart(args: (range: range, period: _period)),
                const SizedBox(height: AppSizes.lg),
                const MonthlyComparisonChart(),
                const SizedBox(height: AppSizes.lg),
                SectionHeader(
                  title: 'Spending by Category',
                  actionLabel: categoryEntries.isEmpty ? null : 'View all',
                  onActionTap: () => context.push(AppRoutes.transactions),
                ),
                if (categoryEntries.isEmpty)
                  const EmptyState(
                    icon: Icons.donut_small_outlined,
                    title: 'No spending yet',
                    subtitle: 'Your top spending categories will appear here.',
                  )
                else ...[
                  CategorySpendingPieChart(entries: categoryEntries),
                  const SizedBox(height: AppSizes.sm),
                  ReportsCategoryList(
                    entries: categoryEntries,
                    onTapCategory: (category) =>
                        context.push('${AppRoutes.reports}/category/${category.id}?period=${_period.name}'),
                  ),
                ],
                if (insights.isNotEmpty) ...[
                  const SizedBox(height: AppSizes.lg),
                  const SectionHeader(title: 'Recent Insights'),
                  InsightsList(insights: insights),
                ],
                if (emis.isNotEmpty) ...[
                  const SizedBox(height: AppSizes.lg),
                  const EmiReportSection(),
                ],
                if (creditCards.isNotEmpty) ...[
                  const SizedBox(height: AppSizes.lg),
                  CreditCardReportSection(periodStart: range.start, periodEnd: range.end),
                ],
                const SizedBox(height: AppSizes.lg),
                FinancialHealthSection(range: range, previousRange: previousRange, period: _period),
              ],
            )),
    );
  }

  DateRange _previousRangeFor(ReportsPeriod period, DateTime now, int fiscalYearStartMonth) {
    switch (period) {
      case ReportsPeriod.today:
        final yesterday = now.subtract(const Duration(days: 1));
        return ReportsPeriod.today.rangeFor(yesterday);
      case ReportsPeriod.thisWeek:
        final lastWeek = now.subtract(const Duration(days: 7));
        return DateRange(lastWeek.startOfWeek, lastWeek.endOfWeek);
      case ReportsPeriod.thisMonth:
        return ReportsPeriod.lastMonth.rangeFor(now);
      case ReportsPeriod.lastMonth:
        final twoMonthsAgo = DateTime(now.year, now.month - 2);
        return DateRange(twoMonthsAgo.startOfMonth, twoMonthsAgo.endOfMonth);
      case ReportsPeriod.thisYear:
        final lastYear = DateTime(now.year - 1, 1, 1);
        return DateRange(lastYear, DateTime(now.year - 1, 12, 31, 23, 59, 59));
      case ReportsPeriod.financialYear:
        final oneYearAgo = DateTime(now.year - 1, now.month, now.day);
        return ReportsPeriod.financialYear.rangeFor(oneYearAgo, fiscalYearStartMonth: fiscalYearStartMonth);
      case ReportsPeriod.custom:
        return period.rangeFor(now);
    }
  }

  double? _percentChange(double current, double previous) {
    if (previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}
