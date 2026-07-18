import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../transactions/domain/transaction.dart';
import '../../domain/reports_period.dart';

/// Daily total for one category across the selected period, as a filled
/// line chart with the peak day called out — mirrors the Figma "Spending
/// Trend" section on the category detail screen.
class CategorySpendingTrendChart extends StatelessWidget {
  const CategorySpendingTrendChart({
    super.key,
    required this.periodStart,
    required this.periodEnd,
    required this.transactions,
    required this.color,
    required this.period,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final List<Transaction> transactions;
  final Color color;

  /// Which date [ReportsPeriodX.reportDateFor] should read for each
  /// transaction — must match the [ReportsPeriod] the caller used to build
  /// [transactions], so a transaction reassigned to a different Accounting
  /// Month lands on the correct day instead of silently vanishing from the
  /// chart while still counting in the screen's header total.
  final ReportsPeriod period;

  @override
  Widget build(BuildContext context) {
    final days = <DateTime>[];
    var day = periodStart.dateOnly;
    final end = periodEnd.dateOnly;
    while (!day.isAfter(end)) {
      days.add(day);
      day = day.add(const Duration(days: 1));
    }

    final totalsByDay = {
      for (final d in days)
        d: transactions.where((t) => period.reportDateFor(t).dateOnly == d).fold(0.0, (sum, t) => sum + t.amount),
    };

    final maxValue = totalsByDay.values.fold(0.0, (max, v) => v > max ? v : max);
    final chartMax = maxValue == 0 ? 1.0 : maxValue * 1.2;

    var peakDay = days.isNotEmpty ? days.first : periodStart;
    var peakValue = 0.0;
    totalsByDay.forEach((d, v) {
      if (v > peakValue) {
        peakValue = v;
        peakDay = d;
      }
    });

    final labelEvery = (days.length / 6).ceil().clamp(1, days.isEmpty ? 1 : days.length);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spending Trend', style: context.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: chartMax,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        CurrencyFormatter.instance.formatCompact(value),
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= days.length || index % labelEvery != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSizes.xs),
                          child: Text(days[index].shortDate, style: context.textTheme.bodySmall),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          CurrencyFormatter.instance.format(spot.y),
                          context.textTheme.bodySmall!.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), totalsByDay[days[i]] ?? 0)],
                    isCurved: true,
                    color: color,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
                  ),
                ],
              ),
            ),
          ),
          if (peakValue > 0) ...[
            const SizedBox(height: AppSizes.sm),
            Center(
              child: Text(
                'Peak: ${peakDay.shortDate} · ${CurrencyFormatter.instance.format(peakValue)}',
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
