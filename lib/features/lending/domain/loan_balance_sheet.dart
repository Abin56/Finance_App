import 'loan_direction.dart';

/// Loan / EMI principal classified by who owes whom — the one place Net Worth
/// and liabilities/receivables come from. Mirrors Web's
/// `lib/engines/loan-balance-sheet.ts` exactly.
///
/// Principal only — future unearned/unaccrued interest is never a current
/// liability or receivable (the schedule does not capitalize it):
///  - Loan, [LoanDirection.taken] (money I borrowed) → liability, UNLESS it
///    was financed on a Credit Card tracked in FlowFi ([LoanPrincipalPosition.ownedByTrackedCard]):
///    exactly like a card-linked EMI below.
///  - Loan, [LoanDirection.given] (money I lent) → receivable (asset).
///  - EMI (always money I owe) → liability, UNLESS it is linked to a Credit
///    Card tracked in FlowFi: the card owns that liability (Decision 3), so it
///    is never counted again here.
/// Closed items are still included (closing is not the same as repaying).
class LoanPrincipalPosition {
  const LoanPrincipalPosition({
    required this.direction,
    required this.outstandingPrincipal,
    this.ownedByTrackedCard = false,
  });
  final LoanDirection direction;
  final double outstandingPrincipal;

  /// True only for a borrowed Loan financed on a tracked Credit Card
  /// (`cardFundedLoanCardId`). Like a card-linked EMI, the card owns that
  /// liability, so it is reported on the card side (its locked principal, or
  /// the represented purchase) and never again as borrowed.
  final bool ownedByTrackedCard;
}

class EmiPrincipalPosition {
  const EmiPrincipalPosition({
    required this.outstandingPrincipal,
    required this.ownedByTrackedCard,
  });
  final double outstandingPrincipal;

  /// True only when `linkedCreditCardId` resolves to a tracked Credit Card.
  final bool ownedByTrackedCard;
}

class LoanBalanceSheet {
  const LoanBalanceSheet({
    required this.borrowedPrincipal,
    required this.lentPrincipal,
    required this.emiPrincipal,
    required this.cardOwnedEmiPrincipal,
    this.cardLockedEmiPrincipal = 0,
  });

  static const empty = LoanBalanceSheet(
    borrowedPrincipal: 0,
    lentPrincipal: 0,
    emiPrincipal: 0,
    cardOwnedEmiPrincipal: 0,
  );

  final double borrowedPrincipal;
  final double lentPrincipal;
  final double emiPrincipal;

  /// Card-owned EMI principal still locked against a tracked card because no
  /// represented purchase carries it (Cases B/C of `emiPurchaseRepresentedOnCard`)
  /// — the card engine's `lockedEmiPrincipal`. A real liability that sits in
  /// no account balance, so Net Worth subtracts it exactly once.
  final double cardLockedEmiPrincipal;

  /// EMI / card-funded Loan principal left out on purpose because a tracked
  /// Credit Card owns it — transparency only.
  final double cardOwnedEmiPrincipal;

  static LoanBalanceSheet from({
    required Iterable<LoanPrincipalPosition> loans,
    required Iterable<EmiPrincipalPosition> emis,
    double cardLockedEmiPrincipal = 0,
  }) {
    var borrowed = 0.0;
    var lent = 0.0;
    var cardOwned = 0.0;
    for (final loan in loans) {
      final principal = loan.outstandingPrincipal < 0
          ? 0.0
          : loan.outstandingPrincipal;
      if (loan.direction == LoanDirection.given) {
        lent += principal;
      } else if (loan.ownedByTrackedCard) {
        cardOwned += principal;
      } else {
        borrowed += principal;
      }
    }
    var emi = 0.0;
    for (final e in emis) {
      final principal = e.outstandingPrincipal < 0
          ? 0.0
          : e.outstandingPrincipal;
      if (e.ownedByTrackedCard) {
        cardOwned += principal;
      } else {
        emi += principal;
      }
    }
    return LoanBalanceSheet(
      borrowedPrincipal: borrowed,
      lentPrincipal: lent,
      emiPrincipal: emi,
      cardOwnedEmiPrincipal: cardOwned,
      cardLockedEmiPrincipal: cardLockedEmiPrincipal,
    );
  }
}

/// Net Worth (Decision 6 + card ownership): account balances (credit-card accounts included,
/// which already carry card debt) + principal owed TO me − principal I owe on
/// loans and on EMIs not owned by a tracked card − card-owned EMI principal that
/// no recorded purchase represents (Case B/C). Mirrors Web's
/// `netWorthWithLoans`.
double netWorthWithLoans(double accountBalances, LoanBalanceSheet sheet) =>
    accountBalances +
    sheet.lentPrincipal -
    sheet.borrowedPrincipal -
    sheet.emiPrincipal -
    sheet.cardLockedEmiPrincipal;
