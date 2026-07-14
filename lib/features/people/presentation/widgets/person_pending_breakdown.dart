import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../domain/person_timeline_entry.dart';

/// Pending amount split by category — subtotal per [PersonTimelineCategory]
/// plus the overall total, folded once from the same timeline entries the
/// screen already loads (no separate query).
class PersonPendingBreakdown extends StatelessWidget {
  const PersonPendingBreakdown({super.key, required this.entries});

  final List<PersonTimelineEntry> entries;

  double _subtotalFor(PersonTimelineCategory category) =>
      entries.where((e) => e.category == category).fold(0.0, (total, e) => total + e.signedAmount);

  @override
  Widget build(BuildContext context) {
    final subtotals = {for (final category in PersonTimelineCategory.values) category: _subtotalFor(category)};
    final overall = subtotals.values.fold(0.0, (total, v) => total + v);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Amount Left breakdown', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          for (final category in PersonTimelineCategory.values)
            if (subtotals[category] != 0) _BreakdownRow(label: category.label, amount: subtotals[category]!),
          const Divider(height: AppSizes.lg),
          _BreakdownRow(label: 'Total Amount Left', amount: overall, emphasize: true),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, required this.amount, this.emphasize = false});

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
