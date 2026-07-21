import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Which real-world kind of money movement a history row represents — the
/// single classification every history-style list in the app (Main
/// History, Person Statement, Loan/EMI/Bill/Credit Card timelines, Search)
/// renders via [TransactionKindBadge], instead of each screen inventing its
/// own label/icon/color for the same underlying concept.
///
/// Never derived by matching a category name or free-text title — every
/// classifier that produces a [TransactionKind] (see
/// `HistoryBuilder`/`PersonTimelineBuilder`, this file's own callers) reads
/// an actual domain relationship (which repository/entity produced this
/// row), exactly the same posture `PaymentUrgencyX.from*` already takes for
/// payment status. Those classifiers live alongside the domain types they
/// read (not here) so this file stays a dependency-free leaf every feature
/// can import without a cycle. Adding a new money-moving feature (e.g.
/// Investments) means adding one value here plus one classifier line at its
/// call site — no UI changes ripple out, since every tile only ever renders
/// whatever [TransactionKind] it's given.
enum TransactionKind {
  myExpense,
  myIncome,
  transfer,
  splitExpense,
  people,
  bill,
  creditCard,
  loan,
  emi,
  savings,
  investment,
  adjustment,
  system,
}

extension TransactionKindX on TransactionKind {
  String get label {
    switch (this) {
      case TransactionKind.myExpense:
        return 'My Expense';
      case TransactionKind.myIncome:
        return 'Income';
      case TransactionKind.transfer:
        return 'Transfer';
      case TransactionKind.splitExpense:
        return 'Split Expense';
      case TransactionKind.people:
        return 'People';
      case TransactionKind.bill:
        return 'Bill';
      case TransactionKind.creditCard:
        return 'Credit Card';
      case TransactionKind.loan:
        return 'Loan';
      case TransactionKind.emi:
        return 'EMI';
      case TransactionKind.savings:
        return 'Savings';
      case TransactionKind.investment:
        return 'Investment';
      case TransactionKind.adjustment:
        return 'Adjustment';
      case TransactionKind.system:
        return 'System';
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionKind.myExpense:
        return Icons.arrow_upward_rounded;
      case TransactionKind.myIncome:
        return Icons.arrow_downward_rounded;
      case TransactionKind.transfer:
        return Icons.swap_horiz_rounded;
      case TransactionKind.splitExpense:
        return Icons.call_split_rounded;
      case TransactionKind.people:
        return Icons.people_alt_outlined;
      case TransactionKind.bill:
        return Icons.receipt_long_outlined;
      case TransactionKind.creditCard:
        return Icons.credit_card_rounded;
      case TransactionKind.loan:
        return Icons.handshake_outlined;
      case TransactionKind.emi:
        return Icons.account_balance_wallet_outlined;
      case TransactionKind.savings:
        return Icons.savings_outlined;
      case TransactionKind.investment:
        return Icons.trending_up_rounded;
      case TransactionKind.adjustment:
        return Icons.tune_rounded;
      case TransactionKind.system:
        return Icons.settings_outlined;
    }
  }

  Color get color {
    switch (this) {
      case TransactionKind.myExpense:
        return AppColors.expense;
      case TransactionKind.myIncome:
        return AppColors.income;
      case TransactionKind.transfer:
        return AppColors.info;
      case TransactionKind.splitExpense:
        return AppColors.primary;
      case TransactionKind.people:
        return AppColors.secondary;
      case TransactionKind.bill:
        return AppColors.warning;
      case TransactionKind.creditCard:
        return const Color(0xFF8E6CEF);
      case TransactionKind.loan:
        return const Color(0xFFE85D9A);
      case TransactionKind.emi:
        return const Color(0xFF40C4FF);
      case TransactionKind.savings:
        return AppColors.savings;
      case TransactionKind.investment:
        return AppColors.success;
      case TransactionKind.adjustment:
        return AppColors.pending;
      case TransactionKind.system:
        return Colors.grey;
    }
  }

  /// Lower sorts first — used to break ties when a list wants a stable,
  /// meaningful ordering by kind (most "mine" first, most peripheral last)
  /// rather than alphabetical or declaration order.
  int get priority {
    switch (this) {
      case TransactionKind.myExpense:
        return 0;
      case TransactionKind.myIncome:
        return 1;
      case TransactionKind.transfer:
        return 2;
      case TransactionKind.splitExpense:
        return 3;
      case TransactionKind.people:
        return 4;
      case TransactionKind.bill:
        return 5;
      case TransactionKind.creditCard:
        return 6;
      case TransactionKind.loan:
        return 7;
      case TransactionKind.emi:
        return 8;
      case TransactionKind.savings:
        return 9;
      case TransactionKind.investment:
        return 10;
      case TransactionKind.adjustment:
        return 11;
      case TransactionKind.system:
        return 12;
    }
  }

  /// Stable identifier for analytics events — deliberately independent of
  /// [label] (which can change for display/copy reasons without breaking
  /// analytics dashboards keyed off this string).
  String get analyticsKey => name;
}
