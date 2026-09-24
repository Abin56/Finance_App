import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan_payment_history_entry.dart';

/// One row in a loan's Payment History section — same visual language as
/// `EmiPaymentHistoryTile` (40x40 tinted status icon, title/subtitle,
/// trailing amount + secondary stat), but payer attribution is resolved
/// from the real [LoanPaymentHistoryEntry.payerPersonId] field rather than
/// parsed out of a note string.
class LoanPaymentHistoryTile extends ConsumerWidget {
  const LoanPaymentHistoryTile({super.key, required this.entry, this.onTap});

  final LoanPaymentHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = entry.status;
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final payerPersonId = entry.payerPersonId;
    String payerLabel = 'Paid by You';
    if (payerPersonId != null) {
      final match = people.where((p) => p.id == payerPersonId);
      payerLabel = match.isNotEmpty ? 'Paid by ${match.first.name}' : 'Paid by You';
    }

    final subtitleParts = <String>[
      entry.date.shortDate,
      payerLabel,
      if (entry.note.isNotEmpty) entry.note,
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Icon(status.icon, color: status.color, size: AppSizes.iconSm),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payment ${entry.installmentSequenceNumber}', style: context.textTheme.titleMedium),
                    Text(
                      subtitleParts.join(' · '),
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.instance.format(entry.amount),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: status.color),
                  ),
                  Text(
                    'Amount left: ${CurrencyFormatter.instance.format(entry.remainingBalanceAfter)}',
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5)),
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
