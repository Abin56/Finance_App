import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../../../credit_cards/presentation/providers/credit_card_report_providers.dart';

/// Credit Card section of the Reports screen — Monthly Card Spend,
/// Statement History, Category Spend (reuses the screen's own category
/// breakdown, filtered to card transactions, passed in rather than
/// recomputed here), Friend Pending inside statement, plus Interest
/// Paid/Late Fees when the user has manually logged either (this app has no
/// interest-calculation engine, so both are simply omitted when empty
/// rather than shown as 0 — mirrors [EmiReportSection]'s conditional
/// rendering).
class CreditCardReportSection extends ConsumerWidget {
  const CreditCardReportSection({super.key, required this.periodStart, required this.periodEnd});

  final DateTime periodStart;
  final DateTime periodEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = (start: periodStart, end: periodEnd);
    final monthlySpend = ref.watch(creditCardSpendForRangeProvider(range));
    final statementCount = ref.watch(statementCountForRangeProvider(range));
    final friendPending = ref.watch(totalFriendPendingInStatementsProvider);
    final interestCharged = ref.watch(interestChargedForRangeProvider(range));
    final lateFees = ref.watch(lateFeesForRangeProvider(range));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Credit Cards'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ReportStat(
                      label: 'Monthly Card Spend',
                      value: CurrencyFormatter.instance.format(monthlySpend),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(child: _ReportStat(label: 'Statement History', value: '$statementCount')),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              _ReportStat(
                label: 'Friend Pending inside statement',
                value: CurrencyFormatter.instance.format(friendPending),
              ),
              if (interestCharged > 0 || lateFees > 0) ...[
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: [
                    if (interestCharged > 0)
                      Expanded(
                        child: _ReportStat(
                          label: 'Interest Paid',
                          value: CurrencyFormatter.instance.format(interestCharged),
                        ),
                      ),
                    if (interestCharged > 0 && lateFees > 0) const SizedBox(width: AppSizes.sm),
                    if (lateFees > 0)
                      Expanded(
                        child: _ReportStat(label: 'Late Fees', value: CurrencyFormatter.instance.format(lateFees)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
