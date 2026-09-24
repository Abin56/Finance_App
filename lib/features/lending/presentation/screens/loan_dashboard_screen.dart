import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../../domain/loan_dashboard_metrics.dart';
import '../providers/loan_providers.dart';

/// High-level Loan dashboard — every figure here is a direct sum of the
/// same [LoanFinancialSummary]/installment data every other loan screen
/// already trusts (see [loanDashboardMetricsProvider]/
/// [loanMonthlyRepaymentsProvider]). Deliberately has no date-range filter
/// over the balance stats (Borrowed/Lent/Outstanding/Interest) — those are
/// lifetime loan-balance figures, not period activity, so filtering them by
/// "This Month"/"Last Month" the way Cash Flow filters transactions would
/// misrepresent a loan's true standing. The Monthly Repayment section is the
/// one part that's inherently period-shaped, since it's already grouped by
/// due-month.
class LoanDashboardScreen extends ConsumerWidget {
  const LoanDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(loanDashboardMetricsProvider);
    final monthly = ref.watch(loanMonthlyRepaymentsProvider(3));
    final currency = CurrencyFormatter.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            _BorrowedVsLentCard(metrics: metrics, currency: currency),
            const SizedBox(height: AppSizes.lg),
            const SectionHeader(title: 'Overview'),
            _StatGrid(metrics: metrics, currency: currency),
            const SizedBox(height: AppSizes.lg),
            const SectionHeader(title: 'Upcoming Payments'),
            _UpcomingCard(metrics: metrics, currency: currency),
            const SizedBox(height: AppSizes.lg),
            const SectionHeader(title: 'Overdue'),
            _OverdueCard(metrics: metrics, currency: currency),
            const SizedBox(height: AppSizes.lg),
            const SectionHeader(title: 'Monthly Repayment'),
            _MonthlyRepaymentCard(buckets: monthly, currency: currency),
          ],
        ),
      ),
    );
  }
}

class _BorrowedVsLentCard extends StatelessWidget {
  const _BorrowedVsLentCard({required this.metrics, required this.currency});

  final LoanDashboardMetrics metrics;
  final CurrencyFormatter currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _DirectionStat(
              label: 'Borrowed',
              amount: metrics.totalBorrowed,
              color: AppColors.debit,
              currency: currency,
            ),
          ),
          Container(width: 1, height: 48, color: colors.outlineVariant),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: _DirectionStat(
              label: 'Lent',
              amount: metrics.totalLent,
              color: AppColors.credit,
              currency: currency,
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionStat extends StatelessWidget {
  const _DirectionStat({required this.label, required this.amount, required this.color, required this.currency});

  final String label;
  final double amount;
  final Color color;
  final CurrencyFormatter currency;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: AppSizes.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            currency.format(amount),
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.metrics, required this.currency});

  final LoanDashboardMetrics metrics;
  final CurrencyFormatter currency;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSizes.md,
      crossAxisSpacing: AppSizes.md,
      childAspectRatio: 2.2,
      children: [
        _StatTile(label: 'Total Outstanding', amount: metrics.totalOutstanding, currency: currency),
        _StatTile(label: 'Total Paid', amount: metrics.totalPaid, currency: currency, color: AppColors.success),
        _StatTile(
          label: 'Interest Remaining',
          amount: metrics.totalInterestRemaining,
          currency: currency,
          color: AppColors.warning,
        ),
        _StatTile(
          label: 'Overdue Amount',
          amount: metrics.overdueAmount,
          currency: currency,
          color: metrics.overdueAmount > 0 ? AppColors.error : null,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.amount, required this.currency, this.color});

  final String label;
  final double amount;
  final CurrencyFormatter currency;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: AppSizes.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              currency.format(amount),
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.metrics, required this.currency});

  final LoanDashboardMetrics metrics;
  final CurrencyFormatter currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _LabeledAmount(
              label: 'Next 7 days',
              value: currency.format(metrics.upcoming7Days),
            ),
          ),
          Container(width: 1, height: 40, color: colors.outlineVariant),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: _LabeledAmount(
              label: 'Next 30 days',
              value: currency.format(metrics.upcoming30Days),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverdueCard extends StatelessWidget {
  const _OverdueCard({required this.metrics, required this.currency});

  final LoanDashboardMetrics metrics;
  final CurrencyFormatter currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasOverdue = metrics.overdueLoanCount > 0;
    return AppCard(
      color: hasOverdue ? AppColors.error.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
          Expanded(
            child: _LabeledAmount(
              label: 'Overdue Loans',
              value: '${metrics.overdueLoanCount}',
              color: hasOverdue ? AppColors.error : null,
            ),
          ),
          Container(width: 1, height: 40, color: colors.outlineVariant),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: _LabeledAmount(
              label: 'Overdue Amount',
              value: currency.format(metrics.overdueAmount),
              color: hasOverdue ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledAmount extends StatelessWidget {
  const _LabeledAmount({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: AppSizes.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}

class _MonthlyRepaymentCard extends StatelessWidget {
  const _MonthlyRepaymentCard({required this.buckets, required this.currency});

  final List<MonthlyRepaymentBucket> buckets;
  final CurrencyFormatter currency;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final monthFormat = DateFormat('MMMM');
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < buckets.length; i++) ...[
            if (i > 0) const Divider(height: AppSizes.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(monthFormat.format(buckets[i].month), style: textTheme.bodyLarge),
                Text(
                  currency.format(buckets[i].amountDue),
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
