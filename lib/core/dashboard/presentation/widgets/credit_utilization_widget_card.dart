import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import 'dashboard_format.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.creditUtilization] — aggregate credit
/// utilization across every active card, reusing
/// [totalCreditCardOutstandingProvider]/[totalCreditAvailableProvider]/
/// [creditCardStandingProvider] exactly as [CreditCardsWidgetCard] already
/// does for its own utilization bars. Distinct purpose from that card:
/// this one is scoped to the utilization/outstanding-balance picture only,
/// not per-card due dates.
///
/// The limit shown is `outstanding + available`, unchanged from before this
/// redesign (see the Dashboard audit's R5 note — whether that should become
/// the card's effective limit is a pending financial decision).
class CreditUtilizationWidgetCard extends ConsumerWidget {
  const CreditUtilizationWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  /// The conventional "keep it under 30%" band, then a warning band.
  static Color toneFor(double utilization) => utilization < 0.3
      ? AppColors.success
      : utilization < 0.75
      ? AppColors.warning
      : AppColors.error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = SectionLoad.of([
      ref.watch(creditCardsStreamProvider),
      ref.watch(accountsStreamProvider),
    ]);

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            title: config.title,
            subtitle: 'Outstanding vs credit limit',
            actionLabel: 'Cards',
            onAction: () => context.push(AppRoutes.creditCards),
          ),
          const SizedBox(height: AppSizes.sm),
          DashboardSectionBody(
            load: load,
            skeletonRows: 2,
            skeletonLeadingHeight: 24,
            errorMessage: "Couldn't load your credit cards.",
            onRetry: () => invalidateDashboardSources(ref),
            builder: (context) => const _UtilizationBody(),
          ),
        ],
      ),
    );
  }
}

class _UtilizationBody extends ConsumerWidget {
  const _UtilizationBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(activeCreditCardsProvider);
    if (cards.isEmpty) {
      return DashboardEmptyLine(
        icon: Icons.credit_card_outlined,
        message: 'No credit cards yet.',
        actionLabel: 'Add card',
        onAction: () => context.push(AppRoutes.creditCards),
      );
    }
    final outstanding = ref.watch(totalCreditCardOutstandingProvider);
    final available = ref.watch(totalCreditAvailableProvider);
    final limit = outstanding + available;
    final utilization = limit <= 0
        ? 0.0
        : (outstanding / limit).clamp(0.0, 1.0);
    final tone = CreditUtilizationWidgetCard.toneFor(utilization);
    final textTheme = context.textTheme;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${(utilization * 100).round()}%',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${formatRupees(outstanding)} of ${formatRupees(limit)} used',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        _UtilizationBar(value: utilization, tone: tone, height: 8),
        const SizedBox(height: AppSizes.md),
        for (final card in cards)
          _CardUtilizationRow(
            cardId: card.id,
            lastFourDigits: card.lastFourDigits,
          ),
      ],
    );
  }
}

class _UtilizationBar extends StatelessWidget {
  const _UtilizationBar({
    required this.value,
    required this.tone,
    required this.height,
  });

  final double value;
  final Color tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: context.colors.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(tone),
        ),
      ),
    );
  }
}

class _CardUtilizationRow extends ConsumerWidget {
  const _CardUtilizationRow({
    required this.cardId,
    required this.lastFourDigits,
  });

  final String cardId;
  final String? lastFourDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(creditCardStandingProvider(cardId));
    final limit = standing.outstanding + standing.available;
    final utilization = limit <= 0
        ? 0.0
        : (standing.outstanding / limit).clamp(0.0, 1.0);
    final textTheme = context.textTheme;
    final label = lastFourDigits == null || lastFourDigits!.isEmpty
        ? 'Card'
        : '•••• $lastFourDigits';

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      onTap: () => context.push('/creditCards/$cardId'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            Icon(
              Icons.credit_card_rounded,
              size: AppSizes.iconSm,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSizes.sm),
            SizedBox(
              width: 84,
              child: Text(
                label,
                style: textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: _UtilizationBar(
                value: utilization,
                tone: CreditUtilizationWidgetCard.toneFor(utilization),
                height: 4,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            SizedBox(
              width: 40,
              child: Text(
                '${(utilization * 100).round()}%',
                textAlign: TextAlign.right,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
