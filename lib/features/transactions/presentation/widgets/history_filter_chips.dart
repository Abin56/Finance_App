import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../domain/history_entry.dart';

/// The category filters the unified History screen supports.
enum HistoryFilter { all, splitExpenses, transactions, loans, bills, emi, moneyReceived, creditCardStatements }

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
        return Icons.call_split_rounded;
      case HistoryFilter.transactions:
        return Icons.receipt_long_outlined;
      case HistoryFilter.loans:
        return Icons.handshake_outlined;
      case HistoryFilter.bills:
        return Icons.bolt_rounded;
      case HistoryFilter.emi:
        return Icons.calendar_month_outlined;
      case HistoryFilter.moneyReceived:
        return Icons.call_received_rounded;
      case HistoryFilter.creditCardStatements:
        return Icons.credit_card_rounded;
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
        return entry.category == HistoryCategory.statementGenerated || entry.category == HistoryCategory.statementPaid;
    }
  }
}

/// Horizontal row of single-select filter chips for [HistoryFilter].
class HistoryFilterChips extends StatelessWidget {
  const HistoryFilterChips({super.key, required this.selected, required this.onChanged});

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
              child: ChoiceChip(
                avatar: filter.icon == null ? null : Icon(filter.icon, size: AppSizes.iconSm),
                label: Text(filter.label),
                selected: selected == filter,
                onSelected: (_) => onChanged(filter),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
              ),
            ),
        ],
      ),
    );
  }
}
