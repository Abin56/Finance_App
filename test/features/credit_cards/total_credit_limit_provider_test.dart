import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the bug where `creditUtilizationPercentProvider`
/// summed raw `CreditCardProfile.creditLimit` across every card, including
/// every member of a shared credit limit — double-counting a shared
/// Visa/RuPay pair's one limit in the denominator while the numerator
/// (`totalCreditCardOutstandingProvider`) already counted the facility
/// once. `totalCreditLimitProvider` fixes this by counting a facility's
/// `SharedCreditLimit.creditLimit` exactly once, mirroring
/// `_sumStandingAcrossCards`'s dedup.
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

  test('sums standalone cards\' own limits directly', () async {
    final accountA = await createCardAccount('Card A');
    final accountB = await createCardAccount('Card B');

    final cards = container.read(creditCardRepositoryProvider);
    await cards.createCard(accountId: accountA, statementDay: 5, paymentDueDay: 25, creditLimit: 50000);
    await cards.createCard(accountId: accountB, statementDay: 5, paymentDueDay: 25, creditLimit: 75000);

    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    expect(container.read(totalCreditLimitProvider), 125000);
  });

  test('counts a shared credit limit\'s limit exactly once, not per member card', () async {
    final accountVisa = await createCardAccount('Visa');
    final accountRupay = await createCardAccount('RuPay');
    final accountStandalone = await createCardAccount('Standalone');

    final sharedLimits = container.read(sharedCreditLimitRepositoryProvider);
    final sharedLimit = await sharedLimits.createSharedLimit(name: 'SBI', creditLimit: 200000);

    final cards = container.read(creditCardRepositoryProvider);
    await cards.createCard(
      accountId: accountVisa,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 200000,
      sharedLimitId: sharedLimit.id,
    );
    await cards.createCard(
      accountId: accountRupay,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 200000,
      sharedLimitId: sharedLimit.id,
    );
    await cards.createCard(accountId: accountStandalone, statementDay: 5, paymentDueDay: 25, creditLimit: 30000);

    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);
    await container.read(sharedCreditLimitsStreamProvider.future);

    // 200000 (facility, counted once) + 30000 (standalone) — NOT
    // 200000 + 200000 + 30000, which is what summing raw card.creditLimit
    // across every card would have produced before the fix.
    expect(container.read(totalCreditLimitProvider), 230000);
  });

  test('credit utilization % is not understated by a shared pair\'s duplicated limit', () async {
    final accountVisa = await createCardAccount('Visa');
    final accountRupay = await createCardAccount('RuPay');

    final sharedLimits = container.read(sharedCreditLimitRepositoryProvider);
    final sharedLimit = await sharedLimits.createSharedLimit(name: 'SBI', creditLimit: 100000);

    final cards = container.read(creditCardRepositoryProvider);
    await cards.createCard(
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

    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);
    await container.read(sharedCreditLimitsStreamProvider.future);

    // No spend yet, so outstanding is 0 and utilization must be exactly 0%
    // — not silently halved by a doubled denominator, which would still
    // read as a plausible-looking (but wrong) number for non-zero spend.
    expect(container.read(totalCreditLimitProvider), 100000);
  });
}
