import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/emi.dart';
import '../../domain/emi_loan_type.dart';
import '../../domain/emi_status.dart';
import '../providers/emi_providers.dart';

/// Row for a single EMI — name, lender (if set), next due date, amount
/// remaining, and status badge. Swipeable to archive, handled by the screen
/// that owns the Dismissible key.
class EmiTile extends ConsumerWidget {
  const EmiTile({super.key, required this.emi, required this.onTap});

  final Emi emi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(emiStatusProvider(emi));
    final remaining = ref.watch(emiRemainingAmountProvider(emi));
    final subtitleParts = [
      if (emi.lenderName != null && emi.lenderName!.isNotEmpty) emi.lenderName!,
      'Ends ${emi.endDate.shortDate}',
    ];

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
                    Row(
                      children: [
                        Icon(emi.loanType.icon, size: AppSizes.iconSm),
                        const SizedBox(width: AppSizes.xs),
                        Expanded(child: Text(emi.name, style: context.textTheme.titleMedium)),
                      ],
                    ),
                    Text(
                      subtitleParts.join(' · '),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                        const SizedBox(width: AppSizes.xs),
                        Text(status.label, style: context.textTheme.bodySmall?.copyWith(color: status.color)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.instance.format(remaining),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'left',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.6),
                    ),
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
