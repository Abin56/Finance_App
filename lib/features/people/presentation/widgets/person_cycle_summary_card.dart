import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../domain/person_cycle_summary.dart';

/// The People Dashboard card for one person — Previous Cycle, Current
/// Cycle, and Overall sections, built from [PersonCycleSummary].
class PersonCycleSummaryCard extends StatelessWidget {
  const PersonCycleSummaryCard({super.key, required this.summary});

  final PersonCycleSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cycle Summary', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          _SectionLabel('Previous Cycle'),
          _SummaryRow(label: 'Outstanding', amount: summary.previousOutstanding),
          _SummaryRow(label: 'Carry Forward', amount: summary.previousCarryForward),
          _SummaryRow(label: 'Total Paid', amount: summary.previousTotalPaid),
          _SummaryRow(label: 'Remaining Balance', amount: summary.previousRemaining, emphasize: true),
          const Divider(height: AppSizes.lg),
          _SectionLabel('Current Cycle'),
          _SummaryRow(label: 'Total Split Expenses', amount: summary.currentTotalSplitExpenses),
          _SummaryRow(label: 'Total Paid', amount: summary.currentTotalPaid),
          _SummaryRow(label: 'Remaining Balance', amount: summary.currentRemaining, emphasize: true),
          const Divider(height: AppSizes.lg),
          _SectionLabel('Overall'),
          _SummaryRow(label: 'Total You Owe', amount: summary.totalYouOwe),
          _SummaryRow(label: 'Total They Owe', amount: summary.totalTheyOwe),
          _SummaryRow(label: 'Net Balance', amount: summary.netBalance, emphasize: true),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Text(
        label,
        style: context.textTheme.labelLarge?.copyWith(
          color: context.colors.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.amount, this.emphasize = false});

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(CurrencyFormatter.instance.format(amount.abs()), style: style),
        ],
      ),
    );
  }
}
