import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the bug where a card's `CreditCardProfile`
/// document had no delete action of its own — deleting a card was only
/// reachable by soft-deleting its linked Account from the Accounts screen,
/// which left the CreditCardProfile permanently active and still counted
/// in every outstanding-balance total. `activeCreditCardsProvider` fixes
/// this by filtering out any card whose linked Account no longer exists.
void main() {
  late ProviderContainer container;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
  });

  test('excludes a card whose linked account has been deleted', () async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: 'Test Card',
      type: AccountType.card,
      openingBalance: 0,
      colorValue: 0xFF000000,
    );

    final cards = container.read(creditCardRepositoryProvider);
    await cards.createCard(
      accountId: account.id,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
    );

    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    expect(container.read(activeCreditCardsProvider), hasLength(1));

    await accounts.softDelete(account);
    await container.read(accountsStreamProvider.future);

    expect(
      container.read(activeCreditCardsProvider),
      isEmpty,
      reason: 'a card whose account was deleted must disappear from the active list',
    );
  });

  test('a restored account brings its card back into the active list', () async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: 'Test Card',
      type: AccountType.card,
      openingBalance: 0,
      colorValue: 0xFF000000,
    );

    final cards = container.read(creditCardRepositoryProvider);
    await cards.createCard(
      accountId: account.id,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
    );

    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    await accounts.softDelete(account);
    await container.read(accountsStreamProvider.future);
    expect(container.read(activeCreditCardsProvider), isEmpty);

    await accounts.restore(account);
    await container.read(accountsStreamProvider.future);

    expect(container.read(activeCreditCardsProvider), hasLength(1));
  });

  test('does not affect a card whose account is still active', () async {
    final accounts = container.read(accountRepositoryProvider);
    final keptAccount = await accounts.createAccount(
      name: 'Kept Card',
      type: AccountType.card,
      openingBalance: 0,
      colorValue: 0xFF000000,
    );
    final deletedAccount = await accounts.createAccount(
      name: 'Deleted Card',
      type: AccountType.card,
      openingBalance: 0,
      colorValue: 0xFF000000,
    );

    final cards = container.read(creditCardRepositoryProvider);
    await cards.createCard(accountId: keptAccount.id, statementDay: 5, paymentDueDay: 25, creditLimit: 50000);
    await cards.createCard(accountId: deletedAccount.id, statementDay: 10, paymentDueDay: 28, creditLimit: 75000);

    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    await accounts.softDelete(deletedAccount);
    await container.read(accountsStreamProvider.future);

    final active = container.read(activeCreditCardsProvider);
    expect(active, hasLength(1));
    expect(active.single.accountId, keptAccount.id);
  });
}
