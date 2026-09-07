import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../../shared/widgets/states/transaction_flag_badge.dart';
import '../../../accounts/domain/account.dart';
import '../../../categories/domain/category.dart';
import '../../domain/transaction.dart' as domain;
import '../../domain/transaction_type.dart';

/// Row for a single transaction — category icon, category + account name,
/// signed amount in income/expense color, and time of day. Wrapped in a
/// [Dismissible] by the screen that owns the swipe-to-delete key.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.category,
    required this.account,
    required this.onTap,
    this.linkedPersonName,
  });

  final domain.Transaction transaction;
  final Category? category;
  final Account? account;
  final VoidCallback onTap;

  /// The name of the person [domain.Transaction.linkedPersonId] resolves to,
  /// pre-looked-up by the caller — same "pass in already-resolved display
  /// data" pattern as [category]/[account]. Null whenever there's no linked
  /// person, so most callers don't need to pass anything.
  final String? linkedPersonName;

  @override
  Widget build(BuildContext context) {
    final color = category != null
        ? Color(category!.colorValue)
        : context.colors.primary;
    final sign = transaction.type == TransactionType.income ? '+' : '-';

    return FlowFiCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: FlowFiListTile(
        leading: FlowFiIconChip(
          icon: category?.icon ?? Icons.category_outlined,
          color: color,
        ),
        title: Text(
          category?.name ?? 'Uncategorized',
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              account?.name ?? 'Unknown account',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.flowfi.textTertiary,
              ),
            ),
            if (transaction.notes.isNotEmpty)
              Text(
                transaction.notes,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.flowfi.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (linkedPersonName != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 12,
                    color: context.flowfi.textTertiary,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      linkedPersonName!,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.flowfi.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (transaction.excludeFromCalculations ||
                transaction.accountingMonth != null) ...[
              const SizedBox(height: 2),
              TransactionFlagBadge(
                excludeFromCalculations: transaction.excludeFromCalculations,
                date: transaction.dateTime,
                accountingMonth: transaction.accountingMonth,
                compact: true,
              ),
            ],
          ],
        ),
        trailing: FlowFiAmountText(
          '$sign${CurrencyFormatter.instance.format(transaction.amount)}',
          size: AmountSize.body,
          color: transaction.type.color,
        ),
        trailingSubtitle: Text(
          TimeOfDay.fromDateTime(transaction.dateTime).format(context),
          style: context.textTheme.bodySmall?.copyWith(
            color: context.flowfi.textTertiary,
          ),
        ),
      ),
    );
  }
}
