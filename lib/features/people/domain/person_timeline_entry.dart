import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Which money-interaction area a [PersonTimelineEntry] belongs to, for the
/// pending breakdown and filter chips. Bills/EMI have no [Person] linkage
/// anywhere in this codebase (no `personId` field on either), so they have
/// no category here — [lending] (via `Loan`), [assignedExpense]/
/// [splitExpense] (via `Expense`/`ExpenseParticipant`), [other] (plain
/// ledger movements/adjustments), and [reference] (a plain `Transaction`
/// with `linkedPersonId` set but no owed toggle — no `Expense`/`LedgerEntry`
/// backs it at all, see `PersonTimelineBuilder`'s `referencedTransactions`
/// input) all exist.
enum PersonTimelineCategory { lending, assignedExpense, splitExpense, other, reference }

extension PersonTimelineCategoryX on PersonTimelineCategory {
  String get label {
    switch (this) {
      case PersonTimelineCategory.lending:
        return 'Lending';
      case PersonTimelineCategory.assignedExpense:
        return 'Expenses this person will pay';
      case PersonTimelineCategory.splitExpense:
        return 'Shared expenses';
      case PersonTimelineCategory.other:
        return 'Other';
      case PersonTimelineCategory.reference:
        return 'Related transactions';
    }
  }
}

/// How one [PersonTimelineEntry] currently stands. Null on entries where
/// completion doesn't apply (e.g. a plain "money given" isn't itself
/// paid/pending — only the person's overall balance is).
enum PersonTimelineStatus { completed, pending, partial, overdue }

extension PersonTimelineStatusX on PersonTimelineStatus {
  String get label {
    switch (this) {
      case PersonTimelineStatus.completed:
        return 'Fully Paid';
      case PersonTimelineStatus.pending:
        return 'Payment Pending';
      case PersonTimelineStatus.partial:
        return 'Partially Paid';
      case PersonTimelineStatus.overdue:
        return 'Overdue';
    }
  }

  Color get color {
    switch (this) {
      case PersonTimelineStatus.completed:
        return AppColors.success;
      case PersonTimelineStatus.pending:
        return AppColors.pending;
      case PersonTimelineStatus.partial:
        return AppColors.warning;
      case PersonTimelineStatus.overdue:
        return AppColors.error;
    }
  }
}

/// One line in a person's unified financial timeline — built by
/// [PersonTimelineBuilder] from that person's [LedgerEntry]s and [Loan]s
/// (plus the loans' installment payments). This is a presentation-layer
/// view model only: it is never persisted, and carries no id back to a
/// single source document (loan-derived entries synthesize their own ids).
class PersonTimelineEntry {
  const PersonTimelineEntry({
    required this.id,
    required this.date,
    required this.icon,
    required this.title,
    required this.signedAmount,
    required this.category,
    required this.isDeleted,
    required this.color,
    this.status,
    this.note = '',
  });

  final String id;
  final DateTime date;
  final IconData icon;
  final String title;

  /// Same sign convention as [LedgerEntry.signedAmount]: positive moves the
  /// person's pending amount toward "they owe you more".
  final double signedAmount;
  final PersonTimelineCategory category;

  /// User-friendly color for this entry's amount/icon — red only for an open
  /// ask ("they need to pay me" / money lent, not yet paid back), green for
  /// every entry where money has actually changed hands. Independent of
  /// [signedAmount]'s sign, which reflects balance direction, not "is this
  /// good news" (see [LedgerEntryType.color]).
  final Color color;
  final PersonTimelineStatus? status;
  final String note;

  /// Soft-deleted entries (from either source) are excluded from totals and
  /// the default timeline view, mirroring how [LedgerRepository.watchAll]
  /// already excludes soft-deleted [LedgerEntry]s — carried through here so
  /// a caller building the trash view can still request them.
  final bool isDeleted;

  /// Money that closed out an existing debt — a repayment, a received-back,
  /// or a loan installment payment — as opposed to money that created or
  /// grew one (lending, split/assigned expenses, adjustments). Drives the
  /// person statement's Transactions/Settlements split.
  static const _settlementTitles = {'Mark as Paid', 'Received Payment', 'Loan payment received'};

  bool get isSettlement => _settlementTitles.contains(title);
}
