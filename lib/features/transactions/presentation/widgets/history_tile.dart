import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/money_direction_indicator.dart';
import '../../domain/history_entry.dart';

/// One row in the unified History feed — same visual language as
/// `LedgerTimelineTile`/`PaymentTile`/`EmiPaymentHistoryTile` (tinted icon,
/// title/subtitle, signed trailing amount), so History reads consistently
/// with every other timeline in the app. A [HistoryCategory.splitExpense]
/// entry additionally shows a "Split expense" badge, participant count, and
/// the live amount still to collect from participants.
class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry, this.onTap});

  final HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = entry.isCredit ? AppColors.credit : AppColors.debit;
    final sign = entry.isCredit ? '+' : '-';
    final splitDetail = entry.splitExpenseDetail;

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(entry.icon, color: color, size: AppSizes.iconSm),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title, style: context.textTheme.titleMedium),
                        if (splitDetail == null)
                          Text(
                            entry.subtitle.isNotEmpty ? '${entry.category.label} · ${entry.subtitle}' : entry.category.label,
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: context.colors.onSurface.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '$sign${CurrencyFormatter.instance.format(entry.amount)}',
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
              if (splitDetail != null) ...[
                const SizedBox(height: AppSizes.sm),
                Wrap(
                  spacing: AppSizes.xs,
                  runSpacing: AppSizes.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Chip(
                      icon: Icons.call_split_rounded,
                      label: 'Total ${CurrencyFormatter.instance.format(entry.amount)}',
                      color: context.colors.primary,
                    ),
                    _Chip(
                      icon: Icons.person_rounded,
                      label: 'My share ${CurrencyFormatter.instance.format(splitDetail.myShare)}',
                      color: context.colors.onSurface.withValues(alpha: 0.7),
                    ),
                    _Chip(
                      icon: Icons.group_outlined,
                      label: '${splitDetail.participantCount} people',
                      color: context.colors.onSurface.withValues(alpha: 0.7),
                    ),
                    if (splitDetail.collected > 0)
                      _Chip(
                        icon: Icons.check_circle_outline_rounded,
                        label: '${CurrencyFormatter.instance.format(splitDetail.collected)} collected',
                        color: AppColors.success,
                      ),
                    if (splitDetail.amountToCollect > 0)
                      _Chip(
                        icon: Icons.hourglass_top_rounded,
                        label: '${CurrencyFormatter.instance.format(splitDetail.amountToCollect)} to collect',
                        color: AppColors.pending,
                      ),
                    MoneyDirectionBadge(direction: _directionFor(splitDetail.status), compact: true),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A split expense the user paid for is always money coming back to
  /// them, so [SplitExpenseHistoryStatus.pending]/`.partial`/`.overdue` map
  /// onto [MoneyDirection.toReceive]/`.partial`/`.toReceive` — never
  /// `.toPay`, since `HistoryBuilder` only builds this detail for expenses
  /// the user fronted. `overdue` doesn't get its own [MoneyDirection] (that
  /// enum is about direction, not urgency) — the badge still reads
  /// "To Receive"; urgency is conveyed by [ExpenseStatusPill] elsewhere on
  /// the row instead.
  MoneyDirection _directionFor(SplitExpenseHistoryStatus status) {
    switch (status) {
      case SplitExpenseHistoryStatus.pending:
      case SplitExpenseHistoryStatus.overdue:
        return MoneyDirection.toReceive;
      case SplitExpenseHistoryStatus.partial:
        return MoneyDirection.partial;
      case SplitExpenseHistoryStatus.completed:
        return MoneyDirection.completed;
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
