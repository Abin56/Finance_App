import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import '../providers/upcoming_due_provider.dart';
import 'dashboard_widget_shell.dart';
import 'upcoming_payments_widget_card.dart';

/// Renders [DashboardWidgetType.bills] — the Bills slice of
/// [upcomingDueProvider], the same shared aggregation the Financial View
/// and Upcoming Payments widgets read, filtered to
/// [UpcomingDueKind.bill]. No bill-status math of its own: every row's
/// remaining amount/urgency/carry-forward flag comes straight from that
/// provider.
class BillsWidgetCard extends ConsumerWidget {
  const BillsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchorDay = switch (config.dateStrategy) {
      SalaryCycleToDate(:final anchorDay) => anchorDay,
      SalaryCycleFull(:final anchorDay) => anchorDay,
      _ => 17,
    };
    final cycle = SalaryCycleFull(anchorDay: anchorDay).resolve(DateTime.now());
    final items = ref
        .watch(upcomingDueProvider((start: cycle.start, end: cycle.end)))
        .where((i) => i.kind == UpcomingDueKind.bill)
        .toList();
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: () => context.push(AppRoutes.bills),
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          if (items.isEmpty)
            Text('No bills due this cycle.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else
            UpcomingDueList(items: items),
        ],
      ),
    );
  }
}
