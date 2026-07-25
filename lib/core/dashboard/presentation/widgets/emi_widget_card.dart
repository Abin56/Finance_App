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

/// Renders [DashboardWidgetType.emi] — the EMI slice of
/// [upcomingDueProvider], filtered to [UpcomingDueKind.emi]. Same shared
/// aggregation the Financial View/Upcoming Payments/Bills widgets read;
/// no EMI-status math of its own.
class EmiWidgetCard extends ConsumerWidget {
  const EmiWidgetCard({super.key, required this.config});

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
        .where((i) => i.kind == UpcomingDueKind.emi)
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
                onTap: () => context.push(AppRoutes.emis),
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          if (items.isEmpty)
            Text('No EMIs due this cycle.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else
            UpcomingDueList(items: items),
        ],
      ),
    );
  }
}
