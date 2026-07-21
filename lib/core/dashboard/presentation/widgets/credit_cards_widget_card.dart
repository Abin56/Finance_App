import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/credit_cards/domain/credit_card_profile.dart';
import '../../../../features/credit_cards/domain/statement.dart';
import '../../../../features/credit_cards/domain/statement_status.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.creditCards] — a usage summary per card:
/// utilization bar (outstanding against the card's limit, shared-limit
/// aware via [creditCardStandingProvider]) plus that card's soonest unpaid
/// statement due date. Header totals reuse the existing dashboard
/// aggregation providers, which already count a shared Visa/RuPay facility
/// exactly once.
class CreditCardsWidgetCard extends ConsumerWidget {
  const CreditCardsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  static const _maxVisible = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(activeCreditCardsProvider);
    final textTheme = context.textTheme;
    final colors = context.colors;

    if (cards.isEmpty) {
      return DashboardWidgetCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(config.title, style: textTheme.labelLarge),
            const SizedBox(height: AppSizes.sm),
            Text(
              'No credit cards yet.',
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final outstanding = ref.watch(totalCreditCardOutstandingProvider);
    final available = ref.watch(totalCreditAvailableProvider);
    final visible = cards.take(_maxVisible).toList();
    final remaining = cards.length - visible.length;
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
                onTap: () => context.push(AppRoutes.creditCards),
                child: Text(
                  'See all ›',
                  style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(label: 'Outstanding', amount: outstanding, color: AppColors.expense),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _SummaryStat(label: 'Available Credit', amount: available, color: AppColors.income),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          const Divider(height: 1),
          for (final card in visible) _CardUsageRow(card: card, format: format),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.xs),
              child: Text(
                '+$remaining more',
                style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.amount, required this.color});

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.format(amount),
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}

class _CardUsageRow extends ConsumerWidget {
  const _CardUsageRow({required this.card, required this.format});

  final CreditCardProfile card;
  final NumberFormat format;

  /// This card's soonest not-fully-paid statement, or null when everything
  /// is paid off — only real statements ever produce a due date here.
  Statement? _nextDue(List<Statement> statements) {
    Statement? soonest;
    for (final statement in statements) {
      if (statement.remainingAmount <= 0) continue;
      if (soonest == null || statement.dueDate.isBefore(soonest.dueDate)) soonest = statement;
    }
    return soonest;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(creditCardStandingProvider(card.id));
    final account = ref.watch(accountForCardProvider(card.id));
    final statements = ref.watch(statementsWithLiveTotalsProvider(card.id));
    final nextDue = _nextDue(statements);
    final textTheme = context.textTheme;
    final colors = context.colors;

    final limit = standing.outstanding + standing.available;
    final utilization = limit <= 0 ? 0.0 : (standing.outstanding / limit).clamp(0.0, 1.0);
    final utilizationColor = utilization < 0.3
        ? AppColors.success
        : utilization < 0.75
            ? AppColors.warning
            : AppColors.error;
    final name = account?.name ?? 'Card';
    final last4 = card.lastFourDigits;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      onTap: () => context.push('/creditCards/${card.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card_rounded, size: AppSizes.iconSm, color: colors.onSurfaceVariant),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    last4 == null || last4.isEmpty ? name : '$name •••• $last4',
                    style: textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Text(
                  format.format(standing.outstanding),
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusPill),
              child: LinearProgressIndicator(
                value: utilization,
                minHeight: 4,
                color: utilizationColor,
                backgroundColor: utilizationColor.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${(utilization * 100).round()}% of limit used',
                    style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                if (nextDue != null)
                  Text(
                    nextDue.status == StatementStatus.overdue
                        ? 'Overdue · was due ${nextDue.dueDate.shortDate}'
                        : 'Due ${nextDue.dueDate.shortDate}',
                    style: textTheme.bodySmall?.copyWith(
                      color: switch (nextDue.status) {
                        StatementStatus.overdue => AppColors.error,
                        StatementStatus.dueSoon => AppColors.warning,
                        _ => colors.onSurfaceVariant,
                      },
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
