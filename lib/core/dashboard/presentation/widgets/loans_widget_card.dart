import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/lending/domain/loan.dart';
import '../../../../features/lending/domain/loan_status.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.loans] — "Loans Owed To Me", the only
/// direction this codebase's Loan model supports (a [Loan] is always money
/// the user lent to someone else, repaid to the user via installments —
/// there is no "loan I took from a person" concept here; EMI is the
/// user's own installment debt to a store/bank, a separate feature).
/// Reads [activeLoansProvider]/[loanRemainingAmountProvider]/
/// [loanStatusProvider] directly rather than [upcomingDueProvider], since
/// this card shows each loan's outstanding balance owed to the user, not
/// its next installment due date.
class LoansWidgetCard extends ConsumerWidget {
  const LoansWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(activeLoansProvider);
    final totalToReceive = ref.watch(totalAmountToReceiveProvider);
    final textTheme = context.textTheme;
    final colors = context.colors;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: () => context.push(AppRoutes.loans),
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          if (loans.isEmpty) ...[
            const SizedBox(height: AppSizes.md),
            Text('No active loans.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ] else ...[
            const SizedBox(height: AppSizes.xs),
            Text(
              'Owed To Me',
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                format.format(totalToReceive),
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            const Divider(height: 1),
            for (final loan in loans) _LoanRow(loan: loan, format: format),
          ],
        ],
      ),
    );
  }
}

class _LoanRow extends ConsumerWidget {
  const _LoanRow({required this.loan, required this.format});

  final Loan loan;
  final NumberFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loanStatusProvider(loan));
    final remaining = ref.watch(loanRemainingAmountProvider(loan));
    final title = loan.name?.isNotEmpty == true ? loan.name! : 'Loan';
    final textTheme = context.textTheme;
    final colors = context.colors;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      onTap: () => context.push('/loans/${loan.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: status.color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(status.icon, size: AppSizes.iconSm, color: status.color),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(title, style: textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: AppSizes.sm),
            Text(
              format.format(remaining),
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
