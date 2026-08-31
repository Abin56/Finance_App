import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../accounts/presentation/providers/account_deletion_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../data/credit_card_deletion_service.dart';
import 'credit_card_providers.dart';

/// Composes every repository the credit-card permanent-delete cascade needs
/// on top of [accountDeletionRepositoriesProvider] — same composition shape,
/// same "own file to avoid a circular file import" reasoning.
final creditCardDeletionRepositoriesProvider = Provider<CreditCardDeletionRepositories>((ref) {
  return CreditCardDeletionRepositories(
    accountDeletionRepositories: ref.watch(accountDeletionRepositoriesProvider),
    creditCardRepository: ref.watch(creditCardRepositoryProvider),
    sharedCreditLimitRepository: ref.watch(sharedCreditLimitRepositoryProvider),
    emiRepository: ref.watch(emiRepositoryProvider),
    statementRepositoryFor: (cardId) => ref.watch(statementRepositoryProvider(cardId)),
  );
});
