import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../providers/cash_flow_providers.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';

/// Section 3 of the Cash Flow Center — "Credit Card Statement Summary". One
/// expandable card per active card: statement period, generation status,
/// payment due date, current bill, minimum due, outstanding, and available
/// credit.
class CreditCardStatementSummaryCard extends ConsumerWidget {
  const CreditCardStatementSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(activeCardStatementSummariesProvider);

    if (summaries.isEmpty) {
      return PlaceholderCard(
        icon: Icons.credit_card_outlined,
        title: 'No credit cards yet',
        message: 'Add a card to track its statement cycle and outstanding balance.',
        onTap: () => context.push(AppRoutes.creditCards),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final summary in summaries) ...[
          _CardStatementTile(summary: summary),
          if (summary != summaries.last) const SizedBox(height: AppSizes.sm),
        ],
      ],
    );
  }
}

class _CardStatementTile extends StatelessWidget {
  const _CardStatementTile({required this.summary});

  final CardStatementSummary summary;

  @override
  Widget build(BuildContext context) {
    final card = summary.card;
    final statement = summary.latestStatement;
    final displayName = card.lastFourDigits != null ? 'Card •••• ${card.lastFourDigits}' : 'Credit Card';

    return AppCard(
      onTap: () => context.push('${AppRoutes.creditCards}/${card.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(displayName, style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          if (statement == null)
            Text(
              'No statement yet',
              style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Statement Period',
                    value: '${statement.periodStart.shortDate} – ${statement.periodEnd.shortDate}',
                  ),
                ),
                Expanded(child: _Stat(label: 'Due Date', value: statement.dueDate.shortDate)),
              ],
            ),
            const SizedBox(height: AppSizes.sm),
            Row(
              children: [
                Expanded(
                  child: _Stat(label: 'Current Bill', value: CurrencyFormatter.instance.format(statement.totalAmount)),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Minimum Due',
                    value: statement.minimumDue == null
                        ? '—'
                        : CurrencyFormatter.instance.format(statement.minimumDue!),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(
                child: _Stat(label: 'Outstanding', value: CurrencyFormatter.instance.format(summary.standing.outstanding)),
              ),
              Expanded(
                child: _Stat(
                  label: 'Available Credit',
                  value: CurrencyFormatter.instance.format(summary.standing.available),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}
