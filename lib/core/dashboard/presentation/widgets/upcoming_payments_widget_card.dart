import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../shared/domain/payment_urgency.dart';
import '../../../../shared/widgets/states/payment_urgency_badge.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import '../providers/upcoming_due_provider.dart';
import '../../../theme/clay_theme.dart';
import '../../../theme/clay_widgets.dart';
import 'dashboard_widget_shell.dart';
import 'upcoming_due_breakdown_sheet.dart';

/// Renders [DashboardWidgetType.upcomingPayments] — the same
/// [upcomingDueProvider] aggregation [FinancialViewWidgetCard]'s Upcoming
/// Due section shows, as its own standalone widget for a dashboard that
/// doesn't also want a Financial View card on the same salary-cycle
/// anchor. No calculation of its own: purely a different presentation of
/// the same provider.
class UpcomingPaymentsWidgetCard extends ConsumerWidget {
  const UpcomingPaymentsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchorDay = switch (config.dateStrategy) {
      SalaryCycleToDate(:final anchorDay) => anchorDay,
      SalaryCycleFull(:final anchorDay) => anchorDay,
      _ => 17,
    };
    final cycle = SalaryCycleFull(anchorDay: anchorDay).resolve(DateTime.now());
    final items = ref.watch(upcomingDueProvider((start: cycle.start, end: cycle.end)));
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSizes.sm),
          if (items.isEmpty)
            Text(
              'Nothing due this cycle.',
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            )
          else
            UpcomingDueList(items: items),
        ],
      ),
    );
  }
}

/// The carried-over/this-cycle split every screen showing [UpcomingDueItem]s
/// renders identically — factored out of [FinancialViewWidgetCard] so
/// [UpcomingPaymentsWidgetCard] doesn't duplicate the same grouping/row
/// logic a second time.
class UpcomingDueList extends StatelessWidget {
  const UpcomingDueList({super.key, required this.items});

  final List<UpcomingDueItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final carriedOver = items.where((i) => i.isCarriedOver).toList();
    final thisCycle = items.where((i) => !i.isCarriedOver).toList();
    final textTheme = context.textTheme;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (carriedOver.isNotEmpty) ...[
          Text(
            'Carried Over From Previous Cycle',
            style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppClay.warning),
          ),
          for (final item in carriedOver) UpcomingDueRow(item: item),
        ],
        if (thisCycle.isNotEmpty) ...[
          if (carriedOver.isNotEmpty) const SizedBox(height: AppSizes.sm),
          Text(
            'Due This Cycle',
            style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.onSurfaceVariant),
          ),
          for (final item in thisCycle) UpcomingDueRow(item: item),
        ],
      ],
    );
  }
}

IconData iconForUpcomingDueKind(UpcomingDueKind kind) {
  switch (kind) {
    case UpcomingDueKind.creditCard:
      return Icons.credit_card_rounded;
    case UpcomingDueKind.emi:
      return Icons.calendar_month_rounded;
    case UpcomingDueKind.loan:
      return Icons.account_balance_rounded;
    case UpcomingDueKind.bill:
      return Icons.bolt_rounded;
    case UpcomingDueKind.splitExpense:
      return Icons.call_split_rounded;
  }
}

String dueLabelFor(DateTime dueDate) {
  final days = dueDate.dateOnly.difference(DateTime.now().dateOnly).inDays;
  if (days < 0) return 'Overdue by ${-days}d';
  if (days == 0) return 'Due today';
  return 'Due in ${days}d';
}

void openUpcomingDueItem(BuildContext context, UpcomingDueItem item) {
  switch (item.kind) {
    case UpcomingDueKind.creditCard:
      context.push('/creditCards/${item.routeId}/statements/${item.secondaryRouteId}');
    case UpcomingDueKind.emi:
      context.push('/emis/${item.routeId}');
    case UpcomingDueKind.loan:
      context.push('/loans/${item.routeId}');
    case UpcomingDueKind.bill:
      context.push('/bills/${item.routeId}');
    case UpcomingDueKind.splitExpense:
      context.push('/transactions/${item.routeId}');
  }
}

class UpcomingDueRow extends StatelessWidget {
  const UpcomingDueRow({super.key, required this.item});

  final UpcomingDueItem item;

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final colors = context.colors;
    final textTheme = context.textTheme;
    final tint = item.urgency.color;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppClay.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppClay.radiusMd),
        onTap: () => UpcomingDueBreakdownSheet.show(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.xs, horizontal: AppSizes.xs),
          child: Row(
            children: [
              ClayIconChip(icon: iconForUpcomingDueKind(item.kind), color: tint, glow: true),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dueLabelFor(item.dueDate),
                      style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PaymentUrgencyBadge(urgency: item.urgency, compact: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    format.format(item.remaining),
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: colors.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
