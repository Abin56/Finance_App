import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/lending/domain/loan.dart';
import '../../../../features/lending/domain/loan_category.dart';
import '../../../../features/lending/domain/loan_direction.dart';
import '../../../../features/lending/domain/loan_status.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../domain/widget_configuration.dart';
import '../../../theme/clay_theme.dart';
import '../../../theme/clay_widgets.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.loans] — every active [Loan] regardless of
/// [LoanDirection], split into a "To Receive" total ([LoanDirection.given])
/// and a "To Pay" total ([LoanDirection.taken]); each stat line hides itself
/// when its total is zero. EMI remains a separate feature (the user's own
/// installment debt to a store/bank, not a person).
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
    final totalToPay = ref.watch(totalAmountToPayProvider);
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
            const SizedBox(height: AppSizes.sm),
            Text('No active loans.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ] else ...[
            const SizedBox(height: AppSizes.xs),
            Row(
              children: [
                if (totalToReceive > 0)
                  Expanded(child: _TotalStat(label: 'To Receive', amount: totalToReceive, format: format)),
                if (totalToReceive > 0 && totalToPay > 0) const SizedBox(width: AppSizes.md),
                if (totalToPay > 0)
                  Expanded(child: _TotalStat(label: 'To Pay', amount: totalToPay, format: format)),
              ],
            ),
            const SizedBox(height: AppSizes.xs),
            const Divider(height: 1),
            for (final loan in loans) _LoanRow(loan: loan, format: format),
          ],
        ],
      ),
    );
  }
}

class _TotalStat extends StatelessWidget {
  const _TotalStat({required this.label, required this.amount, required this.format});

  final String label;
  final double amount;
  final NumberFormat format;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.format(amount),
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
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
    final title = loan.name?.isNotEmpty == true
        ? loan.name!
        : (loan.category == LoanCategory.institutional ? (loan.institutionName ?? 'Institutional Loan') : 'Loan');
    final textTheme = context.textTheme;
    final colors = context.colors;

    return InkWell(
      borderRadius: BorderRadius.circular(AppClay.radiusSm),
      onTap: () => context.push('/loans/${loan.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
        child: Row(
          children: [
            ClayIconChip(icon: status.icon, color: status.color),
            const SizedBox(width: AppSizes.xs),
            Icon(loan.direction.icon, size: AppSizes.iconSm, color: loan.direction.color),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(title, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: AppSizes.sm),
            Text(
              format.format(remaining),
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
