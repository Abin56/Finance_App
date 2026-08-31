import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../features/insights/presentation/providers/insight_generation_provider.dart';
import '../../../../features/insights/presentation/widgets/insight_card.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.insights] — [generalInsightsProvider]'s
/// output for the widget's own salary-cycle window vs. the immediately
/// preceding cycle. No insight text/threshold logic lives here; this card
/// only resolves the current/previous [DateRange] and renders whatever
/// the shared rule set returns.
class InsightsWidgetCard extends ConsumerWidget {
  const InsightsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchorDay = switch (config.dateStrategy) {
      SalaryCycleToDate(:final anchorDay) => anchorDay,
      SalaryCycleFull(:final anchorDay) => anchorDay,
      _ => 17,
    };
    final now = DateTime.now();
    final cycle = SalaryCycleFull(anchorDay: anchorDay).resolve(now);
    final cycleLength = cycle.end.difference(cycle.start);
    final previousCycle = DateRange(cycle.start.subtract(cycleLength), cycle.start.subtract(const Duration(seconds: 1)));

    final insights = ref.watch(
      generalInsightsProvider((range: cycle, previousRange: previousCycle, period: ReportsPeriod.custom)),
    );
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSizes.sm),
          if (insights.isEmpty)
            Text('Nothing to report yet.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else
            InsightsList(insights: insights),
        ],
      ),
    );
  }
}
