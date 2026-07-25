import '../../../../core/pdf/widgets/pdf_status_pill.dart';
import '../../domain/person.dart';
import '../../domain/person_timeline_builder.dart';
import '../../domain/person_timeline_entry.dart';
import '../providers/person_expense_stats_provider.dart';

/// A plain-Dart, PDF-facing snapshot of a person's statement — the seam
/// between the app's Flutter/Riverpod-flavored domain models
/// ([Person], [PersonTimelineEntry], [PersonExpenseStats]) and the `pdf`
/// package's widgets, which know nothing about [Color]/[IconData]/
/// [BuildContext]. Built once via [StatementPdfModel.build], then consumed
/// by every PDF widget without touching the source models again.
class StatementPdfModel {
  const StatementPdfModel({
    required this.personName,
    required this.personPhone,
    required this.personEmail,
    required this.personNotesText,
    required this.personSince,
    required this.generatedAt,
    required this.filterDescription,
    required this.openingBalance,
    required this.currentBalance,
    required this.isCreditor,
    required this.isDebtor,
    required this.totalGiven,
    required this.totalReceived,
    required this.totalSettled,
    required this.youLent,
    required this.youBorrowed,
    required this.expenseStatsTotalSpent,
    required this.expenseStatsTotalSettled,
    required this.expenseStatsPending,
    required this.rows,
  });

  final String personName;
  final String? personPhone;
  final String? personEmail;
  final String personNotesText;
  final DateTime personSince;
  final DateTime generatedAt;

  /// Human-readable summary of the active screen filter (tab + date range +
  /// search query) this statement was exported from — e.g.
  /// "History · 1 Jan – 31 Jan 2026 · "fuel"" — so a reader never mistakes a
  /// filtered export for the person's full history. Empty string means no
  /// filter was active (full history).
  final String filterDescription;

  final double openingBalance;
  final double currentBalance;
  final bool isCreditor;
  final bool isDebtor;

  final double totalGiven;
  final double totalReceived;
  final double totalSettled;
  final double youLent;
  final double youBorrowed;

  /// Scoped to split/assigned Expense participations only, mirroring
  /// [PersonExpenseStats]'s own doc comment — not plain lending. Zero when
  /// this person has no split/assigned expense participation at all.
  final double expenseStatsTotalSpent;
  final double expenseStatsTotalSettled;
  final double expenseStatsPending;

  final List<StatementPdfRow> rows;

  int get totalRowCount => rows.length;

  DateTime? get lastTransactionDate => rows.isEmpty ? null : rows.last.date;

  factory StatementPdfModel.build({
    required Person person,
    required List<PersonTimelineEntry> entriesOldestFirst,
    required PersonExpenseStats expenseStats,
    required String filterDescription,
    required double openingBalanceForRange,
  }) {
    final balanceAfterById = PersonTimelineBuilder.runningBalances(
      openingBalance: openingBalanceForRange,
      entriesOldestFirst: entriesOldestFirst,
    );

    double totalGiven = 0;
    double totalReceived = 0;
    double totalSettled = 0;
    double youLent = 0;
    double youBorrowed = 0;

    for (final entry in entriesOldestFirst) {
      if (entry.signedAmount > 0) {
        totalGiven += entry.signedAmount;
      } else if (entry.signedAmount < 0) {
        totalReceived += -entry.signedAmount;
      }
      if (entry.isSettlement) totalSettled += entry.signedAmount.abs();
      if (entry.category == PersonTimelineCategory.lending) {
        if (entry.signedAmount > 0) youLent += entry.signedAmount;
        if (entry.signedAmount < 0) youBorrowed += -entry.signedAmount;
      }
    }

    return StatementPdfModel(
      personName: person.name,
      personPhone: person.phone,
      personEmail: person.email,
      personNotesText: person.notes,
      personSince: person.createdAt,
      generatedAt: DateTime.now(),
      filterDescription: filterDescription,
      openingBalance: openingBalanceForRange,
      currentBalance: person.currentBalance,
      isCreditor: person.isCreditor,
      isDebtor: person.isDebtor,
      totalGiven: totalGiven,
      totalReceived: totalReceived,
      totalSettled: totalSettled,
      youLent: youLent,
      youBorrowed: youBorrowed,
      expenseStatsTotalSpent: expenseStats.totalSpent,
      expenseStatsTotalSettled: expenseStats.totalSettled,
      expenseStatsPending: expenseStats.pending,
      rows: [
        for (final entry in entriesOldestFirst)
          StatementPdfRow._fromEntry(entry, personName: person.name, runningBalanceAfter: balanceAfterById[entry.id]!),
      ],
    );
  }
}

/// One row of the transaction table. All display fields are pre-resolved to
/// plain strings/enums here so [TransactionTableWidget] never has to know
/// about [PersonTimelineCategory]/[PersonTimelineStatus] label logic itself.
class StatementPdfRow {
  const StatementPdfRow({
    required this.id,
    required this.date,
    required this.title,
    required this.category,
    required this.note,
    required this.displayAmount,
    required this.signedAmount,
    required this.runningBalanceAfter,
    required this.statusLabel,
    required this.statusTone,
    required this.paidBy,
  });

  final String id;
  final DateTime date;
  final String title;
  final String category;
  final String? note;
  final double displayAmount;
  final double signedAmount;
  final double runningBalanceAfter;
  final String? statusLabel;
  final PdfStatusTone? statusTone;

  /// Honestly derived from [signedAmount]'s sign — the same sign convention
  /// [LedgerEntryType]/[Person.currentBalance] already rely on, not a guess:
  /// positive means money moved toward "they owe you more" (you paid),
  /// negative means the reverse (they paid), zero (a `reference` entry that
  /// never moves the balance) has no payer to report.
  final String paidBy;

  factory StatementPdfRow._fromEntry(
    PersonTimelineEntry entry, {
    required String personName,
    required double runningBalanceAfter,
  }) {
    final String paidBy;
    if (entry.signedAmount > 0) {
      paidBy = 'You';
    } else if (entry.signedAmount < 0) {
      paidBy = personName;
    } else {
      paidBy = '—';
    }

    return StatementPdfRow(
      id: entry.id,
      date: entry.date,
      title: entry.title,
      category: entry.category.label,
      note: entry.note.isEmpty ? null : entry.note,
      displayAmount: entry.displayAmount,
      signedAmount: entry.signedAmount,
      runningBalanceAfter: runningBalanceAfter,
      statusLabel: entry.status?.label,
      statusTone: _toneForStatus(entry.status),
      paidBy: paidBy,
    );
  }

  static PdfStatusTone? _toneForStatus(PersonTimelineStatus? status) {
    switch (status) {
      case null:
        return null;
      case PersonTimelineStatus.completed:
        return PdfStatusTone.success;
      case PersonTimelineStatus.pending:
        return PdfStatusTone.neutral;
      case PersonTimelineStatus.partial:
        return PdfStatusTone.warning;
      case PersonTimelineStatus.overdue:
        return PdfStatusTone.error;
    }
  }
}
