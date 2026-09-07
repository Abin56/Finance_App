import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/detected_transaction.dart';

/// One row on the review screen — a checkbox, the essentials (date,
/// description, amount), a plain-language status, and — when relevant — a
/// possible-duplicate warning with quick Skip/Import-anyway actions. Tapping
/// anywhere on the row (other than the checkbox) opens the edit sheet.
class DetectedTransactionTile extends StatelessWidget {
  const DetectedTransactionTile({
    super.key,
    required this.transaction,
    required this.onToggleSelected,
    required this.onTap,
    required this.onSkipDuplicate,
    required this.onImportAnywayDuplicate,
    this.categoryName,
  });

  final DetectedTransaction transaction;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback onTap;
  final VoidCallback onSkipDuplicate;
  final VoidCallback onImportAnywayDuplicate;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    final needsReview =
        transaction.reviewStatus == DetectionReviewStatus.needsReview;
    final amountColor = transaction.type == TransactionType.income
        ? AppColors.income
        : AppColors.expense;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(
          color: transaction.isDuplicate
              ? AppColors.pending
              : context.colors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.sm,
            vertical: AppSizes.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: transaction.isSelected,
                    onChanged: (value) => onToggleSelected(value ?? false),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              transaction.date?.shortDate ?? 'Date unknown',
                              style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: AppSizes.sm),
                            Expanded(
                              child: Text(
                                transaction.description,
                                style: context.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (categoryName != null)
                          Text(
                            categoryName!,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        transaction.amount == null
                            ? '—'
                            : CurrencyFormatter.instance.format(
                                transaction.amount!,
                              ),
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _StatusChip(needsReview: needsReview),
                    ],
                  ),
                ],
              ),
              if (needsReview && transaction.missingFieldsSummary != null)
                Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: AppSizes.xs),
                  child: Text(
                    transaction.missingFieldsSummary!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: AppColors.pending,
                    ),
                  ),
                ),
              if (transaction.isDuplicate)
                _DuplicateWarning(
                  reason: transaction.duplicateReason,
                  onSkip: onSkipDuplicate,
                  onImportAnyway: onImportAnywayDuplicate,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.needsReview});
  final bool needsReview;

  @override
  Widget build(BuildContext context) {
    final color = needsReview ? AppColors.pending : AppColors.income;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          needsReview
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline_rounded,
          size: AppSizes.iconSm,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          needsReview ? 'Needs review' : 'Ready',
          style: context.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({
    required this.reason,
    required this.onSkip,
    required this.onImportAnyway,
  });

  final String? reason;
  final VoidCallback onSkip;
  final VoidCallback onImportAnyway;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: AppSizes.iconSm,
                color: AppColors.pending,
              ),
              const SizedBox(width: AppSizes.xs),
              Expanded(
                child: Text(
                  'Possible duplicate. ${reason ?? "A similar transaction already exists."}',
                  style: context.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onSkip, child: const Text('Skip')),
              TextButton(
                onPressed: onImportAnyway,
                child: const Text('Import anyway'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
