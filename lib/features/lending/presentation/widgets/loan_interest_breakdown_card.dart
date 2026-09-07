import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/charts/domain/pie_chart_data.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/app_pie_chart.dart';
import '../../domain/loan.dart';
import '../../domain/loan_financial_summary.dart';
import '../../domain/loan_interest.dart';

/// Interest breakdown / amortization section for `LoanDetailScreen` — every
/// number here is read straight off [Installment.principalPortion] /
/// [Installment.interestPortion] / [Installment.amountDue] (already computed
/// once, at schedule-generation time, by `InterestCalculator` inside
/// `LoanRepository.createLoan`/`editLoanTerms`/`editLoanDate`) or off
/// [LoanFinancialSummary]. Nothing in this widget calls `InterestCalculator`
/// or re-derives interest with a different formula — that would risk a
/// second calculation drifting from the engine that actually built the
/// schedule and charged the user.
class LoanInterestBreakdownCard extends StatelessWidget {
  const LoanInterestBreakdownCard({
    super.key,
    required this.loan,
    required this.installments,
    required this.summary,
  });

  final Loan loan;
  final List<Installment> installments;
  final LoanFinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final interest = loan.interest;
    final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final hasInterest = interest != null && summary.totalScheduledInterest > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Interest', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSizes.sm),
        AppCard(
          child: !hasInterest
              ? const _NoInterestNotice()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Summary(summary: summary, interest: interest),
                    const SizedBox(height: AppSizes.md),
                    Center(
                      child: AppPieChart(
                        data: AppPieChartData(
                          slices: [
                            ChartSlice(
                              label: 'Principal',
                              value: summary.originalPrincipal,
                              color: context.colors.primary,
                            ),
                            ChartSlice(
                              label: 'Interest',
                              value: summary.totalScheduledInterest,
                              color: AppColors.warning,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),
                    if (interest.type == InterestType.flat)
                      _FlatInterestExplainer(installments: sorted)
                    else
                      _AmortizationTable(installments: sorted),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.interest});

  final LoanFinancialSummary summary;
  final LoanInterest interest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(context, 'Principal', CurrencyFormatter.instance.format(summary.originalPrincipal)),
        _row(context, 'Total Interest', CurrencyFormatter.instance.format(summary.totalScheduledInterest)),
        _row(context, 'Total Payable', CurrencyFormatter.instance.format(summary.totalScheduledPayable)),
        _row(context, 'Rate', '${interest.ratePercent}% ${interest.period.label}'),
        _row(context, 'Method', interest.type.label),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
          Text(value, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NoInterestNotice extends StatelessWidget {
  const _NoInterestNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, color: context.colors.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: AppSizes.sm),
        Text('No interest', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Flat interest charges the same interest portion every installment (all
/// derived from the original principal, never recalculated here) — so
/// instead of a balance-decreasing amortization table, this just explains
/// the method and lists how the fixed total interest is distributed across
/// installments, straight off each installment's own `interestPortion`.
class _FlatInterestExplainer extends StatelessWidget {
  const _FlatInterestExplainer({required this.installments});

  final List<Installment> installments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interest is calculated on the original principal.',
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSizes.sm),
        const Divider(height: 1),
        const SizedBox(height: AppSizes.sm),
        _headerRow(context),
        const SizedBox(height: 4),
        for (final installment in installments) _installmentRow(context, installment),
      ],
    );
  }

  Widget _headerRow(BuildContext context) {
    final style = context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5));
    return Row(
      children: [
        SizedBox(width: 28, child: Text('#', style: style)),
        Expanded(child: Text('EMI', style: style, textAlign: TextAlign.right)),
        const SizedBox(width: AppSizes.sm),
        Expanded(child: Text('Interest', style: style, textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _installmentRow(BuildContext context, Installment installment) {
    final style = context.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('${installment.sequenceNumber}', style: style)),
          Expanded(
            child: Text(CurrencyFormatter.instance.format(installment.amountDue), style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              CurrencyFormatter.instance.format(installment.interestPortion ?? 0),
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reducing-balance amortization table — EMI/Principal/Interest read
/// straight off each [Installment], and Balance is the running outstanding
/// principal after that installment, i.e. total principal minus every
/// principal portion paid through and including this row. This mirrors
/// `InterestBreakdown.periods[i].remainingPrincipal` exactly (same
/// cumulative-sum definition) without calling `InterestCalculator` again.
class _AmortizationTable extends StatelessWidget {
  const _AmortizationTable({required this.installments});

  final List<Installment> installments;

  @override
  Widget build(BuildContext context) {
    final headerStyle = context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5));
    final rowStyle = context.textTheme.bodySmall;

    final totalPrincipal = installments.fold(0.0, (sum, i) => sum + (i.principalPortion ?? 0));
    var cumulativePrincipal = 0.0;
    final balances = <int, double>{};
    for (final installment in installments) {
      cumulativePrincipal += installment.principalPortion ?? 0;
      balances[installment.sequenceNumber] = (totalPrincipal - cumulativePrincipal).clamp(0, totalPrincipal);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 32,
        columnSpacing: AppSizes.md,
        columns: [
          DataColumn(label: Text('#', style: headerStyle)),
          DataColumn(label: Text('EMI', style: headerStyle), numeric: true),
          DataColumn(label: Text('Principal', style: headerStyle), numeric: true),
          DataColumn(label: Text('Interest', style: headerStyle), numeric: true),
          DataColumn(label: Text('Balance', style: headerStyle), numeric: true),
        ],
        rows: [
          for (final installment in installments)
            DataRow(
              cells: [
                DataCell(Text('${installment.sequenceNumber}', style: rowStyle)),
                DataCell(Text(CurrencyFormatter.instance.format(installment.amountDue), style: rowStyle)),
                DataCell(Text(CurrencyFormatter.instance.format(installment.principalPortion ?? 0), style: rowStyle)),
                DataCell(Text(CurrencyFormatter.instance.format(installment.interestPortion ?? 0), style: rowStyle)),
                DataCell(Text(CurrencyFormatter.instance.format(balances[installment.sequenceNumber]!), style: rowStyle)),
              ],
            ),
        ],
      ),
    );
  }
}
