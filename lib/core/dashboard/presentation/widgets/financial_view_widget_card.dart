import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/financial_view_module.dart';
import '../../domain/widget_configuration.dart';
import '../providers/expense_calculator_provider.dart';
import '../../../theme/clay_theme.dart';
import '../../../theme/clay_widgets.dart';
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
    // Only the default "Spent This Pay Period" hero instance gets the
    // gradient-hero treatment — other Financial View instances the user
    // adds (e.g. "Income · Last 30 Days") stay as regular cards so the
    // gradient hero remains a single, unambiguous focal point.
    final isHero = cycleAnchorDay != null && config.financialViewModule == FinancialViewModule.combinedExpenses;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          config.title,
          style: textTheme.labelLarge?.copyWith(
            color: isHero ? Colors.white.withValues(alpha: 0.85) : null,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSizes.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: _DateStrategyChip(label: config.dateStrategy.label, isHero: isHero, onTap: onConfigure),
        ),
        const SizedBox(height: AppSizes.md),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.format(result.amount),
            style: (isHero ? textTheme.headlineMedium : textTheme.titleLarge)?.copyWith(
              fontWeight: isHero ? FontWeight.w800 : FontWeight.w700,
              color: isHero ? Colors.white : null,
              letterSpacing: isHero ? -0.5 : null,
            ),
          ),
        ),
        if (percentChange != null) ...[
          const SizedBox(height: AppSizes.xs),
          _ComparePill(percentChange: percentChange, increaseIsGood: increaseIsGood, isHero: isHero),
        ],
        const SizedBox(height: AppSizes.xs),
        if (cycleAnchorDay == null)
          Text(
            '${result.range.start.shortDate} – ${result.range.end.shortDate}',
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          )
        else ...[
          const SizedBox(height: AppSizes.md),
          _BillingCycleIndicator(anchorDay: cycleAnchorDay, isHero: isHero),
        ],
        if (result.breakdown.isNotEmpty) ...[
          const SizedBox(height: AppSizes.md),
          Divider(height: 1, color: isHero ? Colors.white.withValues(alpha: 0.2) : null),
          const SizedBox(height: AppSizes.sm),
          for (final entry in result.breakdown.entries)
            _BreakdownRow(label: entry.key, amount: entry.value, format: format, isHero: isHero),
        ],
      ],
    );

    return isHero
        ? DashboardWidgetGradientCard(
            onTap: onConfigure,
            child: Padding(padding: const EdgeInsets.all(AppSizes.lg), child: content),
          )
        : DashboardWidgetCard(onTap: onConfigure, child: content);
  }
}

/// Semantic color for a Financial View breakdown line — matches the same
/// module labels [_breakdownFor] in `expense_calculator_provider.dart`
/// always emits, so each row gets a consistent colored dot rather than a
/// bare text row.
Color _breakdownColor(String label) {
  switch (label) {
    case 'My Expenses':
      return AppClay.expense;
    case 'Shared Expenses':
      return AppClay.warning;
    case 'Bills':
      return AppClay.accent;
    case 'EMIs':
      return AppClay.secondary;
    case 'Loans':
      return AppClay.warning;
    case 'Credit Card Payments':
      return AppClay.primary;
    default:
      return AppClay.expense;
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, required this.amount, required this.format, required this.isHero});

  final String label;
  final double amount;
  final NumberFormat format;
  final bool isHero;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final labelColor = isHero ? Colors.white.withValues(alpha: 0.85) : context.colors.onSurfaceVariant;
    final valueColor = isHero ? Colors.white : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: _breakdownColor(label), shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: labelColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            format.format(amount),
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _DateStrategyChip extends StatelessWidget {
  const _DateStrategyChip({required this.label, required this.isHero, this.onTap});

  final String label;
  final bool isHero;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final fg = isHero ? Colors.white : context.colors.onSurfaceVariant;
    final bg = isHero ? Colors.white.withValues(alpha: 0.16) : context.colors.surfaceContainerHighest;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
          child: Text(
            label,
            style: textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
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
  const _BillingCycleIndicator({required this.anchorDay, required this.isHero});

  final int anchorDay;
  final bool isHero;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final now = DateTime.now();
    final cycle = SalaryCycleFull(anchorDay: anchorDay).resolve(now);
    final totalDays = cycle.end.dateOnly.difference(cycle.start.dateOnly).inDays;
    final elapsedDays = now.dateOnly.difference(cycle.start.dateOnly).inDays;
    final daysLeft = (totalDays - elapsedDays).clamp(0, totalDays);
    final progress = totalDays == 0 ? 1.0 : (elapsedDays / totalDays).clamp(0.0, 1.0);
    final primaryColor = isHero ? Colors.white : context.colors.onSurface;
    final mutedColor = isHero ? Colors.white.withValues(alpha: 0.75) : context.colors.onSurfaceVariant;
    final trackColor = isHero ? Colors.white.withValues(alpha: 0.24) : context.colors.primary.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Cycle Progress',
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: primaryColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Flexible(
              child: Text(
                '${now.shortDate} / ${cycle.end.shortDate}',
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: primaryColor),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        ClayProgressBar(
          value: progress,
          height: 7,
          trackColor: trackColor,
          colors: isHero ? [Colors.white, Colors.white] : [AppClay.secondary, AppClay.primary],
        ),
        const SizedBox(height: AppSizes.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                '${(progress * 100).round()}% complete',
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: primaryColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Flexible(
              child: Text(
                daysLeft == 0 ? 'Ends today' : '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
                style: textTheme.bodySmall?.copyWith(color: mutedColor),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${cycle.start.shortDate} → ${cycle.end.shortDate}',
          style: textTheme.labelSmall?.copyWith(color: mutedColor),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ComparePill extends StatelessWidget {
  const _ComparePill({required this.percentChange, required this.increaseIsGood, required this.isHero});

  final double percentChange;
  final bool increaseIsGood;
  final bool isHero;

  @override
  Widget build(BuildContext context) {
    final isIncrease = percentChange >= 0;
    final isGood = isIncrease == increaseIsGood;
    final color = isHero ? Colors.white : (isGood ? AppClay.success : AppClay.danger);
    final arrow = isIncrease ? '↑' : '↓';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
      decoration: BoxDecoration(
        color: isHero ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        '$arrow ${percentChange.abs().toStringAsFixed(0)}% vs last cycle',
        style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
