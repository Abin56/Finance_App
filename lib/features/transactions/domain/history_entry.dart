import 'package:flutter/material.dart';

import '../../../shared/domain/transaction_kind.dart';

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

/// One participant's name and share, for the "You ₹400 · John ₹600" style
/// breakdown on a [HistoryCategory.splitExpense] tile — a display-only
/// projection of `ExpenseParticipant`, decoupled from the expense domain
/// layer the same way the rest of [HistoryEntry] is.
class SplitShare {
  const SplitShare({required this.name, required this.share, required this.isMe});

  final String name;
  final double share;
  final bool isMe;
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
    required this.shares,
  });

  final int participantCount;

  /// Still owed back by other participants — "Need To Collect"/"Pending".
  final double amountToCollect;
  final SplitExpenseHistoryStatus status;

  /// The payer's own share of this expense — see `Expense.myShare`.
  final double myShare;

  /// Sum already paid back by other participants.
  final double collected;

  /// Every participant's name/share, "Me" first — the full breakdown behind
  /// [myShare]/[amountToCollect]'s totals, for the per-person chip.
  final List<SplitShare> shares;
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
    required this.kind,
    this.routePath,
    this.splitExpenseDetail,
    this.excludeFromCalculations = false,
    this.accountingMonth,
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

  /// Which real-world kind of money movement this row represents — see
  /// `TransactionKind`'s doc comment. Computed once in `HistoryBuilder`
  /// (where the source `Transaction`/`Expense`/etc. is available) rather
  /// than re-derived from [category] alone, since [category] can't tell a
  /// transfer leg apart from a plain expense/income the way the source
  /// `Transaction.isTransfer` field can.
  final TransactionKind kind;

  /// Where tapping this entry navigates, if anywhere.
  final String? routePath;

  /// Only populated when [category] is [HistoryCategory.splitExpense].
  final SplitExpenseHistoryDetail? splitExpenseDetail;

  /// Only ever true/set for an entry built from a plain [Transaction] (see
  /// `HistoryBuilder._fromTransaction`) — every other source (loan/bill/EMI/
  /// statement) has no such flag, so these default false/null for them.
  final bool excludeFromCalculations;
  final DateTime? accountingMonth;
}
