import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../domain/unified_workspace_model.dart';

class UnifiedAgreementSummaryCard extends StatelessWidget {
  const UnifiedAgreementSummaryCard({super.key, required this.summary});
  final UnifiedAgreementSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'I Owe',
        summary.liabilityPrincipal,
        Icons.north_east_rounded,
        context.colors.error,
        null,
      ),
      (
        'Owed to Me',
        summary.receivablePrincipal,
        Icons.south_west_rounded,
        context.colors.primary,
        null,
      ),
      (
        'Due Soon',
        summary.dueSoonAmount,
        Icons.event_outlined,
        context.colors.tertiary,
        summary.dueSoonCount,
      ),
      (
        'Overdue',
        summary.overdueAmount,
        Icons.warning_amber_rounded,
        context.colors.error,
        summary.overdueCount,
      ),
    ];
    return FlowFiCard.soft(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / 2;
          return Wrap(
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: _SummaryItem(
                    label: item.$1,
                    amount: item.$2,
                    icon: item.$3,
                    color: item.$4,
                    count: item.$5,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    this.count,
  });
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count == null ? label : '$label · $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyFormatter.instance.format(amount),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
