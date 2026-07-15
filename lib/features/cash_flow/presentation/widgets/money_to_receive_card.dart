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

/// Section 2 of the Cash Flow Center — "Money To Receive". Breaks total
/// outstanding receivables into Split Expenses / People Pending Payments /
/// Loan Recoveries rows (Assigned Expenses / Other Receivables hidden until
/// a real data source exists), each tapping through to its detail screen.
class MoneyToReceiveCard extends ConsumerWidget {
  const MoneyToReceiveCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(totalMoneyToReceiveProvider);
    final rows = [
      (
        label: 'Split Expenses',
        breakdown: ref.watch(splitExpensesReceivableProvider),
        onTap: () => context.goNamed(AppRoutes.transactionsName, queryParameters: {'filter': 'splitExpenses'}),
      ),
      (
        label: 'Assigned Expenses',
        breakdown: ref.watch(assignedExpensesReceivableProvider),
        onTap: () => context.goNamed(AppRoutes.transactionsName, queryParameters: {'filter': 'splitExpenses'}),
      ),
      (
        label: 'People Pending Payments',
        breakdown: ref.watch(peoplePendingReceivableProvider),
        onTap: () => context.push(AppRoutes.creditors),
      ),
      (
        label: 'Loan Recoveries',
        breakdown: ref.watch(loanRecoveriesReceivableProvider),
        onTap: () => context.push(AppRoutes.loans),
      ),
      (
        label: 'Other Money to Receive',
        breakdown: ref.watch(otherReceivablesProvider),
        onTap: () => context.push(AppRoutes.people),
      ),
    ].where((r) => r.breakdown.amount > 0).toList();

    if (total == 0) {
      return const PlaceholderCard(
        icon: Icons.call_received_rounded,
        title: 'Nothing owed to you',
        message: 'Split expenses, people, and loans you\'re owed money for will appear here.',
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Money To Receive', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          Text(
            CurrencyFormatter.instance.format(total),
            style: context.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: PaymentUrgency.paid.color,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          for (final row in rows)
            InkWell(
              onTap: row.onTap,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(row.label, style: context.textTheme.bodyMedium)),
                    Text(
                      CurrencyFormatter.instance.format(row.breakdown.amount),
                      style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: AppSizes.xs),
                    Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.4)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
