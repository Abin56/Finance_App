import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/emi_installment_display.dart';

/// Row for a single EMI installment — due date, monthly payment amount, and
/// status badge. Uses [emiInstallmentStatusLabel] so an upcoming
/// installment due this month reads "Unpaid" rather than "Upcoming". When
/// the installment carries a principal/interest split, adds a secondary
/// "Amount: X · Interest: Y" line.
class EmiInstallmentTile extends StatelessWidget {
  const EmiInstallmentTile({super.key, required this.installment, this.onTap});

  final Installment installment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = installment.status;
    final label = emiInstallmentStatusLabel(status, installment.dueDate);

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
                      Text(label, style: context.textTheme.bodySmall?.copyWith(color: status.color)),
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
