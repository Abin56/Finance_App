import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../features/transactions/domain/history_entry.dart';

extension SplitExpenseHistoryStatusColor on SplitExpenseHistoryStatus {
  Color get color {
    switch (this) {
      case SplitExpenseHistoryStatus.completed:
        return AppColors.success;
      case SplitExpenseHistoryStatus.pending:
        return AppColors.pending;
      case SplitExpenseHistoryStatus.partial:
        return AppColors.warning;
      case SplitExpenseHistoryStatus.overdue:
        return AppColors.error;
    }
  }
}

/// A small tinted pill rendering a split/assigned expense's aggregate
/// [SplitExpenseHistoryStatus] — the one widget every expense-facing surface
/// (Contact Ledger rows, Expense Details, the Expense Updated dialog, the
/// shared-expenses list) should use, so "Pending"/"Partly Paid"/"Overdue"/
/// "Paid" always looks identical no matter which screen shows it. Mirrors
/// [MoneyDirectionBadge]'s shape (icon + label + color, `compact` for dense
/// rows) rather than inventing a second badge convention.
class ExpenseStatusPill extends StatelessWidget {
  const ExpenseStatusPill({super.key, required this.status, this.compact = false});

  final SplitExpenseHistoryStatus status;

  /// Smaller padding/text for dense rows (e.g. inline in a list tile)
  /// instead of a standalone card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(
        status.label,
        style: (compact ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
