import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/unified_finance_agreement.dart';

/// Live, deterministic, read-only composition of the existing Loan and EMI
/// streams. No migration or write repository is invoked.
final unifiedFinanceAgreementsProvider =
    Provider<List<UnifiedFinanceAgreement>>((ref) {
      final loans = ref.watch(loansStreamProvider).value ?? const [];
      final emis = ref.watch(emisStreamProvider).value ?? const [];
      final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
      final transactions =
          ref.watch(transactionsStreamProvider).value ?? const [];
      final cardById = {for (final card in cards) card.id: card};
      final transactionById = {
        for (final transaction in transactions) transaction.id: transaction,
      };
      return sortUnifiedAgreements([
        for (final loan in loans)
          loanToUnifiedAgreement(
            loan,
            ref.watch(installmentsStreamProvider(loan.scheduleId)).value ??
                const [],
            ownership: cardById[loan.linkedCreditCardId] == null
                ? null
                : (
                    cardAccountId: cardById[loan.linkedCreditCardId]!.accountId,
                    purchase: transactionById[loan.purchaseTransactionId],
                  ),
          ),
        for (final emi in emis)
          emiToUnifiedAgreement(
            emi,
            ref.watch(installmentsStreamProvider(emi.scheduleId)).value ??
                const [],
            ownership: cardById[emi.linkedCreditCardId] == null
                ? null
                : (
                    cardAccountId: cardById[emi.linkedCreditCardId]!.accountId,
                    purchase: transactionById[emi.purchaseTransactionId],
                  ),
          ),
      ]);
    });

/// Aggregate state for the source streams used by the unified workspace.
/// The list provider stays a simple, synchronous projection while the screen
/// can still distinguish first-load and source failures from a genuine empty
/// data set.
final unifiedFinanceAgreementsStateProvider = Provider<AsyncValue<void>>((ref) {
  final loans = ref.watch(loansStreamProvider);
  final emis = ref.watch(emisStreamProvider);
  final cards = ref.watch(creditCardsStreamProvider);
  final transactions = ref.watch(transactionsStreamProvider);

  for (final source in [loans, emis, cards, transactions]) {
    if (source.hasError) {
      return AsyncError(source.error!, source.stackTrace ?? StackTrace.current);
    }
  }
  if (loans.isLoading ||
      emis.isLoading ||
      cards.isLoading ||
      transactions.isLoading) {
    return const AsyncLoading();
  }
  return const AsyncData(null);
});
