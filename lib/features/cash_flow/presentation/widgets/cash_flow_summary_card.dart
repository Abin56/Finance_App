import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/cash_flow_providers.dart';
import '../screens/money_flow_detail_screen.dart';

/// Section 5 of the Cash Flow Center — "Cash Flow Summary". This is the
/// screen's one hero figure: Net Cash Flow for the selected
/// [cashFlowDateRangeProvider] period, with Money In (income + collections)
/// and Money Out (expenses + EMI/Bill/Loan payments) as supporting stats
/// underneath — one of the two sections (alongside "My Expenses") that
/// actually obeys the date-range filter, unlike Payments Due/Credit Card
/// Statement/Upcoming Payments, which stay on "what's currently owed"
/// regardless of the picked range.
class CashFlowSummaryCard extends ConsumerWidget {
  const CashFlowSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashFlow = ref.watch(cashFlowForRangeProvider);
    final flowfi = context.flowfi;
    final netColor = cashFlow.net >= 0 ? AppColors.income : AppColors.expense;

    return FlowFiCard.hero(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Net Cash Flow',
            style: context.textTheme.bodyMedium?.copyWith(
              color: flowfi.onHeroSurfaceMuted,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          FlowFiAmountText(
            CurrencyFormatter.instance.format(cashFlow.net),
            size: AmountSize.display,
            color: netColor,
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              Expanded(
                child: _HeroFlowStat(
                  label: 'Money In',
                  value: cashFlow.moneyIn,
                  color: AppColors.income,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MoneyFlowDetailScreen(
                        direction: MoneyFlowDirection.moneyIn,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _HeroFlowStat(
                  label: 'Money Out',
                  value: cashFlow.moneyOut,
                  color: AppColors.expense,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MoneyFlowDetailScreen(
                        direction: MoneyFlowDirection.moneyOut,
                      ),
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

/// A Money In/Out stat tile for the hero card — a raised tint of the hero
/// surface (rather than the standard card's tone-tinted-on-light treatment)
/// so it reads correctly against the near-black background.
class _HeroFlowStat extends StatelessWidget {
  const _HeroFlowStat({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final double value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final flowfi = context.flowfi;
    final borderRadius = BorderRadius.circular(AppSizes.radiusMd);

    final content = Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: flowfi.heroSurfaceRaised,
        borderRadius: borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  CurrencyFormatter.instance.format(value),
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppSizes.iconSm,
                  color: flowfi.onHeroSurfaceMuted,
                ),
            ],
          ),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              color: flowfi.onHeroSurfaceMuted,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
    );
  }
}
