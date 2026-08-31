import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import '../providers/upcoming_due_provider.dart';
import 'dashboard_widget_shell.dart';
import 'upcoming_payments_widget_card.dart';

/// Renders [DashboardWidgetType.splitExpenses] — others' pending shares
/// (money owed *to* the user through a split expense), reusing
/// [totalPendingSplitAmountProvider] for the headline total and the
/// [UpcomingDueKind.splitExpense] slice of [upcomingDueProvider] for the
/// per-item list, the same shared aggregation every other kind-filtered
/// dashboard card reads.
class SplitExpensesWidgetCard extends ConsumerWidget {
  const SplitExpensesWidgetCard({super.key, required this.config});

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
        .where((i) => i.kind == UpcomingDueKind.splitExpense)
        .toList();
    final total = ref.watch(totalPendingSplitAmountProvider);
    final textTheme = context.textTheme;
    final colors = context.colors;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

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
                onTap: () => context.push(AppRoutes.transactions),
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          if (total <= 0) ...[
            const SizedBox(height: AppSizes.sm),
            Text(
              'No pending split expenses.',
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ] else ...[
            const SizedBox(height: AppSizes.xs),
            Text('Owed To Me', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(format.format(total), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: AppSizes.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSizes.xs),
              UpcomingDueList(items: items),
            ],
          ],
        ],
      ),
    );
  }
}
