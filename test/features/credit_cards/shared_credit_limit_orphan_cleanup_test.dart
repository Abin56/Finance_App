import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/credit_cards/data/credit_card_repository.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the gap where removing the last card from a
/// shared credit limit left the now-empty `SharedCreditLimit` document
/// active forever — it would keep showing up as a dead "Existing shared
/// credit limit" option in `CreditCardFormSheet` with no cards actually
/// drawing from it.
///
/// The cleanup now lives in `CreditCardRepository.editCard` itself (not the
/// UI), so every path that moves a card off a facility — this screen, or
/// any future API/import/sync call site — gets it automatically instead of
/// relying on each caller to remember to check.
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

  Future<String> createCardAccount(String name) async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: name,
      type: AccountType.card,
      openingBalance: 0,
      colorValue: 0xFF000000,
    );
    return account.id;
  }

  test('going standalone as the sole remaining card trashes the now-empty SharedCreditLimit', () async {
    final accountId = await createCardAccount('Visa');

    final sharedLimits = container.read(sharedCreditLimitRepositoryProvider);
    final sharedLimit = await sharedLimits.createSharedLimit(name: 'SBI', creditLimit: 100000);

    final cards = container.read(creditCardRepositoryProvider);
    final card = await cards.createCard(
      accountId: accountId,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
      sharedLimitId: sharedLimit.id,
    );

    await cards.editCard(card, clearSharedLimitId: true, creditLimit: 50000);

    expect(
      await sharedLimits.getAll(),
      isEmpty,
      reason: 'the orphaned SharedCreditLimit must be trashed once its last card leaves',
    );
  });

  test('going standalone on one of two cards keeps the facility active for the remaining sibling', () async {
    final accountVisa = await createCardAccount('Visa');
    final accountRupay = await createCardAccount('RuPay');

    final sharedLimits = container.read(sharedCreditLimitRepositoryProvider);
    final sharedLimit = await sharedLimits.createSharedLimit(name: 'SBI', creditLimit: 100000);

    final cards = container.read(creditCardRepositoryProvider);
    final visaCard = await cards.createCard(
      accountId: accountVisa,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
      sharedLimitId: sharedLimit.id,
    );
    await cards.createCard(
      accountId: accountRupay,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
      sharedLimitId: sharedLimit.id,
    );

    await cards.editCard(visaCard, clearSharedLimitId: true, creditLimit: 60000);

    expect(
      await sharedLimits.getAll(),
      hasLength(1),
      reason: 'the facility still has a card (RuPay) attached, so it must stay active',
    );
  });

  test('moving a card to a different shared limit trashes the facility it left', () async {
    final accountVisa = await createCardAccount('Visa');

    final sharedLimits = container.read(sharedCreditLimitRepositoryProvider);
    final oldSharedLimit = await sharedLimits.createSharedLimit(name: 'Old Facility', creditLimit: 100000);
    final newSharedLimit = await sharedLimits.createSharedLimit(name: 'New Facility', creditLimit: 150000);

    final cards = container.read(creditCardRepositoryProvider);
    final card = await cards.createCard(
      accountId: accountVisa,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
      sharedLimitId: oldSharedLimit.id,
    );

    await cards.editCard(card, sharedLimitId: newSharedLimit.id);

    final activeSharedLimits = await sharedLimits.getAll();
    expect(activeSharedLimits.map((g) => g.id), [newSharedLimit.id]);
  });

  test('a CreditCardRepository with no injected SharedCreditLimitRepository still updates without error', () async {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('creditCards').withConverter<CreditCardProfile>(
          fromFirestore: CreditCardProfile.fromFirestore,
          toFirestore: (c, _) => c.toFirestore(),
        );
    final repository = CreditCardRepository(collection);

    final card = await repository.createCard(
      accountId: 'a1',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
      sharedLimitId: 'some-facility',
    );

    await expectLater(
      repository.editCard(card, clearSharedLimitId: true, creditLimit: 50000),
      completes,
    );
  });
}
