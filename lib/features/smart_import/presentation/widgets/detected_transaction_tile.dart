import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../categories/domain/category.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/detected_transaction.dart';

/// One row on the review screen — a checkbox, a category icon chip (same
/// [FlowFiIconChip]/[FlowFiListTile]/[FlowFiAmountText] primitives
/// [TransactionTile] uses, so a detected row looks like the same app rather
/// than a separate one), the essentials (date, description, amount), a
/// plain-language status, and — when relevant — a possible-duplicate warning
/// with quick Skip/Import-anyway actions. Tapping anywhere on the row (other
/// than the checkbox) opens the edit sheet.
class DetectedTransactionTile extends StatelessWidget {
  const DetectedTransactionTile({
    super.key,
    required this.transaction,
    required this.onToggleSelected,
    required this.onTap,
    required this.onSkipDuplicate,
    required this.onImportAnywayDuplicate,
    this.category,
  });

  final DetectedTransaction transaction;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback onTap;
  final VoidCallback onSkipDuplicate;
  final VoidCallback onImportAnywayDuplicate;

  /// The resolved category this row is suggested/assigned to — null shows a
  /// neutral "uncategorized" chip, exactly like [TransactionTile] does for a
  /// real transaction with no category.
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final needsReview =
        transaction.reviewStatus == DetectionReviewStatus.needsReview;
    final chipColor = category != null
        ? Color(category!.colorValue)
        : context.colors.primary;
    final sign = transaction.type == TransactionType.income ? '+' : '-';
    final amountColor = transaction.type == TransactionType.income
        ? AppColors.income
        : AppColors.expense;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: transaction.isDuplicate
            ? Border.all(color: AppColors.pending)
            : null,
      ),
      child: FlowFiCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FlowFiListTile(
              onTap: onTap,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: transaction.isSelected,
                    onChanged: (value) => onToggleSelected(value ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: AppSizes.xs),
                  FlowFiIconChip(
                    icon: category?.icon ?? Icons.category_outlined,
                    color: chipColor,
                  ),
                ],
              ),
              title: Text(
                transaction.description,
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                category?.name ?? 'Uncategorized',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.flowfi.textTertiary,
                ),
              ),
              trailing: FlowFiAmountText(
                transaction.amount == null
                    ? '—'
                    : CurrencyFormatter.instance.format(transaction.amount!),
                prefix: transaction.amount == null ? null : sign,
                size: AmountSize.body,
                color: amountColor,
              ),
              trailingSubtitle: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    transaction.date?.shortDate ?? 'Date unknown',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.flowfi.textTertiary,
                    ),
                  ),
                  const SizedBox(width: AppSizes.xs),
                  _StatusChip(needsReview: needsReview),
                ],
              ),
            ),
            if (needsReview && transaction.missingFieldsSummary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md,
                  0,
                  AppSizes.md,
                  AppSizes.sm,
                ),
                child: Text(
                  transaction.missingFieldsSummary!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: AppColors.pending,
                  ),
                ),
              ),
            if (transaction.isDuplicate)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md,
                  0,
                  AppSizes.md,
                  AppSizes.md,
                ),
                child: _DuplicateWarning(
                  reason: transaction.duplicateReason,
                  onSkip: onSkipDuplicate,
                  onImportAnyway: onImportAnywayDuplicate,
                ),
              ),
          ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Row(
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
            style: context.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onSkip,
                child: const Text('Skip'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
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
