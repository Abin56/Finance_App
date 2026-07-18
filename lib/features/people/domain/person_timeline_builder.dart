import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../core/payment_schedule/domain/installment_status.dart';
import '../../lending/domain/loan.dart';
import '../../lending/domain/loan_status.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_type.dart';
import 'ledger_entry.dart';
import 'ledger_entry_type.dart';
import 'person_timeline_entry.dart';

/// Everything a [Loan] contributes to its person's timeline: the loan
/// itself, its current installments (for status), and every payment
/// recorded against those installments — supplied by the caller (the
/// provider layer), since fetching them is I/O this pure builder must not do.
class LoanTimelineData {
  const LoanTimelineData({
    required this.loan,
    required this.installments,
    required this.payments,
  });

  final Loan loan;
  final List<Installment> installments;
  final List<InstallmentPayment> payments;
}

/// Folds a person's [LedgerEntry]s and [LoanTimelineData] into one
/// chronological [PersonTimelineEntry] list with running pending amounts —
/// the single place this merge happens, so the statement screen and the
/// share/export text can never disagree about ordering or balance.
abstract class PersonTimelineBuilder {
  PersonTimelineBuilder._();

  static const _splitSettlementPrefix = 'Split settlement:';
  static const _splitGivenPrefix = 'Split:';

  /// Builds the full timeline, oldest first, excluding soft-deleted source
  /// records by default (pass [includeDeleted] to build a trash view).
  ///
  /// [participantCountByTransactionRef] disambiguates a ledger entry
  /// created for "assign expense to person" (one participant) from one
  /// created for a genuine split (multiple participants) — both post the
  /// same "Split:"/"Split settlement:" note prefix (see
  /// `ExpenseRepository.assignToPerson`, the degenerate one-participant
  /// case of `createExpense`), so the participant count is the only signal
  /// that tells them apart. Keyed by `LedgerEntry.transactionRef`, supplied
  /// by the caller from the already-loaded `Expense` stream. An entry whose
  /// `transactionRef` isn't in the map (e.g. a non-split ledger entry) falls
  /// back to [PersonTimelineCategory.lending].
  ///
  /// [installmentStatusByTransactionRef] supplies each split/assigned
  /// expense's *own* participant installment status (not the whole
  /// schedule's), so a "Split: Dinner" entry can show live Pending/Partial/
  /// Completed the same way a loan entry does — a "Split settlement: ..."
  /// entry (money already collected) always reads Completed regardless,
  /// since it's a historical record of a specific past payment.
  /// [referencedTransactions] are plain `Transaction`s linked to this person
  /// (`Transaction.linkedPersonId`) with no owed toggle and therefore no
  /// backing `Expense`/`LedgerEntry` at all — the caller is responsible for
  /// excluding any transaction that *does* have an `Expense` (an owed one
  /// already surfaces via its `gave` ledger entry above, and must not be
  /// double-counted here). Each becomes a zero-amount, no-status
  /// [PersonTimelineCategory.reference] entry — nothing to settle, just a
  /// "this happened, involving them" marker.
  static List<PersonTimelineEntry> build({
    required List<LedgerEntry> ledgerEntries,
    required List<LoanTimelineData> loans,
    List<Transaction> referencedTransactions = const [],
    Map<String, int> participantCountByTransactionRef = const {},
    Map<String, InstallmentStatus> installmentStatusByTransactionRef = const {},
    bool includeDeleted = false,
  }) {
    final entries = <PersonTimelineEntry>[
      for (final entry in ledgerEntries)
        if (includeDeleted || !entry.isDeleted)
          _fromLedgerEntry(entry, participantCountByTransactionRef, installmentStatusByTransactionRef),
      for (final loanData in loans) ..._fromLoan(loanData, includeDeleted: includeDeleted),
      for (final transaction in referencedTransactions)
        if (includeDeleted || !transaction.isDeleted) _fromReferencedTransaction(transaction),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  static PersonTimelineEntry _fromReferencedTransaction(Transaction transaction) {
    return PersonTimelineEntry(
      id: transaction.id,
      date: transaction.dateTime,
      icon: transaction.type.icon,
      title: transaction.description.isNotEmpty ? transaction.description : transaction.type.label,
      signedAmount: 0,
      category: PersonTimelineCategory.reference,
      isDeleted: transaction.isDeleted,
      color: AppColors.pending,
      note: transaction.description,
    );
  }

  /// Annotates a (already chronologically sorted, oldest-first) timeline
  /// with the running pending amount after each entry, starting from
  /// [openingBalance] — the same fold every caller (screen, share export)
  /// needs, kept in one place.
  static Map<String, double> runningBalances({
    required double openingBalance,
    required List<PersonTimelineEntry> entriesOldestFirst,
  }) {
    var runningBalance = openingBalance;
    final balanceAfterById = <String, double>{};
    for (final entry in entriesOldestFirst) {
      runningBalance += entry.signedAmount;
      balanceAfterById[entry.id] = runningBalance;
    }
    return balanceAfterById;
  }

  static PersonTimelineEntry _fromLedgerEntry(
    LedgerEntry entry,
    Map<String, int> participantCountByTransactionRef,
    Map<String, InstallmentStatus> installmentStatusByTransactionRef,
  ) {
    final category = _categoryForLedgerEntry(entry, participantCountByTransactionRef);
    return PersonTimelineEntry(
      id: entry.id,
      date: entry.date,
      icon: entry.type.icon,
      title: entry.type.label,
      signedAmount: entry.signedAmount,
      category: category,
      status: _statusForLedgerEntry(entry, category, installmentStatusByTransactionRef),
      note: entry.note,
      isDeleted: entry.isDeleted,
      color: entry.type.color,
    );
  }

  /// Only a "gave" entry (the original split/assignment) tracks a live
  /// pending status — a "receivedBack" entry (a settlement) is itself
  /// already-collected money and always reads Completed.
  static PersonTimelineStatus? _statusForLedgerEntry(
    LedgerEntry entry,
    PersonTimelineCategory category,
    Map<String, InstallmentStatus> installmentStatusByTransactionRef,
  ) {
    if (category != PersonTimelineCategory.splitExpense && category != PersonTimelineCategory.assignedExpense) {
      return null;
    }
    if (entry.type == LedgerEntryType.receivedBack) return PersonTimelineStatus.completed;

    final installmentStatus = installmentStatusByTransactionRef[entry.transactionRef];
    if (installmentStatus == null) return null;
    switch (installmentStatus) {
      case InstallmentStatus.paid:
        return PersonTimelineStatus.completed;
      case InstallmentStatus.partiallyPaid:
        return PersonTimelineStatus.partial;
      case InstallmentStatus.overdue:
        return PersonTimelineStatus.overdue;
      case InstallmentStatus.skipped:
      case InstallmentStatus.upcoming:
        return PersonTimelineStatus.pending;
    }
  }

  static PersonTimelineCategory _categoryForLedgerEntry(
    LedgerEntry entry,
    Map<String, int> participantCountByTransactionRef,
  ) {
    if (entry.type == LedgerEntryType.adjustment) return PersonTimelineCategory.other;
    final isExpenseLinked =
        entry.note.startsWith(_splitSettlementPrefix) || entry.note.startsWith(_splitGivenPrefix);
    if (!isExpenseLinked) return PersonTimelineCategory.lending;

    final participantCount = participantCountByTransactionRef[entry.transactionRef];
    return participantCount == 1 ? PersonTimelineCategory.assignedExpense : PersonTimelineCategory.splitExpense;
  }

  static List<PersonTimelineEntry> _fromLoan(LoanTimelineData data, {required bool includeDeleted}) {
    final loan = data.loan;
    if (!includeDeleted && loan.isDeleted) return const [];

    final loanStatus = loan.statusGiven(data.installments);
    final entries = <PersonTimelineEntry>[
      PersonTimelineEntry(
        id: 'loan-${loan.id}',
        date: loan.loanDate,
        icon: Icons.call_made_rounded,
        title: 'Money lent',
        signedAmount: loan.loanAmount,
        category: PersonTimelineCategory.lending,
        status: _statusForLoan(loanStatus),
        note: loan.name ?? loan.notes,
        isDeleted: loan.isDeleted,
        color: AppColors.debit,
      ),
    ];

    for (final payment in data.payments) {
      if (!includeDeleted && payment.isDeleted) continue;
      entries.add(
        PersonTimelineEntry(
          id: 'loan-payment-${payment.id}',
          date: payment.date,
          icon: Icons.undo_rounded,
          title: 'Loan payment received',
          signedAmount: -payment.amount,
          category: PersonTimelineCategory.lending,
          status: PersonTimelineStatus.completed,
          note: payment.note,
          isDeleted: payment.isDeleted,
          color: AppColors.credit,
        ),
      );
    }

    return entries;
  }

  static PersonTimelineStatus _statusForLoan(LoanStatus status) {
    switch (status) {
      case LoanStatus.active:
        return PersonTimelineStatus.pending;
      case LoanStatus.closed:
        return PersonTimelineStatus.completed;
      case LoanStatus.overdue:
        return PersonTimelineStatus.overdue;
    }
  }
}
