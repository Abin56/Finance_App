import '../../../core/constants/firestore_constants.dart';
import '../../accounts/data/account_deletion_service.dart';
import '../../emi/data/emi_repository.dart';
import '../../emi/domain/emi.dart';
import '../domain/credit_card_profile.dart';
import '../domain/statement.dart';
import 'credit_card_repository.dart';
import 'shared_credit_limit_repository.dart';
import 'statement_repository.dart';

/// Everything [permanentlyDeleteCreditCardAndHistory]/[previewCreditCardDeletionImpact]
/// need beyond the plain account cascade — mirrors [AccountDeletionRepositories]'s
/// dependency-bag shape. Built by `creditCardDeletionRepositoriesProvider`.
class CreditCardDeletionRepositories {
  const CreditCardDeletionRepositories({
    required this.accountDeletionRepositories,
    required this.creditCardRepository,
    required this.sharedCreditLimitRepository,
    required this.emiRepository,
    required this.statementRepositoryFor,
  });

  final AccountDeletionRepositories accountDeletionRepositories;
  final CreditCardRepository creditCardRepository;
  final SharedCreditLimitRepository sharedCreditLimitRepository;
  final EmiRepository emiRepository;
  final StatementRepository Function(String cardId) statementRepositoryFor;
}

/// What permanently deleting a credit card will destroy, on top of
/// [AccountDeletionImpact] for its underlying account.
class CreditCardDeletionImpact {
  const CreditCardDeletionImpact({
    required this.accountImpact,
    required this.emiCount,
    required this.statementCount,
    required this.sharedLimitWillBeRemoved,
  });

  final AccountDeletionImpact accountImpact;
  final int emiCount;
  final int statementCount;
  final bool sharedLimitWillBeRemoved;
}

class _CardExtras {
  const _CardExtras({
    required this.emis,
    required this.statementRepository,
    required this.statements,
    required this.sharedLimitWillBeRemoved,
  });

  final List<Emi> emis;
  final StatementRepository statementRepository;
  final List<Statement> statements;
  final bool sharedLimitWillBeRemoved;
}

Future<_CardExtras> _gatherCardExtras(CreditCardProfile card, CreditCardDeletionRepositories repos) async {
  final allEmis = [...await repos.emiRepository.getAll(), ...await repos.emiRepository.getTrash()];
  final emis = allEmis.where((e) => e.linkedCreditCardId == card.id).toList();

  final statementRepository = repos.statementRepositoryFor(card.id);
  final statements = [...await statementRepository.getAll(), ...await statementRepository.getTrash()];

  var sharedLimitWillBeRemoved = false;
  final sharedLimitId = card.sharedLimitId;
  if (sharedLimitId != null) {
    final allCards = await repos.creditCardRepository.getAll();
    sharedLimitWillBeRemoved = !allCards.any((c) => c.id != card.id && c.sharedLimitId == sharedLimitId);
  }

  return _CardExtras(
    emis: emis,
    statementRepository: statementRepository,
    statements: statements,
    sharedLimitWillBeRemoved: sharedLimitWillBeRemoved,
  );
}

/// Read-only preview for the type-to-confirm delete dialog.
Future<CreditCardDeletionImpact> previewCreditCardDeletionImpact(
  CreditCardProfile card,
  CreditCardDeletionRepositories repos,
) async {
  final accountImpact = await previewAccountDeletionImpact(card.accountId, repos.accountDeletionRepositories);
  final extras = await _gatherCardExtras(card, repos);
  return CreditCardDeletionImpact(
    accountImpact: accountImpact,
    emiCount: extras.emis.length,
    statementCount: extras.statements.length,
    sharedLimitWillBeRemoved: extras.sharedLimitWillBeRemoved,
  );
}

/// Full cascade: linked EMIs (via the existing [EmiRepository.permanentlyDeleteEmi]),
/// every statement + its payments, an orphaned shared credit limit, then the
/// shared account-history cascade for [CreditCardProfile.accountId], and
/// finally the [CreditCardProfile] document and its [Account] document
/// themselves. Only ever reached after the destructive-delete dialog's
/// type-to-confirm gate.
Future<void> permanentlyDeleteCreditCardAndHistory(
  CreditCardProfile card,
  CreditCardDeletionRepositories repos,
) async {
  final extras = await _gatherCardExtras(card, repos);

  for (final emi in extras.emis) {
    await repos.emiRepository.permanentlyDeleteEmi(emi);
  }

  for (final statement in extras.statements) {
    final paymentsSnapshot = await extras.statementRepository.collection
        .doc(statement.id)
        .collection(FirestoreCollections.statementPayments)
        .get();
    for (final paymentDoc in paymentsSnapshot.docs) {
      await paymentDoc.reference.delete();
    }
    await extras.statementRepository.permanentlyDelete(statement);
  }

  final sharedLimitId = card.sharedLimitId;
  if (extras.sharedLimitWillBeRemoved && sharedLimitId != null) {
    final sharedLimit = await repos.sharedCreditLimitRepository.getByKey(sharedLimitId);
    if (sharedLimit != null) {
      await repos.sharedCreditLimitRepository.permanentlyDelete(sharedLimit);
    }
  }

  await permanentlyDeleteAccountHistory(card.accountId, repos.accountDeletionRepositories);

  await repos.creditCardRepository.permanentlyDelete(card);
  final account = await repos.accountDeletionRepositories.accountRepository.getByKey(card.accountId);
  if (account != null) {
    await repos.accountDeletionRepositories.accountRepository.permanentlyDelete(account);
  }
}
