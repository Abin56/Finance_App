import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Row for a single installment — due date, amount, status badge. When the
/// installment carries a principal/interest split (interest-bearing loans),
/// adds a secondary "Amount: X · Interest: Y" line; otherwise renders
/// exactly as a plain installment.
class LoanInstallmentTile extends StatelessWidget {
  const LoanInstallmentTile({super.key, required this.installment, this.onTap});

  final Installment installment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = installment.status;

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payment ${installment.sequenceNumber}', style: context.textTheme.titleMedium),
                    Text(
                      installment.dueDate.fullDate,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    if (installment.principalPortion != null)
                      Text(
                        'Amount: ${CurrencyFormatter.instance.format(installment.principalPortion!)}'
                        ' · Interest: ${CurrencyFormatter.instance.format(installment.interestPortion ?? 0)}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.instance.format(installment.amountDue),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                      const SizedBox(width: AppSizes.xs),
                      Text(status.label, style: context.textTheme.bodySmall?.copyWith(color: status.color)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
