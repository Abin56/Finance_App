import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../providers/cash_flow_providers.dart';

/// Section 5 of the Cash Flow Center — "This Month Cash Flow". Money In
/// (income + collections), Money Out (expenses + EMI/Bill/Loan payments),
/// and Net Cash Flow for the current calendar month.
class CashFlowSummaryCard extends ConsumerWidget {
  const CashFlowSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashFlow = ref.watch(cashFlowThisMonthProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This Month Cash Flow', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _FlowStat(label: 'Money In', value: cashFlow.moneyIn, color: AppColors.income),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _FlowStat(label: 'Money Out', value: cashFlow.moneyOut, color: AppColors.expense),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          _FlowStat(
            label: 'Net Cash Flow',
            value: cashFlow.net,
            color: cashFlow.net >= 0 ? AppColors.income : AppColors.expense,
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
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(AppSizes.radiusLg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CurrencyFormatter.instance.format(value),
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
