import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/sms_import_status.dart';
import '../../domain/sms_inbox_item.dart';
import '../../domain/sms_transaction_category.dart';
import '../../domain/sms_transaction_direction.dart';

/// One SMS in the inbox, rendered as a compact ~76dp messaging-app row
/// (channel icon, amount, merchant, time, status chip) rather than a
/// dashboard card — so a user with thousands of bank SMS can scan the list
/// with minimal scrolling. Row actions live in the screen's swipe/long-press
/// gestures, not in per-row buttons.
class SmsMessageTile extends StatelessWidget {
  const SmsMessageTile({
    super.key,
    required this.item,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
  });

  final SmsInboxItem item;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final parsed = item.parsed;
    final direction = parsed?.direction;
    final amountColor = _amountColor(context, direction);

    return Material(
      color: selected ? context.colors.primary.withValues(alpha: 0.08) : context.colors.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
          child: Row(
            children: [
              _Leading(item: item, selectionMode: selectionMode, selected: selected, color: amountColor),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _amountLabel(parsed?.amount, direction),
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.75),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _dateTimeLabel(item.rawMessage.date),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              _StatusChip(status: item.status),
            ],
          ),
        ),
      ),
    );
  }

  Color _amountColor(BuildContext context, SmsTransactionDirection? direction) {
    if (direction == null) return context.colors.onSurface.withValues(alpha: 0.55);
    return direction == SmsTransactionDirection.credit ? AppColors.credit : AppColors.debit;
  }

  /// Beginner-friendly wording over the raw debit/credit enum — "spent" and
  /// "received" describe what actually happened to the user's money.
  String _amountLabel(double? amount, SmsTransactionDirection? direction) {
    if (amount == null || direction == null) return 'Amount unclear';
    final formatted = CurrencyFormatter.instance.format(amount);
    return direction == SmsTransactionDirection.credit ? '$formatted received' : '$formatted spent';
  }

  String _subtitle() {
    final parsed = item.parsed;
    final parts = [
      parsed?.merchantOrSender ?? item.rawMessage.address,
      ?parsed?.bankName,
      if (parsed?.maskedAccountOrCard != null) 'XX${parsed!.maskedAccountOrCard}',
    ];
    return parts.join(' • ');
  }

  String _dateTimeLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final time = TimeOfDay.fromDateTime(date);
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    final timeLabel = '$hour:$minute $period';

    final dayDelta = today.difference(day).inDays;
    if (dayDelta == 0) return 'Today • $timeLabel';
    if (dayDelta == 1) return 'Yesterday • $timeLabel';
    return '${date.day}/${date.month}/${date.year} • $timeLabel';
  }
}

/// The channel avatar (UPI / card / bank), which flips to a checkbox in
/// multi-select so the row height never changes between the two modes.
class _Leading extends StatelessWidget {
  const _Leading({required this.item, required this.selectionMode, required this.selected, required this.color});

  final SmsInboxItem item;
  final bool selectionMode;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (selectionMode) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? context.colors.primary : context.colors.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          selected ? Icons.check_rounded : Icons.circle_outlined,
          size: AppSizes.iconMd,
          color: selected ? context.colors.onPrimary : context.colors.onSurface.withValues(alpha: 0.4),
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(_icon(item.parsed?.category), size: AppSizes.iconMd, color: color),
    );
  }

  IconData _icon(SmsTransactionCategory? category) {
    switch (category) {
      case SmsTransactionCategory.upiPayment:
      case SmsTransactionCategory.upiReceive:
        return Icons.qr_code_rounded;
      case SmsTransactionCategory.cardPurchase:
      case SmsTransactionCategory.creditCardPurchase:
        return Icons.credit_card_rounded;
      case SmsTransactionCategory.atmWithdrawal:
      case SmsTransactionCategory.cashDeposit:
        return Icons.local_atm_rounded;
      case SmsTransactionCategory.walletPayment:
        return Icons.account_balance_wallet_rounded;
      case null:
        return Icons.sms_rounded;
      default:
        return Icons.account_balance_rounded;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SmsImportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        _shortLabel(status),
        style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Short forms of `SmsImportStatusX.label` — the full "Pending review" /
  /// "Already imported" copy is too wide for a chip at 360dp.
  String _shortLabel(SmsImportStatus status) {
    switch (status) {
      case SmsImportStatus.pending:
        return 'Pending';
      case SmsImportStatus.imported:
        return 'Converted';
      case SmsImportStatus.ignored:
        return 'Ignored';
    }
  }
}
