import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../../transactions/presentation/widgets/transaction_tile.dart';
import '../widgets/dashboard_balance_card.dart';
import '../widgets/dashboard_budget_ring_card.dart';
import '../widgets/dashboard_money_to_receive_card.dart';
import '../widgets/dashboard_monthly_summary_cards.dart';
import '../widgets/dashboard_upcoming_payments_card.dart';
import '../widgets/greeting_header.dart';
import '../widgets/quick_actions_row.dart';
import '../widgets/today_summary_card.dart';

/// The Home tab — a premium, quick-glance overview (not a detailed
/// financial center — that's the Cash Flow tab). Contains: Net Worth/
/// Account Balance, this month's Income/Expense/Savings, Today's Summary,
/// Upcoming Payments, Money To Receive, Budget Progress, Recent Activity,
/// and Quick Actions. Upcoming Payments/Money To Receive are compact
/// previews (top 3) of data the Cash Flow tab and Creditors list already
/// own in full; every other feature (EMI, Savings, split expenses,
/// Reports) stays one tap away via Quick Actions' "More" sheet or the More
/// tab, not a dashboard section.
///
/// This Month and Today's summaries sit back-to-back near the top so the
/// two numbers people check most often are visible without scrolling past
/// Budget Progress or Recent Activity first.
///
/// Every section animates in with a staggered fade + slide; pull-to-refresh
/// re-reads live Firestore streams (cheap and instant since they're already
/// cached locally, but the gesture is still wired up since it's expected
/// UX for a finance app).
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Future<void> _onRefresh() async {
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// Percentage change from [previous] to [current], or null when
  /// [previous] is zero (nothing to meaningfully compare against).
  double? _percentChange(double current, double previous) {
    if (previous == 0) return null;
    return (current - previous) / previous * 100;
  }

  @override
  Widget build(BuildContext context) {
    const stagger = Duration(milliseconds: 60);
    const sectionGap = SizedBox(height: AppSizes.lg);

    final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};
    final accountsById = {for (final a in accounts) a.id: a};

    final recent = [...transactions]..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final recentTop5 = recent.take(5).toList();

    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);
    final monthTransactions = transactions.where((t) => t.dateTime.isSameMonth(now)).toList();
    final lastMonthTransactions = transactions.where((t) => t.dateTime.isSameMonth(lastMonth)).toList();

    double totalFor(List<Transaction> list, TransactionType type) =>
        list.where((t) => t.type == type).fold(0.0, (total, t) => total + t.amount);

    final income = totalFor(monthTransactions, TransactionType.income);
    final expenses = totalFor(monthTransactions, TransactionType.expense);
    final lastMonthIncome = totalFor(lastMonthTransactions, TransactionType.income);
    final lastMonthExpenses = totalFor(lastMonthTransactions, TransactionType.expense);
    final netThisMonth = income - expenses;
    final netLastMonth = lastMonthIncome - lastMonthExpenses;

    final blocks = <Widget>[
      DashboardBalanceCard(
        changeVsLastMonth: netThisMonth - netLastMonth,
        changePercent: _percentChange(netThisMonth, netLastMonth),
      ),
      DashboardMonthlySummaryCards(income: income, expenses: expenses),
      const TodaySummaryCard(),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Upcoming Payments', actionLabel: 'View all', onActionTap: () => context.push(AppRoutes.cashFlow)),
          const DashboardUpcomingPaymentsCard(),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Money To Receive', actionLabel: 'View all', onActionTap: () => context.push(AppRoutes.creditors)),
          const DashboardMoneyToReceiveCard(),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Budget Progress', actionLabel: 'View all', onActionTap: () => context.push(AppRoutes.budget)),
          const DashboardBudgetRingCard(),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Recent Activity',
            actionLabel: recentTop5.isEmpty ? null : 'View all',
            onActionTap: () => context.goNamed(AppRoutes.transactionsName),
          ),
          if (recentTop5.isEmpty)
            const PlaceholderCard(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              message: 'Income and expenses you add will show up here.',
            )
          else
            for (final transaction in recentTop5)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: TransactionTile(
                  transaction: transaction,
                  category: categoriesById[transaction.categoryId],
                  account: accountsById[transaction.accountId],
                  onTap: () => context.push('${AppRoutes.transactions}/${transaction.id}'),
                ),
              ),
        ],
      ),
      const QuickActionsRow(),
    ];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: blocks.length + 1,
            separatorBuilder: (_, _) => sectionGap,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const GreetingHeader().animate().fadeIn(duration: const Duration(milliseconds: 350));
              }
              final block = blocks[index - 1];
              return block
                  .animate(delay: stagger * index)
                  .fadeIn(duration: const Duration(milliseconds: 350))
                  .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
            },
          ),
        ),
      ),
    );
  }
}
