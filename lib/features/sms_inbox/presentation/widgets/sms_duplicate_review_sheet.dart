import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/sms_duplicate_reason.dart';
import '../../domain/sms_inbox_item.dart';
import '../providers/sms_inbox_providers.dart';

/// What the user decided about a flagged duplicate. Returned to the screen,
/// which owns the actual mutation — this sheet only asks.
enum SmsDuplicateAction {
  /// Remove the duplicate row entirely.
  delete,

  /// The rules were wrong: un-flag it back into the normal inbox.
  ///
  /// Named for its effect rather than the user's assertion ("not a
  /// duplicate"), matching FlowFi's existing "Move to Trash" phrasing for
  /// relocating an item between buckets. Deliberately *not* "Restore": that
  /// already means un-ignore in this same feature (`SmsRowAction.restore`)
  /// and recover-from-trash everywhere else, and one word must not carry
  /// three meanings.
  moveToInbox,

  /// The bank really did charge twice — convert it like any other message.
  convertAnyway,

  /// Leave it, but stop showing it as pending.
  ignore,
}

/// Reviews one flagged duplicate against the original it was matched to.
///
/// Shows both messages in full plus the rule that fired, because this sheet
/// is asking the user to ratify a judgement the app made about their data.
/// They cannot do that from a verdict alone — they need to see the evidence
/// and be able to overrule it, which is what [SmsDuplicateAction.moveToInbox]
/// is for.
class SmsDuplicateReviewSheet extends ConsumerWidget {
  const SmsDuplicateReviewSheet._({required this.duplicate});

  final SmsInboxItem duplicate;

  static Future<SmsDuplicateAction?> show(BuildContext context, SmsInboxItem duplicate) {
    return showModalBottomSheet<SmsDuplicateAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SmsDuplicateReviewSheet._(duplicate: duplicate),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original = ref.watch(smsDuplicateOriginalProvider(duplicate.id));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSizes.lg, 0, AppSizes.lg, AppSizes.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Possible duplicate', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.xs),
              Text(
                duplicate.duplicateReason?.explanation ?? 'Matches a message already in your inbox.',
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSizes.md),

              if (original != null) ...[
                _MessageBlock(label: 'Original', item: original),
                const SizedBox(height: AppSizes.sm),
              ] else
                // The original was deleted, so there is nothing left to
                // compare against. Say so rather than showing a lone message
                // under a "duplicate" heading it can no longer justify.
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: Text(
                    'The original message has since been deleted.',
                    style: context.textTheme.bodySmall?.copyWith(color: AppColors.pending),
                  ),
                ),

              _MessageBlock(label: 'This message', item: duplicate, highlighted: true),
              const SizedBox(height: AppSizes.lg),

              // Delete leads: it's the expected outcome for a real duplicate.
              // It's an outlined rather than filled button because the safe
              // choice here is still the user's to make, not the app's.
              _Action(
                icon: Icons.delete_outline_rounded,
                label: 'Delete duplicate',
                description: 'Remove this message. Your original stays.',
                color: AppColors.debit,
                onTap: () => Navigator.of(context).pop(SmsDuplicateAction.delete),
              ),
              _Action(
                icon: Icons.move_to_inbox_outlined,
                label: 'Move to Inbox',
                description: "It isn't a duplicate — convert it like any other message.",
                onTap: () => Navigator.of(context).pop(SmsDuplicateAction.moveToInbox),
              ),
              _Action(
                icon: Icons.bolt_rounded,
                label: 'Convert anyway',
                description: 'Use this if you were genuinely charged twice.',
                onTap: () => Navigator.of(context).pop(SmsDuplicateAction.convertAnyway),
              ),
              _Action(
                icon: Icons.visibility_off_outlined,
                label: 'Ignore',
                description: 'Keep it, but stop showing it as pending.',
                onTap: () => Navigator.of(context).pop(SmsDuplicateAction.ignore),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One message rendered in full — amount, when, sender and raw body. The raw
/// body is the point: two messages the rules call identical often differ in
/// it, and that difference is the only thing that lets the user tell a real
/// double charge from a re-send.
class _MessageBlock extends StatelessWidget {
  const _MessageBlock({required this.label, required this.item, this.highlighted = false});

  final String label;
  final SmsInboxItem item;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final amount = item.parsed?.amount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: highlighted ? 0.7 : 0.35),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: highlighted ? Border.all(color: context.colors.primary.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (amount != null)
                Text(
                  CurrencyFormatter.instance.format(amount),
                  style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            '${item.rawMessage.address} • ${item.rawMessage.date.sectionLabel}',
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(item.rawMessage.body, style: context.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? context.colors.onSurface;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: effective),
      title: Text(label, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: effective)),
      subtitle: Text(description, style: context.textTheme.bodySmall),
      onTap: onTap,
    );
  }
}
