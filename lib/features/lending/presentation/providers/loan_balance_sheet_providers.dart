import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/domain/card_emi_ownership.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/providers/person_position_providers.dart';
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

/// Account ids behind every tracked credit card — accounts that carry card
/// debt, not cash.
final _trackedCardAccountIdsProvider = Provider<Set<String>>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).asData?.value ?? const [];
  return {for (final c in cards) c.accountId};
});

/// "Total balance" — money actually held: every account EXCEPT tracked
/// credit-card accounts, whose (negative) balance is card debt, already in
/// Net Worth and the card's outstanding. Mirrors Web's Accounts/Dashboard
/// "Total balance". [netWorthProvider] stays the all-accounts sum Net Worth
/// is built on.
final cashBalanceProvider = Provider<double>((ref) {
  final cardAccountIds = ref.watch(_trackedCardAccountIdsProvider);
  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  return accounts
      .where((a) => !cardAccountIds.contains(a.id))
      .fold(0.0, (total, a) => total + a.currentBalance);
});

/// Card debt as the card accounts' own balances (−balance) — the exact figure
/// [netWorthProvider] already includes, so Assets − Debt reconciles to Net
/// Worth to the rupee.
final _cardAccountDebtProvider = Provider<double>((ref) {
  final cardAccountIds = ref.watch(_trackedCardAccountIdsProvider);
  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  final debt = -accounts
      .where((a) => cardAccountIds.contains(a.id))
      .fold(0.0, (total, a) => total + a.currentBalance);
  return debt < 0 ? 0 : debt;
});

/// Sum of every person's DIRECT ledger balance (split expenses, settlements,
/// manual entries) — Loans excluded, since they're already in the balance
/// sheet. + they owe me, − I owe them. Mirrors Web `useLoanBalanceSheet`.
final peopleDirectBalanceProvider = Provider<double>((ref) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  return people.fold(
    0.0,
    (total, p) => total + ref.watch(personPositionProvider(p.id)).directBalance,
  );
});

/// Every liability once — see [liabilityTotals].
final liabilityTotalsProvider = Provider<LiabilityTotals>((ref) {
  return liabilityTotals(
    ref.watch(loanBalanceSheetProvider),
    ref.watch(_cardAccountDebtProvider),
  );
});

/// Net Worth including loan principal (Decision 6) and People direct
/// balances — see [netWorthWithLoans]. [netWorthProvider] stays the plain
/// all-accounts sum it is built on.
final netWorthWithLoansProvider = Provider<double>((ref) {
  return netWorthWithLoans(
    ref.watch(netWorthProvider),
    ref.watch(loanBalanceSheetProvider),
    peopleDirectBalance: ref.watch(peopleDirectBalanceProvider),
  );
});
