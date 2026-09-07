import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/cash_flow/presentation/providers/cash_flow_providers.dart';
import '../../domain/widget_configuration.dart';
import '../../../theme/clay_theme.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.cashFlow] — a dashboard-sized digest of the
/// Cash Flow Center's Section 5 (Money In/Out/Net), reusing
/// [cashFlowThisMonthProvider] directly. Deliberately scoped to just this
/// one figure rather than mirroring the Cash Flow Center's other sections
/// (Payments Due, Money To Receive, timeline, statement summary) — those
/// stay the full screen's job, this card only summarizes.
///
/// Deliberately NOT wired to `dashboardFinancialSummaryProvider` (unlike
/// [NetWorthWidgetCard]): that composition provider also watches
/// `netWorthProvider` (Accounts), which pulls in a Firebase-backed stream
/// this card previously had no dependency on at all — swapping to it would
/// silently add a Firebase requirement wherever this widget is rendered
/// (confirmed by `test/core/dashboard/new_widget_cards_small_layout_test.dart`,
/// which renders this card with no Firebase override and failed once this
/// was tried), so this is a real behavior/dependency change, not a clean
/// drop-in, and is left reading [cashFlowThisMonthProvider] directly.
class CashFlowWidgetCard extends ConsumerWidget {
  const CashFlowWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashFlow = ref.watch(cashFlowThisMonthProvider);
    final summary = (moneyIn: cashFlow.moneyIn, moneyOut: cashFlow.moneyOut, netCashFlow: cashFlow.net);
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
                onTap: () => context.go(AppRoutes.cashFlow),
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(child: _FlowStat(label: 'Money In', value: summary.moneyIn, color: AppClay.income)),
              const SizedBox(width: AppSizes.md),
              Expanded(child: _FlowStat(label: 'Money Out', value: summary.moneyOut, color: AppClay.expense)),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(
                child: Text('Net Cash Flow', style: textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: AppSizes.sm),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    format.format(summary.netCashFlow),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: summary.netCashFlow >= 0 ? AppClay.income : AppClay.expense,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowStat extends StatelessWidget {
  const _FlowStat({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Container(
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppClay.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              format.format(value),
              style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
