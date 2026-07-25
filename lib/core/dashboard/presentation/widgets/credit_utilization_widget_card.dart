import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.creditUtilization] — aggregate credit
/// utilization across every active card, reusing
/// [totalCreditCardOutstandingProvider]/[totalCreditAvailableProvider]/
/// [creditCardStandingProvider] exactly as [CreditCardsWidgetCard] already
/// does for its own utilization bars. Distinct purpose from that card:
/// this one is scoped to the utilization/outstanding-balance picture only,
/// not per-card due dates.
class CreditUtilizationWidgetCard extends ConsumerWidget {
  const CreditUtilizationWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

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
            Text('No credit cards yet.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      );
    }

    final outstanding = ref.watch(totalCreditCardOutstandingProvider);
    final available = ref.watch(totalCreditAvailableProvider);
    final limit = outstanding + available;
    final utilization = limit <= 0 ? 0.0 : (outstanding / limit).clamp(0.0, 1.0);
    final utilizationColor = utilization < 0.3
        ? AppColors.success
        : utilization < 0.75
            ? AppColors.warning
            : AppColors.error;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return DashboardWidgetCard(
      backgroundColor: utilizationColor.withValues(alpha: 0.05),
      showHairline: false,
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
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(utilization * 100).round()}% Utilized',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: utilizationColor),
              ),
              Text(
                '${format.format(outstanding)} / ${format.format(limit)}',
                style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
            child: LinearProgressIndicator(
              value: utilization,
              minHeight: 10,
              color: utilizationColor,
              backgroundColor: utilizationColor.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const Divider(height: 1),
          for (final card in cards) _CardUtilizationRow(cardId: card.id, lastFourDigits: card.lastFourDigits),
        ],
      ),
    );
  }
}

class _CardUtilizationRow extends ConsumerWidget {
  const _CardUtilizationRow({required this.cardId, required this.lastFourDigits});

  final String cardId;
  final String? lastFourDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(creditCardStandingProvider(cardId));
    final limit = standing.outstanding + standing.available;
    final utilization = limit <= 0 ? 0.0 : (standing.outstanding / limit).clamp(0.0, 1.0);
    final textTheme = context.textTheme;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: colors.onSurfaceVariant.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.credit_card_rounded, size: AppSizes.iconSm, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              lastFourDigits == null || lastFourDigits!.isEmpty ? 'Card' : '•••• $lastFourDigits',
              style: textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${(utilization * 100).round()}%',
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
