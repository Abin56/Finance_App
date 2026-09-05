import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/cash_flow_providers.dart';
import '../screens/money_flow_detail_screen.dart';

/// Section 5 of the Cash Flow Center — "Cash Flow Summary". Money In
/// (income + collections), Money Out (expenses + EMI/Bill/Loan payments),
/// and Net Cash Flow for the selected [cashFlowDateRangeProvider] period —
/// one of the two sections (alongside "My Expenses") that actually obeys
/// the date-range filter, unlike Payments Due/Credit Card Statement/
/// Upcoming Payments, which stay on "what's currently owed" regardless of
/// the picked range.
class CashFlowSummaryCard extends ConsumerWidget {
  const CashFlowSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashFlow = ref.watch(cashFlowForRangeProvider);

    return ClayCard(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cash Flow Summary', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(
                child: _FlowStat(
                  label: 'Money In',
                  value: cashFlow.moneyIn,
                  color: AppColors.income,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MoneyFlowDetailScreen(direction: MoneyFlowDirection.moneyIn),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _FlowStat(
                  label: 'Money Out',
                  value: cashFlow.moneyOut,
                  color: AppColors.expense,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MoneyFlowDetailScreen(direction: MoneyFlowDirection.moneyOut),
                    ),
                  ),
                ),
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
  const _FlowStat({required this.label, required this.value, required this.color, this.onTap});

  final String label;
  final double value;
  final Color color;

  /// Opens the Money In/Out drill-down when set (Net Cash Flow has no
  /// detail of its own — it's just `moneyIn - moneyOut` — so it passes
  /// null and stays a plain, non-interactive stat).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Tone-tinted stat tile — mirrors the web app's `StatCard` pattern
    // (`bg-{tone}/8 border-{tone}/20`) instead of a flat neutral box, so
    // Money In/Out read as green/red at a glance even before the figure.
    final content = Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  CurrencyFormatter.instance.format(value),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: color.withValues(alpha: 0.6)),
            ],
          ),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
