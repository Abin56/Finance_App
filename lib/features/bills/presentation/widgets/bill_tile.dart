import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../categories/domain/category.dart';
import '../../domain/bill.dart';
import '../../domain/bill_status.dart';

/// Row for a single bill — status-colored icon, name, due-date/category
/// subtitle, remaining amount, and a status badge. Swipeable to
/// soft-delete, handled by the screen that owns the Dismissible key.
class BillTile extends StatelessWidget {
  const BillTile({super.key, required this.bill, required this.category, required this.onTap});

  final Bill bill;
  final Category? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = bill.status;
    final subtitleParts = [
      bill.dueDate.shortDate,
      if (category != null) category!.name,
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Icon(status.icon, color: status.color),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bill.name, style: context.textTheme.titleMedium),
                    Text(
                      subtitleParts.join(' · '),
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.instance.format(bill.remainingAmount),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    status.label,
                    style: context.textTheme.bodySmall?.copyWith(color: status.color),
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
