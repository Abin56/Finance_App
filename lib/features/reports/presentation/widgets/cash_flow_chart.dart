import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/reports_period.dart';

/// Income vs. expenses grouped bar chart, one pair of bars per week of the
/// selected period — mirrors the Figma "Cash Flow" section.
class CashFlowChart extends StatelessWidget {
  const CashFlowChart({
    super.key,
    required this.periodStart,
    required this.periodEnd,
    required this.transactions,
    required this.period,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final List<Transaction> transactions;

  /// Which date [ReportsPeriodX.reportDateFor] should read for each
  /// transaction — must be the same [ReportsPeriod] the caller used to
  /// build [transactions] in the first place, so a transaction reassigned
  /// to a different Accounting Month lands in the correct week bar instead
  /// of falling outside every bucket and silently vanishing from the chart.
  final ReportsPeriod period;

  @override
  Widget build(BuildContext context) {
    final weeks = <DateTime>[];
    var weekStart = periodStart.startOfWeek;
    while (weekStart.isBefore(periodEnd)) {
      weeks.add(weekStart);
      weekStart = weekStart.add(const Duration(days: 7));
    }
    if (weeks.isEmpty) weeks.add(periodStart.startOfWeek);

    // Transfers between the user's own accounts aren't real income/expense —
    // excluded so a transfer's two legs don't inflate both bars.
    double totalFor(DateTime weekStart, TransactionType type) {
      final weekEnd = weekStart.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      return transactions
          .where((t) {
            final d = period.reportDateFor(t);
            return t.type == type && !t.isTransfer && !d.isBefore(weekStart) && !d.isAfter(weekEnd);
          })
          .fold(0.0, (total, t) => total + t.amount);
    }

    final incomeByWeek = [for (final w in weeks) totalFor(w, TransactionType.income)];
    final expenseByWeek = [for (final w in weeks) totalFor(w, TransactionType.expense)];
    final maxY = [...incomeByWeek, ...expenseByWeek].fold(0.0, (max, v) => v > max ? v : max);
    final chartMax = maxY == 0 ? 1.0 : maxY * 1.15;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Income vs Expenses', style: context.textTheme.titleSmall),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(color: TransactionType.income.color, label: 'Income'),
                  const SizedBox(width: AppSizes.md),
                  _LegendDot(color: TransactionType.expense.color, label: 'Expenses'),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: chartMax,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= weeks.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSizes.xs),
                          child: Text('Week ${index + 1}', style: context.textTheme.bodySmall),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < weeks.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 6,
                      barRods: [
                        BarChartRodData(
                          toY: incomeByWeek[i],
                          color: TransactionType.income.color,
                          width: 14,
                          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                        ),
                        BarChartRodData(
                          toY: expenseByWeek[i],
                          color: TransactionType.expense.color,
                          width: 14,
                          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSizes.xs),
        Text(label, style: context.textTheme.bodySmall),
      ],
    );
  }
}
