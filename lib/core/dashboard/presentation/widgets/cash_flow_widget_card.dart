import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/cash_flow/presentation/providers/cash_flow_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import 'dashboard_format.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.cashFlow] — this calendar month's Money In /
/// Money Out / Net, read straight from [cashFlowThisMonthProvider] (the same
/// lines the Cash Flow Center totals), plus the month's net by week from
/// [dashboardWeeklyCashFlowProvider], which buckets those same lines.
///
/// The header always names the period actually shown ("This month ·
/// October 2026"): the card has only ever displayed this month, whatever
/// its stored title or date strategy said (the old default was titled
/// "Today").
class CashFlowWidgetCard extends ConsumerWidget {
  const CashFlowWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = SectionLoad.of([
      ref.watch(transactionsStreamProvider),
      ref.watch(creditCardsStreamProvider),
      ref.watch(emisStreamProvider),
      ref.watch(loansStreamProvider),
    ]);

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            title: 'Cash flow',
            subtitle: 'This month · ${DateTime.now().monthYear}',
            actionLabel: 'Details',
            onAction: () => context.go(AppRoutes.cashFlow),
          ),
          const SizedBox(height: AppSizes.sm),
          DashboardSectionBody(
            load: load,
            skeletonRows: 1,
            skeletonLeadingHeight: 32,
            errorMessage: "Couldn't load this month's cash flow.",
            onRetry: () => invalidateDashboardSources(ref),
            builder: (context) => const _CashFlowBody(),
          ),
        ],
      ),
    );
  }
}

class _CashFlowBody extends ConsumerWidget {
  const _CashFlowBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashFlow = ref.watch(cashFlowThisMonthProvider);
    final weeks = ref.watch(dashboardWeeklyCashFlowProvider);
    final textTheme = context.textTheme;
    final colors = context.colors;
    final net = cashFlow.net;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Net',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${net > 0 ? '+' : ''}${formatRupees(net)}',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: net < 0 ? AppColors.expense : colors.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        Row(
          children: [
            Expanded(
              child: _FlowMetric(
                icon: Icons.south_west_rounded,
                label: 'Money in',
                value: cashFlow.moneyIn,
                tone: AppColors.income,
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: _FlowMetric(
                icon: Icons.north_east_rounded,
                label: 'Money out',
                value: cashFlow.moneyOut,
                tone: AppColors.expense,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        _WeeklyBars(weeks: weeks),
      ],
    );
  }
}

class _FlowMetric extends StatelessWidget {
  const _FlowMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final double value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSizes.radiusXs),
          ),
          child: Icon(icon, size: 14, color: tone),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRupees(value),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Four compact bars of the month's net per week — green above the
/// baseline, red below, height relative to the largest absolute week. No
/// axes: the exact figure is in each bar's semantics label.
class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.weeks});

  final List<WeeklyCashFlowBucket> weeks;

  static const _maxBar = 28.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;
    final peak = weeks.fold(0.0, (m, w) => w.net.abs() > m ? w.net.abs() : m);
    final today = DateTime.now().day;
    int currentWeek() => today <= 7
        ? 0
        : today <= 14
        ? 1
        : today <= 21
        ? 2
        : 3;

    Widget bar(WeeklyCashFlowBucket w, {required bool above}) {
      final show = above ? w.net > 0 : w.net < 0;
      final height = !show || peak == 0
          ? 0.0
          : (w.net.abs() / peak * _maxBar).clamp(3.0, _maxBar);
      return Align(
        alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 22,
          height: height,
          decoration: BoxDecoration(
            color: above ? AppColors.income : AppColors.expense,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            for (final w in weeks)
              Expanded(
                child: Semantics(
                  label: 'Week ${w.label}: net ${formatRupees(w.net)}',
                  child: Column(
                    children: [
                      SizedBox(height: _maxBar, child: bar(w, above: true)),
                      Container(height: 1, color: colors.outline),
                      SizedBox(height: _maxBar, child: bar(w, above: false)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSizes.xs),
        Row(
          children: [
            for (var i = 0; i < weeks.length; i++)
              Expanded(
                child: Text(
                  weeks[i].label,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: i == currentWeek()
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontWeight: i == currentWeek()
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
