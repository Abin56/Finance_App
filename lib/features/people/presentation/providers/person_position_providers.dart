import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../lending/domain/loan.dart';
import '../../../lending/domain/loan_direction.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../domain/ledger_entry.dart';
import '../../domain/person_position.dart';
import 'people_providers.dart';

/// Every known Loan id — active and trashed — so a legacy Loan-generated
/// ledger entry of a trashed Loan is still recognised (see [personPosition]).
final allLoanIdsProvider = Provider<Set<String>>((ref) {
  final active = ref.watch(loansStreamProvider).value ?? const <Loan>[];
  final trashed = ref.watch(loansTrashStreamProvider).value ?? const <Loan>[];
  return {for (final l in active) l.id, for (final l in trashed) l.id};
});

/// Live position for one person: direct ledger balance + the Loans they are
/// the counterparty on (outstanding principal from
/// [loanFinancialSummaryProvider], the figure Net Worth uses), with legacy
/// Loan-generated ledger entries de-duplicated. Updates on any Loan payment,
/// prepayment, Borrow/Lend More or reversal — no Person write involved.
/// Mirrors the web app's `usePersonPositions`.
final personPositionProvider = Provider.family<PersonPosition, String>((
  ref,
  personId,
) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  final person = people.where((p) => p.id == personId).firstOrNull;
  if (person == null) return PersonPosition.zero;
  final myLoans = [
    ...(ref.watch(loansStreamProvider).value ?? const <Loan>[]),
    ...(ref.watch(loansTrashStreamProvider).value ?? const <Loan>[]),
  ].where((l) => l.personId == personId).toList();
  // Only people with a Loan can have Loan-generated ledger entries, so
  // everyone else needs no ledger read at all.
  final entries = myLoans.isEmpty
      ? const []
      : ref.watch(ledgerStreamProvider(personId)).value ?? const [];
  return personPosition(
    personId: personId,
    currentBalance: person.currentBalance,
    loanIds: myLoans.isEmpty ? const {} : ref.watch(allLoanIdsProvider),
    loans: [
      for (final loan in myLoans)
        PositionLoan(
          id: loan.id,
          personId: loan.personId,
          isGiven: loan.direction == LoanDirection.given,
          outstandingPrincipal: loan.isDeleted
              ? 0
              : ref
                    .watch(loanFinancialSummaryProvider(loan))
                    .principalRemaining,
          isDeleted: loan.isDeleted,
        ),
    ],
    ledgerEntries: [
      for (final e in entries)
        PositionLedgerEntry(
          transactionRef: e.transactionRef,
          signedAmount: e.signedAmount,
          isDeleted: e.isDeleted,
        ),
    ],
  );
});

/// Net position per person id, for every live person.
final personNetBalancesProvider = Provider<Map<String, double>>((ref) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  return {
    for (final p in people) p.id: ref.watch(personPositionProvider(p.id)).net,
  };
});

/// A person's active ledger entries WITHOUT legacy Loan-generated ones (the
/// old web Loan form's `transactionRef = loan.id` entries). The statement
/// timeline shows each Loan's own events instead, so this is what keeps a
/// Loan event from appearing twice. Mirrors the web People activity filter.
final directLedgerEntriesProvider = Provider.autoDispose
    .family<List<LedgerEntry>, String>((ref, personId) {
      final entries =
          ref.watch(ledgerStreamProvider(personId)).value ?? const [];
      final loanIds = ref.watch(allLoanIdsProvider);
      return entries
          .where((e) => !isLegacyLoanLedgerEntry(e.transactionRef, loanIds))
          .toList();
    });
