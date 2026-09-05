import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../providers/cash_flow_providers.dart';
import '../screens/my_expenses_history_screen.dart';

/// "My Expenses" — a separate section from every other Cash Flow card,
/// answering "how much did I personally spend during the selected period?"
/// Deliberately NOT the same figure as [CashFlowSummaryCard]'s Money Out:
/// that also counts EMI/Loan/Bill payments (scheduled obligations) and, for
/// a shared expense, the full amount that left the account — this card
/// counts only my own share of each expense (see [Expense.myShare]), split
/// into "Personal" (expenses with no other participants) and "My share of
/// shared expenses" so the split-expense math is visible, not just implied.
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MyExpensesHistoryScreen()),
        ),
        child: ClayCard(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('My Expenses', style: context.textTheme.titleMedium)),
                  Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                CurrencyFormatter.instance.format(breakdown.total),
                style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Only your share of shared expenses is counted here',
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              ),
              if (breakdown.personal > 0 || breakdown.split > 0) ...[
                const SizedBox(height: AppSizes.lg),
                if (breakdown.personal > 0) _BreakdownRow(label: 'Personal expenses', value: breakdown.personal),
                if (breakdown.split > 0) ...[
                  const SizedBox(height: AppSizes.sm),
                  _BreakdownRow(label: 'My share of shared expenses', value: breakdown.split),
                ],
              ],
            ],
          ),
        ),
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
