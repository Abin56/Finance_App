import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../features/bills/presentation/providers/bill_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../shared/domain/payment_urgency.dart';
import '../../../../shared/widgets/states/payment_urgency_badge.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import '../providers/upcoming_due_provider.dart';
import '../../../constants/app_colors.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import 'dashboard_format.dart';
import 'dashboard_widget_shell.dart';
import 'upcoming_due_breakdown_sheet.dart';

/// Renders [DashboardWidgetType.upcomingPayments] — the same
/// [upcomingDueProvider] aggregation [FinancialViewWidgetCard]'s Upcoming
/// Due section shows, as its own standalone widget for a dashboard that
/// doesn't also want a Financial View card on the same salary-cycle
/// anchor. No calculation of its own: purely a different presentation of
/// the same provider — the header's count/total only add up the outgoing
/// rows' own `remaining`.
class UpcomingPaymentsWidgetCard extends ConsumerWidget {
  const UpcomingPaymentsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  /// Rows shown per group before "View all" takes over.
  static const _maxRows = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchorDay = switch (config.dateStrategy) {
      SalaryCycleToDate(:final anchorDay) => anchorDay,
      SalaryCycleFull(:final anchorDay) => anchorDay,
      _ => 17,
    };
    final cycle = SalaryCycleFull(anchorDay: anchorDay).resolve(DateTime.now());
    final load = SectionLoad.of([
      ref.watch(creditCardsStreamProvider),
      ref.watch(emisStreamProvider),
      ref.watch(loansStreamProvider),
      ref.watch(billsStreamProvider),
      ref.watch(expensesStreamProvider),
    ]);
    final items = ref.watch(
      upcomingDueProvider((start: cycle.start, end: cycle.end)),
    );
    final outgoing = items
        .where((i) => i.kind != UpcomingDueKind.splitExpense)
        .toList();
    final total = outgoing.fold(0.0, (s, i) => s + i.remaining);
    final hasMore =
        outgoing.length > _maxRows || items.length - outgoing.length > _maxRows;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            title: config.title,
            subtitle: load.isReady && outgoing.isNotEmpty
                ? '${outgoing.length} due this cycle · ${formatRupees(total)}'
                : 'This cycle · ${cycle.start.shortDate} – '
                      '${cycle.end.shortDate}',
            actionLabel: hasMore ? 'View all' : null,
            onAction: hasMore ? () => _AllDueSheet.show(context, items) : null,
          ),
          const SizedBox(height: AppSizes.xs),
          DashboardSectionBody(
            load: load,
            errorMessage: "Couldn't load what's due.",
            onRetry: () => invalidateDashboardSources(ref),
            builder: (context) => items.isEmpty
                ? const DashboardEmptyLine(
                    icon: Icons.event_available_rounded,
                    message: 'Nothing due this cycle.',
                  )
                : UpcomingDueList(items: items, maxRowsPerGroup: _maxRows),
          ),
        ],
      ),
    );
  }
}

/// Every upcoming item, ungrouped by row limits — the "View all" sheet.
class _AllDueSheet extends StatelessWidget {
  const _AllDueSheet({required this.items});

  final List<UpcomingDueItem> items;

  static Future<void> show(BuildContext context, List<UpcomingDueItem> items) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AllDueSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            0,
            AppSizes.lg,
            AppSizes.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Upcoming payments', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.sm),
              UpcomingDueList(items: items),
            ],
          ),
        ),
      ),
    );
  }
}

/// The carried-over/this-cycle split every screen showing [UpcomingDueItem]s
/// renders identically — factored out of [FinancialViewWidgetCard] so
/// [UpcomingPaymentsWidgetCard] doesn't duplicate the same grouping/row
/// logic a second time.
///
/// Split-expense rows are money owed TO me (a participant's share), so when
/// they appear alongside real payments they get their own "Coming in from
/// people" group instead of being listed as something I have to pay.
/// Presentation only — the items themselves are untouched.
class UpcomingDueList extends StatelessWidget {
  const UpcomingDueList({super.key, required this.items, this.maxRowsPerGroup});

  final List<UpcomingDueItem> items;

  /// Caps rows per group (null = all), for compact dashboard cards.
  final int? maxRowsPerGroup;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final outgoing = items
        .where((i) => i.kind != UpcomingDueKind.splitExpense)
        .toList();
    final incoming = items
        .where((i) => i.kind == UpcomingDueKind.splitExpense)
        .toList();
    // A receivables-only list (the Split Expenses widget) keeps the plain
    // carried-over / this-cycle grouping.
    if (outgoing.isEmpty || incoming.isEmpty) {
      return _GroupedDueList(items: items, maxRows: maxRowsPerGroup);
    }
    final shownIncoming = maxRowsPerGroup == null
        ? incoming
        : incoming.take(maxRowsPerGroup!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupedDueList(items: outgoing, maxRows: maxRowsPerGroup),
        const SizedBox(height: AppSizes.md),
        Text(
          'Coming In From People',
          style: context.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.income,
          ),
        ),
        for (final item in shownIncoming) UpcomingDueRow(item: item),
      ],
    );
  }
}

class _GroupedDueList extends StatelessWidget {
  const _GroupedDueList({required this.items, this.maxRows});

  final List<UpcomingDueItem> items;
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    List<UpcomingDueItem> cap(List<UpcomingDueItem> list) =>
        maxRows == null ? list : list.take(maxRows!).toList();
    final carriedOver = cap(items.where((i) => i.isCarriedOver).toList());
    final thisCycle = cap(items.where((i) => !i.isCarriedOver).toList());
    final textTheme = context.textTheme;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (carriedOver.isNotEmpty) ...[
          Text(
            'Carried Over From Previous Cycle',
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
          for (final item in carriedOver) UpcomingDueRow(item: item),
        ],
        if (thisCycle.isNotEmpty) ...[
          if (carriedOver.isNotEmpty) const SizedBox(height: AppSizes.sm),
          Text(
            'Due This Cycle',
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
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
      context.push(
        '/creditCards/${item.routeId}/statements/${item.secondaryRouteId}',
      );
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
    final format = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final colors = context.colors;
    final textTheme = context.textTheme;
    final tint = item.urgency.color;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => UpcomingDueBreakdownSheet.show(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSizes.xs,
            horizontal: AppSizes.xs,
          ),
          child: Row(
            children: [
              FlowFiIconChip(
                icon: iconForUpcomingDueKind(item.kind),
                color: tint,
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dueLabelFor(item.dueDate),
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PaymentUrgencyBadge(
                        urgency: item.urgency,
                        compact: true,
                      ),
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
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: AppSizes.iconSm,
                color: colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
