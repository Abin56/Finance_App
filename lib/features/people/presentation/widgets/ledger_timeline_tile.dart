import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/person_timeline_entry.dart';

/// One entry in a person's unified timeline — icon/title, signed amount,
/// note, date, optional status badge, and the running pending amount
/// immediately after this entry (computed by the caller as it folds over
/// the sorted list via `PersonTimelineBuilder.runningBalances`; there is
/// only one place balance-as-of-a-point is computed, so the timeline UI can
/// never disagree with `Person.currentBalance`).
///
/// [onTap] always means "view/edit details" — predictable and consistent
/// with every other list in the app (History, Transactions). Settling is a
/// separate, always-visible action: when [canMarkSettled] and
/// [onMarkSettled] are both supplied (only for split/assigned-expense
/// entries the caller has resolved a participant/installment for — see
/// `PersonStatementScreen`), a "Settle" button appears on the row alongside
/// the amount, so both actions are one tap away without either overloading
/// or hiding the other behind a menu.
class LedgerTimelineTile extends StatelessWidget {
  const LedgerTimelineTile({
    super.key,
    required this.entry,
    required this.balanceAfter,
    required this.onTap,
    this.canMarkSettled = false,
    this.onMarkSettled,
  });

  final PersonTimelineEntry entry;
  final double balanceAfter;
  final VoidCallback onTap;

  /// Whether the resolved participant still has a remaining amount —
  /// controls whether the "Settle" button appears.
  final bool canMarkSettled;
  final VoidCallback? onMarkSettled;

  @override
  Widget build(BuildContext context) {
    final signed = entry.signedAmount;
    final sign = signed >= 0 ? '+' : '-';
    final color = entry.color;
    final showSettleButton = canMarkSettled && onMarkSettled != null;

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
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Icon(entry.icon, color: color, size: AppSizes.iconSm),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.title,
                            style: context.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.status != null) ...[
                          const SizedBox(width: AppSizes.xs),
                          Flexible(child: _StatusBadge(status: entry.status!)),
                        ],
                      ],
                    ),
                    Text(
                      entry.note.isNotEmpty ? '${entry.date.shortDate} · ${entry.note}' : entry.date.shortDate,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${CurrencyFormatter.instance.format(signed.abs())}',
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
                  ),
                  Text(
                    'Amount Left: ${CurrencyFormatter.instance.format(balanceAfter)}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  if (showSettleButton) ...[
                    const SizedBox(height: AppSizes.xs),
                    IntrinsicWidth(
                      child: SizedBox(
                        height: 28,
                        child: OutlinedButton(
                          onPressed: onMarkSettled,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
                            visualDensity: VisualDensity.compact,
                            textStyle: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Settle'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final PersonTimelineStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              style: context.textTheme.labelSmall?.copyWith(color: status.color, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
