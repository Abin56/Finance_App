import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/app_line_chart.dart';
import '../../domain/reports_period.dart';
import '../providers/spending_trend_providers.dart';

/// Daily spending trend for the selected Reports period, via
/// [spendingTrendProvider] + the shared [AppLineChart] component — no
/// spending math of its own.
class SpendingTrendChart extends ConsumerWidget {
  const SpendingTrendChart({super.key, required this.args});

  final ({DateRange range, ReportsPeriod period}) args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(spendingTrendProvider(args));
    if (data.series.every((s) => s.points.every((p) => p.y == 0))) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Spending Trend', style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.lg),
          AppLineChart(data: data),
        ],
      ),
    );
  }
}
