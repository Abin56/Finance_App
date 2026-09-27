/// One Person's financial position — the single People rule shared with the
/// web app (`lib/engines/person-position.ts`), held to identical answers by
/// `test/cross_platform_fixtures/person_position_fixture.json`. Pure.
///
/// Canonical sources:
///  - Direct obligations (split expenses, settlements, manual entries, "someone
///    paid my EMI" attributions) → the Person ledger (`Person.currentBalance`).
///  - Loan obligations → the Loan: outstanding principal (never future
///    interest — the same figure Net Worth uses), attributed to the Loan's
///    counterparty `personId`. `payerPersonId` is not a counterparty.
///
/// Legacy de-duplication: the old web Loan form also posted Loan-generated
/// ledger entries stamped `transactionRef = loan.id`. They are recognised ONLY
/// by that persisted link (never amount/date/text) and taken back out of the
/// direct balance, so the Loan counts once.
///
/// Trashed Loans are excluded, closed Loans included — exactly as the Loan
/// balance sheet.
library;

class PositionLoan {
  const PositionLoan({
    required this.id,
    required this.personId,
    required this.isGiven,
    required this.outstandingPrincipal,
    required this.isDeleted,
  });

  final String id;
  final String? personId;

  /// True for money I lent ([LoanDirection.given]).
  final bool isGiven;
  final double outstandingPrincipal;
  final bool isDeleted;
}

class PositionLedgerEntry {
  const PositionLedgerEntry({
    required this.transactionRef,
    required this.signedAmount,
    required this.isDeleted,
  });

  final String? transactionRef;

  /// Positive = they owe me more.
  final double signedAmount;
  final bool isDeleted;
}

class PersonPosition {
  const PersonPosition({
    required this.directBalance,
    required this.loanReceivable,
    required this.loanPayable,
    required this.legacyLoanLedger,
    required this.net,
  });

  static const zero = PersonPosition(
    directBalance: 0,
    loanReceivable: 0,
    loanPayable: 0,
    legacyLoanLedger: 0,
    net: 0,
  );

  /// Direct Person ledger balance with legacy Loan-generated entries taken out
  /// — the part Settle Up settles.
  final double directBalance;
  final double loanReceivable;
  final double loanPayable;

  /// Signed sum of this person's active legacy Loan-generated ledger entries.
  final double legacyLoanLedger;

  /// direct + receivable − payable. Positive: they owe me.
  final double net;

  double get owesMe => net > 0 ? net : 0;
  double get iOwe => net < 0 ? -net : 0;
}

double _round2(double v) => (v * 100).round() / 100;

/// True for a ledger entry the old web Loan form generated for one of
/// [loanIds].
bool isLegacyLoanLedgerEntry(String? transactionRef, Set<String> loanIds) =>
    transactionRef != null && loanIds.contains(transactionRef);

/// [loanIds] is every known Loan id (active AND trashed).
PersonPosition personPosition({
  required String personId,
  required double currentBalance,
  required Iterable<PositionLoan> loans,
  required Iterable<PositionLedgerEntry> ledgerEntries,
  required Set<String> loanIds,
}) {
  final legacy = ledgerEntries
      .where(
        (e) =>
            !e.isDeleted && isLegacyLoanLedgerEntry(e.transactionRef, loanIds),
      )
      .fold<double>(0, (total, e) => total + e.signedAmount);
  var receivable = 0.0;
  var payable = 0.0;
  for (final loan in loans) {
    if (loan.personId != personId || loan.isDeleted) continue;
    if (loan.isGiven) {
      receivable += loan.outstandingPrincipal;
    } else {
      payable += loan.outstandingPrincipal;
    }
  }
  final direct = _round2(currentBalance - legacy);
  return PersonPosition(
    directBalance: direct,
    loanReceivable: _round2(receivable),
    loanPayable: _round2(payable),
    legacyLoanLedger: _round2(legacy),
    net: _round2(direct + receivable - payable),
  );
}

/// People-list totals over every person's position.
({
  double totalOwedToMe,
  int owedByCount,
  double totalIOwe,
  int owingCount,
  double net,
})
peopleTotals(Iterable<PersonPosition> positions) {
  final owed = _round2(positions.fold(0.0, (t, p) => t + p.owesMe));
  final owe = _round2(positions.fold(0.0, (t, p) => t + p.iOwe));
  return (
    totalOwedToMe: owed,
    owedByCount: positions.where((p) => p.owesMe > 0).length,
    totalIOwe: owe,
    owingCount: positions.where((p) => p.iOwe > 0).length,
    net: _round2(owed - owe),
  );
}
