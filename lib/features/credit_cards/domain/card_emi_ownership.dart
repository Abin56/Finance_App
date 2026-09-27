import '../../lending/domain/loan.dart';
import '../../lending/domain/loan_direction.dart';
import '../../transactions/domain/transaction.dart';

/// Who owns a card-linked EMI's exposure — the ONE rule Credit Card
/// available credit / utilization / exposure, Reports and Net Worth all apply.
/// Mirrors Web's `emiPurchaseRepresentedOnCard`
/// (`lib/engines/credit-utilization.ts`) exactly.
///
/// The card's liability is the sum of the card account's active, calculable,
/// non-transfer Transactions (live statement totals + the current cycle). So
/// the EMI's linked purchase ([purchase], looked up by the EMI's
/// `purchaseTransactionId` among ACTIVE transactions — a deleted/reversed one
/// is simply absent) is "represented" exactly when it would be inside that
/// sum:
///  - Case A — represented: the purchase already carries the exposure; the
///    EMI must not lock its principal again.
///  - Case B — no link (legacy default / issuer-converted, never recorded):
///    the EMI's remaining principal is the exposure, counted once.
///  - Case C — linked but deleted, excluded from calculations, a transfer
///    leg, or on a different account: NOT represented in this card's
///    liability any more, so the EMI owns the exposure like Case B.
/// Never matched by amount/date.
bool emiPurchaseRepresentedOnCard({
  required String? purchaseTransactionId,
  required Transaction? purchase,
  required String cardAccountId,
}) {
  if (purchaseTransactionId == null || purchase == null) return false;
  return purchase.id == purchaseTransactionId &&
      !purchase.isDeleted &&
      !purchase.excludeFromCalculations &&
      !purchase.isTransfer &&
      purchase.accountId == cardAccountId;
}

/// The Credit Card that owns a [Loan]'s liability, or `null`. A borrowed Loan
/// financed on a card (the unified wizard's `fundingSource: creditCard` +
/// `linkedCreditCardId`, e.g. a ₹40,000 installment purchase) is the same
/// obligation as a card-linked EMI: the card owns the exposure, so the Loan
/// locks/restores that card's available credit like an EMI and is never
/// counted again as a Loan liability (docs/loans-installments-unification-audit.md
/// §6.5 on Web). Same rule as the unified adapter's `cardOwnedLiability`.
/// Mirrors Web's `cardFundedLoanCardId` (`lib/engines/credit-utilization.ts`).
String? cardFundedLoanCardId(Loan loan) =>
    loan.direction == LoanDirection.taken &&
        loan.fundingSource == LoanFundingSource.creditCard &&
        loan.linkedCreditCardId != null
    ? loan.linkedCreditCardId
    : null;
