import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/payment_allocation_type.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/loan_financial_history_action.dart';

class LoanFinancialHistoryTile extends StatelessWidget {
  const LoanFinancialHistoryTile({
    super.key,
    required this.action,
    this.accountLabel,
  });

  final LoanFinancialHistoryAction action;
  final String? accountLabel;

  @override
  Widget build(BuildContext context) {
    final event = action.reamortizationEvent;
    final color = action.reversed
        ? context.colors.onSurface.withValues(alpha: 0.55)
        : _color;
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: color, size: AppSizes.iconSm),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(_title, style: context.textTheme.titleMedium),
              ),
              Text(
                CurrencyFormatter.instance.format(action.amount),
                style: context.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: [
              Text(action.date.shortDate, style: context.textTheme.bodySmall),
              if (accountLabel != null)
                Text(accountLabel!, style: context.textTheme.bodySmall),
              if (action.reversed)
                Text(
                  action.reversedAt == null
                      ? 'Reversed'
                      : 'Reversed ${action.reversedAt!.shortDate}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (action.allocations.length > 1 ||
              action.kind == LoanFinancialHistoryKind.principalPrepayment) ...[
            const SizedBox(height: AppSizes.sm),
            for (final allocation in action.allocations)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        allocation.allocationType ==
                                PaymentAllocationType.principalPrepayment
                            ? 'Principal'
                            : 'EMI #${allocation.installmentSequenceNumber}',
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.instance.format(allocation.amount),
                      style: context.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
          if (event != null) ...[
            const Divider(height: AppSizes.lg),
            _change(
              context,
              'Principal',
              CurrencyFormatter.instance.format(event.principalBefore),
              CurrencyFormatter.instance.format(event.principalAfter),
            ),
            _change(
              context,
              'Remaining installments',
              '${event.installmentCountBefore}',
              '${event.installmentCountAfter}',
            ),
            Text(
              action.kind == LoanFinancialHistoryKind.additionalDisbursement
                  ? 'Policy: Hold Tenure'
                  : 'Policy: Reduce Tenure',
              style: context.textTheme.bodySmall,
            ),
          ],
          if (action.note.isNotEmpty) ...[
            const SizedBox(height: AppSizes.xs),
            Text(
              action.note,
              style: context.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _change(
    BuildContext context,
    String label,
    String before,
    String after,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textTheme.bodySmall)),
          Text('$before → $after', style: context.textTheme.bodySmall),
        ],
      ),
    );
  }

  String get _title => switch (action.kind) {
    LoanFinancialHistoryKind.regularEmi => 'Regular EMI',
    LoanFinancialHistoryKind.partialEmi => 'Partial EMI',
    LoanFinancialHistoryKind.advanceEmi => 'Advance EMI',
    LoanFinancialHistoryKind.multiInstallmentPayment => 'Payment',
    LoanFinancialHistoryKind.principalPrepayment => 'Principal Prepayment',
    LoanFinancialHistoryKind.additionalDisbursement =>
      'Additional Disbursement',
  };

  IconData get _icon => switch (action.kind) {
    LoanFinancialHistoryKind.additionalDisbursement =>
      Icons.add_circle_outline_rounded,
    LoanFinancialHistoryKind.principalPrepayment => Icons.trending_down_rounded,
    LoanFinancialHistoryKind.advanceEmi => Icons.fast_forward_rounded,
    _ => Icons.payments_outlined,
  };

  Color get _color => switch (action.kind) {
    LoanFinancialHistoryKind.additionalDisbursement => AppColors.info,
    LoanFinancialHistoryKind.principalPrepayment => AppColors.success,
    LoanFinancialHistoryKind.partialEmi => AppColors.warning,
    _ => AppColors.success,
  };
}
