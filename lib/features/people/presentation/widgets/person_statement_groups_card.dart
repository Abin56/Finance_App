import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../providers/person_statement_grouping_providers.dart';

/// One statement's worth of this person's pending expense shares — Part 3's
/// People-integration requirement ("group assigned expenses by statement").
/// Reuses the exact total/collected/pending shape `PersonPendingBreakdown`
/// already renders, just scoped to one statement's items instead of the
/// whole timeline.
class PersonStatementGroupsCard extends StatelessWidget {
  const PersonStatementGroupsCard({super.key, required this.groups});

  final List<StatementExpenseGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups) ...[
          _StatementGroupCard(group: group),
          const SizedBox(height: AppSizes.sm),
        ],
      ],
    );
  }
}

class _StatementGroupCard extends StatelessWidget {
  const _StatementGroupCard({required this.group});

  final StatementExpenseGroup group;

  @override
  Widget build(BuildContext context) {
    final total = group.items.fold(0.0, (sum, i) => sum + i.share);
    final collected = group.items.fold(0.0, (sum, i) => sum + i.collected);
    final pending = group.items.fold(0.0, (sum, i) => sum + i.pending);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${group.statement.periodEnd.monthYear} Statement', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          for (final item in group.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(item.expenseDescription, style: context.textTheme.bodyMedium)),
                  Text(CurrencyFormatter.instance.format(item.share), style: context.textTheme.bodyMedium),
                ],
              ),
            ),
          const Divider(height: AppSizes.lg),
          _TotalRow(label: 'Total', value: total),
          _TotalRow(label: 'Collected', value: collected),
          _TotalRow(label: 'Pending', value: pending, emphasize: true),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(CurrencyFormatter.instance.format(value), style: style),
        ],
      ),
    );
  }
}
