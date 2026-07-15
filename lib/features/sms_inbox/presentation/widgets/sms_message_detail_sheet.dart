import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/sms_import_status.dart';
import '../../domain/sms_inbox_item.dart';

/// What the user chose in [SmsMessageDetailSheet]. The sheet itself performs
/// no work — it returns an intent and the screen runs the same handlers the
/// swipe gestures and multi-select toolbar already call.
enum SmsRowAction { convert, ignore, restore, delete }

/// Tapping a compact inbox row opens this — it carries the detail the row
/// itself no longer has room for (full SMS body, parser confidence,
/// reference number) and exposes the row's actions as real buttons, so
/// Convert stays discoverable for users who never try swiping.
class SmsMessageDetailSheet {
  static Future<SmsRowAction?> show(BuildContext context, SmsInboxItem item) {
    return showModalBottomSheet<SmsRowAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSizes.lg, 0, AppSizes.lg, AppSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.parsed?.merchantOrSender ?? item.rawMessage.address,
                      style: context.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.parsed != null)
                    Text(
                      _confidenceLabel(item.parsed!.confidence),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSizes.md),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: Text(item.rawMessage.body, style: context.textTheme.bodySmall),
              ),
              if (item.parsed?.referenceNumber != null) ...[
                const SizedBox(height: AppSizes.sm),
                Text(
                  'Ref ${item.parsed!.referenceNumber}',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.lg),
              _Actions(status: item.status, sheetContext: sheetContext),
            ],
          ),
        ),
      ),
    );
  }

  static String _confidenceLabel(double confidence) {
    if (confidence >= 0.8) return 'Clearly detected';
    return confidence >= 0.6 ? 'Likely match' : 'Best guess';
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.status, required this.sheetContext});

  final SmsImportStatus status;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    final delete = TextButton.icon(
      onPressed: () => Navigator.of(sheetContext).pop(SmsRowAction.delete),
      icon: const Icon(Icons.delete_outline_rounded, size: AppSizes.iconSm),
      label: const Text('Delete'),
      style: TextButton.styleFrom(foregroundColor: AppColors.debit),
    );

    switch (status) {
      case SmsImportStatus.pending:
        return Row(
          children: [
            delete,
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(SmsRowAction.ignore),
              child: const Text('Ignore'),
            ),
            const SizedBox(width: AppSizes.sm),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(SmsRowAction.convert),
              child: const Text('Convert'),
            ),
          ],
        );
      case SmsImportStatus.ignored:
        return Row(
          children: [
            delete,
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(SmsRowAction.restore),
              child: const Text('Restore'),
            ),
          ],
        );
      case SmsImportStatus.imported:
        return Row(
          children: [
            delete,
            const Spacer(),
            Icon(Icons.check_circle_rounded, size: AppSizes.iconSm, color: AppColors.success),
            const SizedBox(width: AppSizes.xs),
            Text(
              'Already imported',
              style: context.textTheme.labelMedium?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
            ),
          ],
        );
    }
  }
}
