import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../shared/charts/domain/chart_point.dart';
import '../../../../shared/charts/domain/line_chart_data.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/reports_period.dart';

/// Daily total spending across [range], bucketed the same way
/// `CategorySpendingTrendChart` already buckets one category's spend — this
/// is the whole-period equivalent, generalized to `AppLineChartData` (see
/// `shared/charts/domain/`) rather than a bespoke `fl_chart` input, so this
/// provider's output is chart-library-agnostic. Only sums
/// [calculableTransactionsProvider] entries already filtered/bucketed by
/// [period]'s own [ReportsPeriodX.reportDateFor] — no new spending math.
final spendingTrendProvider =
    Provider.family<AppLineChartData, ({DateRange range, ReportsPeriod period})>((ref, args) {
  final transactions = ref.watch(calculableTransactionsProvider);

  final days = <DateTime>[];
  var day = args.range.start.dateOnly;
  final end = args.range.end.dateOnly;
  while (!day.isAfter(end)) {
    days.add(day);
    day = day.add(const Duration(days: 1));
  }

  final totalsByDay = {
    for (final d in days)
      d: transactions
          .where((t) =>
              t.type == TransactionType.expense &&
              args.period.reportDateFor(t).dateOnly == d)
          .fold(0.0, (sum, t) => sum + t.amount),
  };

  return AppLineChartData.trend(
    points: [for (var i = 0; i < days.length; i++) ChartPoint(x: i.toDouble(), y: totalsByDay[days[i]] ?? 0)],
    seriesName: 'Spending',
    xAxisLabels: [for (final d in days) d.shortDate],
  );
});
