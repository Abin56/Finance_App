import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/domain/card_emi_ownership.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../domain/loan_balance_sheet.dart';
import '../../domain/loan_principal.dart';
import 'loan_providers.dart';

/// Live [LoanBalanceSheet] over every non-deleted Loan and EMI (closed ones
/// included — same as Web's `useLoanBalanceSheet`). Streams are read with
/// `asData` so a failing Loan/EMI/Card stream degrades to "no loans" instead of
/// crashing every Net Worth consumer (the error still surfaces on its own screen).
final loanBalanceSheetProvider = Provider<LoanBalanceSheet>((ref) {
  final loans = ref.watch(loansStreamProvider).asData?.value ?? const [];
  final emis = ref.watch(emisStreamProvider).asData?.value ?? const [];
  final trackedCards =
      ref.watch(creditCardsStreamProvider).asData?.value ?? const [];
  final trackedCardIds = {for (final c in trackedCards) c.id};
  return LoanBalanceSheet.from(
    // Card-owned EMI exposure that no represented purchase carries (Case B/C)
    // — the same figure the card's available credit uses.
    cardLockedEmiPrincipal: trackedCards.fold(
      0.0,
      (sum, c) => sum + ref.watch(lockedEmiPrincipalForCardProvider(c.id)),
    ),
    loans: [
      for (final loan in loans)
        LoanPrincipalPosition(
          direction: loan.direction,
          // Already net of extra principal — see `loanFinancialSummaryProvider`.
          outstandingPrincipal: ref
              .watch(loanFinancialSummaryProvider(loan))
              .principalRemaining,
          // A Loan financed on a tracked card is that card's liability (its
          // lock, or the represented purchase) — counting it as borrowed too
          // subtracted the same money twice from Net Worth.
          ownedByTrackedCard: trackedCardIds.contains(
            cardFundedLoanCardId(loan),
          ),
        ),
    ],
    emis: [
      for (final emi in emis)
        EmiPrincipalPosition(
          outstandingPrincipal: outstandingPrincipalAfterPrepayments(
            loanAmount: emi.principalAmount,
            installments:
                ref
                    .watch(installmentsStreamProvider(emi.scheduleId))
                    .asData
                    ?.value ??
                const [],
            principalPrepaid: 0,
          ),
          ownedByTrackedCard:
              emi.linkedCreditCardId != null &&
              trackedCardIds.contains(emi.linkedCreditCardId),
        ),
    ],
  );
});

/// Net Worth including loan principal (Decision 6) — see [netWorthWithLoans].
/// [netWorthProvider] stays the plain account-balance sum ("Total balance").
final netWorthWithLoansProvider = Provider<double>((ref) {
  return netWorthWithLoans(
    ref.watch(netWorthProvider),
    ref.watch(loanBalanceSheetProvider),
  );
});
