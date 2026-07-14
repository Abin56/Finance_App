import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/domain/payment_urgency.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../providers/cash_flow_providers.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';

/// Section 1 of the Cash Flow Center — "Payments Due This Month". Breaks
/// the month's total obligation into Credit Cards / EMI / Loans / Bills
/// rows (Other Scheduled Payments hidden until a real data source exists),
/// each showing Due/Paid/Remaining, with an overall Total Due/Paid/
/// Remaining footer.
class PaymentsDueCard extends ConsumerWidget {
  const PaymentsDueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(totalDueThisMonthProvider);
    final rows = [
      (label: 'Credit Cards', breakdown: ref.watch(creditCardDueThisMonthBreakdownProvider), route: AppRoutes.creditCards),
      (label: 'EMI', breakdown: ref.watch(emiDueThisMonthBreakdownProvider), route: AppRoutes.emis),
      (label: 'Loans', breakdown: ref.watch(loanDueThisMonthBreakdownProvider), route: AppRoutes.loans),
      (label: 'Bills', breakdown: ref.watch(billsDueThisMonthBreakdownProvider), route: AppRoutes.bills),
      (
        label: 'Other Scheduled Payments',
        breakdown: ref.watch(otherScheduledDueThisMonthBreakdownProvider),
        route: AppRoutes.bills,
      ),
    ].where((r) => r.breakdown.due > 0).toList();

    if (total.due == 0) {
      return const PlaceholderCard(
        icon: Icons.event_available_rounded,
        title: 'Nothing due this month',
        message: 'Credit card bills, EMIs, loans, and bills due this month will appear here.',
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payments Due This Month', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          Text(
            CurrencyFormatter.instance.format(total.due),
            style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSizes.lg),
          for (final row in rows) ...[
            _PaymentRow(
              label: row.label,
              breakdown: row.breakdown,
              onTap: () => context.push(row.route),
            ),
            const SizedBox(height: AppSizes.sm),
          ],
          const Divider(height: AppSizes.lg),
          Row(
            children: [
              Expanded(child: _FooterStat(label: 'Total Due', value: total.due)),
              Expanded(
                child: _FooterStat(label: 'Already Paid', value: total.paid, color: PaymentUrgency.paid.color),
              ),
              Expanded(
                child: _FooterStat(label: 'Remaining', value: total.remaining, color: PaymentUrgency.overdue.color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.label, required this.breakdown, required this.onTap});

  final String label;
  final DueCategoryBreakdown breakdown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: context.textTheme.bodyMedium),
            ),
            Expanded(
              child: Text(
                CurrencyFormatter.instance.format(breakdown.due),
                textAlign: TextAlign.end,
                style: context.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: Text(
                CurrencyFormatter.instance.format(breakdown.remaining),
                textAlign: TextAlign.end,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: breakdown.remaining > 0 ? PaymentUrgency.overdue.color : PaymentUrgency.paid.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}
