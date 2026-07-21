import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../features/credit_cards/domain/statement_status.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/financial_view_module.dart';
import '../../domain/widget_configuration.dart';
import '../providers/expense_calculator_provider.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.financialView] — the widget users can add
/// unlimited instances of, each on its own [WidgetConfiguration.dateStrategy]
/// and [WidgetConfiguration.financialViewModule]. All the actual computation
/// lives in [financialViewResultProvider]; this widget only formats and
/// lays out what comes back.
class FinancialViewWidgetCard extends ConsumerWidget {
  const FinancialViewWidgetCard({super.key, required this.config, this.onConfigure});

  final WidgetConfiguration config;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(financialViewResultProvider(config));
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final colors = context.colors;
    final textTheme = context.textTheme;
    final percentChange = result.percentChange;
    final isNetCashFlow = config.financialViewModule == FinancialViewModule.netCashFlow;
    // For a spend-like total, a rise vs last cycle is unwelcome (red); for
    // Net Cash Flow a rise is good news (green) — the same delta means the
    // opposite thing depending on what's being measured.
    final increaseIsGood = isNetCashFlow || config.financialViewModule == FinancialViewModule.income;
    // A salary-cycle strategy gets the richer billing-cycle treatment below
    // (progress through the cycle + next card due date) instead of the plain
    // range caption every other strategy shows.
    final cycleAnchorDay = switch (config.dateStrategy) {
      SalaryCycleToDate(:final anchorDay) => anchorDay,
      SalaryCycleFull(:final anchorDay) => anchorDay,
      _ => null,
    };

    return DashboardWidgetCard(
      onTap: onConfigure,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  config.title,
                  style: textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(
                child: InputChip(
                  label: Text(
                    config.dateStrategy.label,
                    style: textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: onConfigure,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    format.format(result.amount),
                    style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (percentChange != null) ...[
                const SizedBox(width: AppSizes.sm),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.xs),
                    child: _ComparePill(percentChange: percentChange, increaseIsGood: increaseIsGood),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          if (cycleAnchorDay == null)
            Text(
              '${result.range.start.shortDate} – ${result.range.end.shortDate}',
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            )
          else ...[
            const SizedBox(height: AppSizes.sm),
            _BillingCycleIndicator(anchorDay: cycleAnchorDay),
            const _NextCardDueRow(),
          ],
          if (result.breakdown.isNotEmpty) ...[
            const SizedBox(height: AppSizes.md),
            const Divider(height: 1),
            const SizedBox(height: AppSizes.xs),
            for (final entry in result.breakdown.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Text(format.format(entry.value), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Visualizes where "today" falls inside the current anchorDay→anchorDay
/// pay cycle — a progress bar plus "Day X of Y" and days remaining, so a
/// user unfamiliar with the salary-cycle concept can read it at a glance
/// without needing the raw date range. Always derives the *full* cycle
/// window from [anchorDay]
/// (via [SalaryCycleFull]) even when the widget's own strategy is
/// [SalaryCycleToDate], since a to-date total still belongs to one full
/// 17th→17th cycle the user thinks in.
class _BillingCycleIndicator extends StatelessWidget {
  const _BillingCycleIndicator({required this.anchorDay});

  final int anchorDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;
    final now = DateTime.now();
    final cycle = SalaryCycleFull(anchorDay: anchorDay).resolve(now);
    final totalDays = cycle.end.dateOnly.difference(cycle.start.dateOnly).inDays;
    final elapsedDays = now.dateOnly.difference(cycle.start.dateOnly).inDays;
    final daysLeft = (totalDays - elapsedDays).clamp(0, totalDays);
    final progress = totalDays == 0 ? 1.0 : (elapsedDays / totalDays).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Cycle Progress',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${now.shortDate} / ${cycle.end.shortDate}',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: colors.primary.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress * 100).round()}% complete',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              daysLeft == 0 ? 'Ends today' : '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${cycle.start.shortDate} → ${cycle.end.shortDate}',
          style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// The soonest not-fully-paid card statement's due date and remaining
/// amount, shown inside the billing-cycle hero so "what do I owe next and
/// by when" sits beside "what have I spent this cycle". Hidden entirely
/// when no unpaid statement exists — never a guessed or placeholder date.
class _NextCardDueRow extends ConsumerWidget {
  const _NextCardDueRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statement = ref.watch(nextStatementDueProvider);
    if (statement == null) return const SizedBox.shrink();

    final colors = context.colors;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final status = statement.status;
    final accent = switch (status) {
      StatementStatus.overdue => AppColors.error,
      StatementStatus.dueSoon => AppColors.warning,
      _ => colors.primary,
    };
    final dueLabel = switch (status) {
      StatementStatus.overdue => 'was due ${statement.dueDate.shortDate}',
      _ => 'due ${statement.dueDate.shortDate}',
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.sm),
      child: Material(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          onTap: () => context.push('/creditCards/${statement.cardId}/statements/${statement.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: AppSizes.iconSm, color: accent),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'Card payment ${format.format(statement.remainingAmount)} $dueLabel',
                    style: context.textTheme.bodySmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparePill extends StatelessWidget {
  const _ComparePill({required this.percentChange, required this.increaseIsGood});

  final double percentChange;
  final bool increaseIsGood;

  @override
  Widget build(BuildContext context) {
    final isIncrease = percentChange >= 0;
    final isGood = isIncrease == increaseIsGood;
    final color = isGood ? AppColors.success : AppColors.error;
    final arrow = isIncrease ? '↑' : '↓';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        '$arrow ${percentChange.abs().toStringAsFixed(0)}% vs last pay period',
        style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
