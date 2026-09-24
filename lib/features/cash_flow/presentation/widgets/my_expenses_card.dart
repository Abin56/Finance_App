import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../providers/cash_flow_providers.dart';

/// Feature 2 — "My Expenses". Answers "how much did I personally spend
/// during the selected period", counting only the user's own share of a
/// shared expense (never other participants' shares), and never EMI/Loan/
/// Bill/Credit-Card payments — those remain in their own Cash Flow
/// sections since they're scheduled obligations, not personal spending.
class MyExpensesCard extends ConsumerWidget {
  const MyExpensesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(myExpensesForRangeProvider);

    if (breakdown.total == 0) {
      return const PlaceholderCard(
        icon: Icons.person_outline_rounded,
        title: 'No personal expenses',
        message: 'Your personal spending for the selected period will appear here.',
      );
    }

    return ClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Expenses', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          Text(
            CurrencyFormatter.instance.format(breakdown.total),
            style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.expense),
          ),
          const SizedBox(height: AppSizes.lg),
          if (breakdown.personal > 0) _BreakdownRow(label: 'Personal expenses', value: breakdown.personal),
          if (breakdown.split > 0) ...[
            const SizedBox(height: AppSizes.xs),
            _BreakdownRow(label: 'My share of shared expenses', value: breakdown.split),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: context.textTheme.bodyMedium)),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
