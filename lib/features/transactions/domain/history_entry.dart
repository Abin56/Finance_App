import 'package:flutter/material.dart';

/// Which History filter chip a [HistoryEntry] belongs to. Distinct from any
/// single feature's own status/category enum — this is purely "what kind of
/// money-movement is this row" for the unified History list.
enum HistoryCategory {
  transaction,
  splitExpense,
  loan,
  bill,
  emi,
  moneyReceived,
  statementGenerated,
  statementPaid,
}

extension HistoryCategoryX on HistoryCategory {
  String get label {
    switch (this) {
      case HistoryCategory.transaction:
        return 'Transactions';
      case HistoryCategory.splitExpense:
        return 'Shared expenses';
      case HistoryCategory.loan:
        return 'Loans';
      case HistoryCategory.bill:
        return 'Bills';
      case HistoryCategory.emi:
        return 'EMI';
      case HistoryCategory.moneyReceived:
        return 'Money received';
      case HistoryCategory.statementGenerated:
        return 'Statement generated';
      case HistoryCategory.statementPaid:
        return 'Statement paid';
    }
  }
}

/// A split expense's aggregate standing across every participant's tracking
/// installment — distinct from [InstallmentStatus] (which is per-participant)
/// since the History tile represents the whole expense as one row. Mirrors
/// the Pending/Partial/Completed language `SplitExpenseStatusFilter` already
/// uses on the Person page, so the two screens read consistently.
///
/// [overdue] takes priority over [partial]/[pending] whenever any unpaid
/// installment's own `Installment.status` is overdue — see
/// `HistoryBuilder.splitExpenseDetailFor`, the one place this is computed.
enum SplitExpenseHistoryStatus { pending, partial, overdue, completed }

extension SplitExpenseHistoryStatusX on SplitExpenseHistoryStatus {
  String get label {
    switch (this) {
      case SplitExpenseHistoryStatus.pending:
        return 'Still to Pay';
      case SplitExpenseHistoryStatus.partial:
        return 'Partly Paid';
      case SplitExpenseHistoryStatus.overdue:
        return 'Overdue';
      case SplitExpenseHistoryStatus.completed:
        return 'Paid';
    }
  }
}

/// Extra detail only a [HistoryCategory.splitExpense] entry carries — how
/// many people are splitting it, how much is still owed back to the user,
/// and the expense's aggregate settlement status.
class SplitExpenseHistoryDetail {
  const SplitExpenseHistoryDetail({
    required this.participantCount,
    required this.amountToCollect,
    required this.status,
    required this.myShare,
    required this.collected,
  });

  final int participantCount;

  /// Still owed back by other participants — "Need To Collect"/"Pending".
  final double amountToCollect;
  final SplitExpenseHistoryStatus status;

  /// The payer's own share of this expense — see `Expense.myShare`.
  final double myShare;

  /// Sum already paid back by other participants.
  final double collected;
}

/// One line in the unified History feed — built by [HistoryBuilder] from
/// every feature that moves money (plain transactions, split expenses,
/// loan/bill/EMI payments, and money-received receipts), so the History
/// screen has one place to filter/search/sort across all of them without
/// duplicating any feature's own business logic. Presentation-layer view
/// model only: never persisted, and [id] doesn't necessarily address a
/// single Firestore document (a loan/bill/EMI entry synthesizes its own).
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.isCredit,
    required this.category,
    required this.icon,
    this.routePath,
    this.splitExpenseDetail,
  });

  final String id;
  final DateTime date;
  final String title;
  final String subtitle;

  /// Always positive — direction comes from [isCredit].
  final double amount;

  /// Whether this entry added money (income, money received, a settled
  /// split-expense collection) or removed/committed it (expense, a loan/
  /// bill/EMI payment, a split expense you fronted).
  final bool isCredit;

  final HistoryCategory category;
  final IconData icon;

  /// Where tapping this entry navigates, if anywhere.
  final String? routePath;

  /// Only populated when [category] is [HistoryCategory.splitExpense].
  final SplitExpenseHistoryDetail? splitExpenseDetail;
}
