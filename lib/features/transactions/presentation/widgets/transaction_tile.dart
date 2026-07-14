import 'package:flutter/material.dart';

import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
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
  });

  final domain.Transaction transaction;
  final Category? category;
  final Account? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = category != null ? Color(category!.colorValue) : context.colors.primary;
    final sign = transaction.type == TransactionType.income ? '+' : '-';

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(category?.icon ?? Icons.category_outlined, color: color),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category?.name ?? 'Uncategorized', style: context.textTheme.titleMedium),
                    Text(
                      account?.name ?? 'Unknown account',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    if (transaction.notes.isNotEmpty)
                      Text(
                        transaction.notes,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurface.withValues(alpha: 0.5),
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
                    '$sign${CurrencyFormatter.instance.format(transaction.amount)}',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: transaction.type.color,
                    ),
                  ),
                  Text(
                    TimeOfDay.fromDateTime(transaction.dateTime).format(context),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
