import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/history_entry.dart';

/// The category filters the unified History screen supports.
enum HistoryFilter {
  all,
  splitExpenses,
  transactions,
  loans,
  bills,
  emi,
  moneyReceived,
  creditCardStatements,
}

extension HistoryFilterX on HistoryFilter {
  String get label {
    switch (this) {
      case HistoryFilter.all:
        return 'All';
      case HistoryFilter.splitExpenses:
        return 'Shared expenses';
      case HistoryFilter.transactions:
        return 'Transactions';
      case HistoryFilter.loans:
        return 'Loans';
      case HistoryFilter.bills:
        return 'Bills';
      case HistoryFilter.emi:
        return 'EMI';
      case HistoryFilter.moneyReceived:
        return 'Money received';
      case HistoryFilter.creditCardStatements:
        return 'Card statements';
    }
  }

  IconData? get icon {
    switch (this) {
      case HistoryFilter.all:
        return null;
      case HistoryFilter.splitExpenses:
        return Icons.group_outlined;
      case HistoryFilter.transactions:
        return Icons.receipt_long_outlined;
      case HistoryFilter.loans:
        return Icons.handshake_outlined;
      case HistoryFilter.bills:
        return Icons.receipt_outlined;
      case HistoryFilter.emi:
        return Icons.calendar_month_outlined;
      case HistoryFilter.moneyReceived:
        return Icons.payments_outlined;
      case HistoryFilter.creditCardStatements:
        return Icons.credit_card_outlined;
    }
  }

  bool matches(HistoryEntry entry) {
    switch (this) {
      case HistoryFilter.all:
        return true;
      case HistoryFilter.splitExpenses:
        return entry.category == HistoryCategory.splitExpense;
      case HistoryFilter.transactions:
        return entry.category == HistoryCategory.transaction;
      case HistoryFilter.loans:
        return entry.category == HistoryCategory.loan;
      case HistoryFilter.bills:
        return entry.category == HistoryCategory.bill;
      case HistoryFilter.emi:
        return entry.category == HistoryCategory.emi;
      case HistoryFilter.moneyReceived:
        return entry.category == HistoryCategory.moneyReceived;
      case HistoryFilter.creditCardStatements:
        return entry.category == HistoryCategory.statementGenerated ||
            entry.category == HistoryCategory.statementPaid;
    }
  }
}

/// Horizontal row of single-select filter chips for [HistoryFilter].
///
/// Theme V2 "Filter Chips" spec: unselected = neutral surface + thin border,
/// selected = solid lime fill + near-black text — a plain [ChoiceChip] can't
/// express the solid-fill selected state on its own (the app-wide chip theme
/// covers most chips, but this row spells it out explicitly since it's the
/// primary example of the pattern), so this renders its own pill shape.
class HistoryFilterChips extends StatelessWidget {
  const HistoryFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final HistoryFilter selected;
  final ValueChanged<HistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in HistoryFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSizes.xs),
              child: _HistoryFilterPill(
                icon: filter.icon,
                label: filter.label,
                selected: selected == filter,
                onTap: () => onChanged(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryFilterPill extends StatelessWidget {
  const _HistoryFilterPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? AppColors.onLime : colors.onSurface;

    return Material(
      color: selected ? colors.primary : colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        side: BorderSide(color: selected ? Colors.transparent : colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSizes.iconSm, color: foreground),
                const SizedBox(width: AppSizes.xs),
              ],
              Text(
                label,
                style: context.textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
