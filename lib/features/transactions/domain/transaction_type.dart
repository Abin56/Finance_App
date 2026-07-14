import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Whether a transaction adds to ([income]) or subtracts from ([expense])
/// its account's balance. [Transaction.amount] is always stored positive;
/// this enum is the single source of the sign applied during balance math.
enum TransactionType { income, expense }

extension TransactionTypeX on TransactionType {
  static TransactionType fromName(String name) =>
      TransactionType.values.firstWhere((t) => t.name == name, orElse: () => TransactionType.expense);

  String get label {
    switch (this) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionType.income:
        return Icons.arrow_downward_rounded;
      case TransactionType.expense:
        return Icons.arrow_upward_rounded;
    }
  }

  Color get color {
    switch (this) {
      case TransactionType.income:
        return AppColors.income;
      case TransactionType.expense:
        return AppColors.expense;
    }
  }
}
