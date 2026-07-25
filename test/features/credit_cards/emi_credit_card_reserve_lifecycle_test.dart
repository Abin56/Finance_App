import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the actual Riverpod providers (not just their math in
/// isolation, unlike `emi_credit_card_restoration_test.dart`) through the
/// full create/edit/close/delete lifecycle of a card-linked EMI, using the
/// `ProviderContainer` + `FakeFirebaseFirestore` pattern established in
/// `total_credit_limit_provider_test.dart`. Confirms Part 5 of the EMI spec
/// ("reserve on create, adjust on edit, release on close/delete") already
/// holds via `linkedEmiPrincipalForCardProvider` +
/// `principalRestoredForCardProvider` + `creditCardStandingProvider` — no
/// new credit-card logic was introduced for this.
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

  Future<String> createCard(String accountId, {double creditLimit = 100000}) async {
    final cards = container.read(creditCardRepositoryProvider);
    final card = await cards.createCard(
      accountId: accountId,
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: creditLimit,
    );
    return card.id;
  }

  test('reserve on create: linking an EMI to a card ties up its principal from available credit', () async {
    final accountId = await createCardAccount('ICICI Amazon Pay');
    final cardId = await createCard(accountId, creditLimit: 100000);
    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    final standingBefore = container.read(creditCardStandingProvider(cardId));
    expect(standingBefore.available, 100000);

    final emiRepository = container.read(emiRepositoryProvider);
    await emiRepository.createEmi(
      name: 'Laptop EMI',
      principalAmount: 25000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 6,
      linkedCreditCardId: cardId,
    );
    await container.read(emisStreamProvider.future);

    expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 25000);
    final standingAfter = container.read(creditCardStandingProvider(cardId));
    expect(standingAfter.available, 75000);
  });

  test('reserve on edit: changing principal before any payment adjusts the reservation', () async {
    final accountId = await createCardAccount('HDFC Card');
    final cardId = await createCard(accountId, creditLimit: 100000);
    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    final emiRepository = container.read(emiRepositoryProvider);
    final emi = await emiRepository.createEmi(
      name: 'Phone EMI',
      principalAmount: 20000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 4,
      linkedCreditCardId: cardId,
    );
    await container.read(emisStreamProvider.future);
    expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 20000);

    await emiRepository.editEmi(emi, hasPayments: false, principalAmount: 30000);
    await container.read(emisStreamProvider.future);

    expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 30000);
    expect(container.read(creditCardStandingProvider(cardId)).available, 70000);
  });

  test('reserve releases when the linked card is removed via edit', () async {
    final accountId = await createCardAccount('Axis Card');
    final cardId = await createCard(accountId, creditLimit: 50000);
    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    final emiRepository = container.read(emiRepositoryProvider);
    final emi = await emiRepository.createEmi(
      name: 'TV EMI',
      principalAmount: 15000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 3,
      linkedCreditCardId: cardId,
    );
    await container.read(emisStreamProvider.future);
    expect(container.read(creditCardStandingProvider(cardId)).available, 35000);

    await emiRepository.editEmi(emi, hasPayments: false, clearLinkedCreditCardId: true);
    await container.read(emisStreamProvider.future);

    expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 0);
    expect(container.read(creditCardStandingProvider(cardId)).available, 50000);
  });

  test('closing an EMI with no payments yet releases its full reserved principal', () async {
    final accountId = await createCardAccount('SBI Card');
    final cardId = await createCard(accountId, creditLimit: 50000);
    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    final emiRepository = container.read(emiRepositoryProvider);
    final emi = await emiRepository.createEmi(
      name: 'Furniture EMI',
      principalAmount: 15000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 3,
      linkedCreditCardId: cardId,
    );
    await container.read(emisStreamProvider.future);
    expect(container.read(creditCardStandingProvider(cardId)).available, 35000);

    await emiRepository.closeEmi(emi);
    await container.read(emisStreamProvider.future);

    expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 0);
    expect(container.read(creditCardStandingProvider(cardId)).available, 50000);
  });

  test(
    'closing a partially-paid EMI releases the remaining reserve without double-counting its past repayments',
    () async {
      // Regression coverage: a naive fix that only excluded closed EMIs
      // from linkedEmiPrincipalForCardProvider (and left
      // principalRestoredForCardProvider summing every linked EMI
      // regardless of isClosed) would let a partially-paid-then-closed
      // EMI's old repayments keep adding into `available` on top of its
      // principal already being fully excluded — overstating available
      // credit. Both providers must exclude isClosed EMIs together so a
      // closed EMI nets to exactly zero effect on the card's standing.
      final accountId = await createCardAccount('HSBC Card');
      final cardId = await createCard(accountId, creditLimit: 50000);
      await container.read(accountsStreamProvider.future);
      await container.read(creditCardsStreamProvider.future);

      final emiRepository = container.read(emiRepositoryProvider);
      final emi = await emiRepository.createEmi(
        name: 'Appliance EMI',
        principalAmount: 12000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
        linkedCreditCardId: cardId,
      );
      await container.read(emisStreamProvider.future);
      expect(container.read(creditCardStandingProvider(cardId)).available, 38000);

      final installments = await container.read(installmentRepositoryProvider(emi.scheduleId)).getAll();
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      final paymentKey = (scheduleId: emi.scheduleId, installmentId: sorted.first.id);
      final paymentRepository = container.read(installmentPaymentRepositoryProvider(paymentKey));
      await paymentRepository.recordPayment(sorted.first, amount: 4000, date: DateTime(2026, 2, 1));
      await container.read(installmentsStreamProvider(emi.scheduleId).future);
      await container.read(installmentPaymentsStreamProvider(paymentKey).future);

      expect(container.read(principalRestoredForCardProvider(cardId)), 4000);
      expect(container.read(creditCardStandingProvider(cardId)).available, 42000);

      await emiRepository.closeEmi(emi);
      await container.read(emisStreamProvider.future);

      // Both the remaining 8000 reserved AND the 4000 already restored drop
      // out together — available returns to the full 50000, not 54000.
      expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 0);
      expect(container.read(principalRestoredForCardProvider(cardId)), 0);
      expect(container.read(creditCardStandingProvider(cardId)).available, 50000);
    },
  );

  test('an EMI that reaches Completed by being fully paid off already shows zero remaining reserve', () async {
    // EmiStatus.completed is auto-derived (see Emi.statusGiven) the moment
    // every installment is paid — isClosed stays false until the user
    // explicitly taps "Close". No code change was needed for this
    // scenario: paying off every installment already drives
    // principalRestoredForCardProvider up to match linkedEmiPrincipalForCardProvider
    // exactly, so available is already fully restored before the user ever
    // closes the EMI.
    final accountId = await createCardAccount('Yes Bank Card');
    final cardId = await createCard(accountId, creditLimit: 50000);
    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    final emiRepository = container.read(emiRepositoryProvider);
    final emi = await emiRepository.createEmi(
      name: 'Headphones EMI',
      principalAmount: 6000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 2,
      linkedCreditCardId: cardId,
    );
    await container.read(emisStreamProvider.future);

    final installments = await container.read(installmentRepositoryProvider(emi.scheduleId)).getAll();
    final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    for (final installment in sorted) {
      final paymentKey = (scheduleId: emi.scheduleId, installmentId: installment.id);
      final paymentRepository = container.read(installmentPaymentRepositoryProvider(paymentKey));
      await paymentRepository.recordPayment(installment, amount: installment.amountDue, date: DateTime(2026, 1, 15));
      await container.read(installmentPaymentsStreamProvider(paymentKey).future);
    }
    await container.read(installmentsStreamProvider(emi.scheduleId).future);
    await container.read(emisStreamProvider.future);

    final updatedEmi = container.read(emisStreamProvider).value!.firstWhere((e) => e.id == emi.id);
    expect(updatedEmi.isClosed, isFalse);
    expect(container.read(creditCardStandingProvider(cardId)).available, 50000);
  });

  test('soft-deleting (trashing) an EMI releases its reservation, restoring available credit', () async {
    final accountId = await createCardAccount('Kotak Card');
    final cardId = await createCard(accountId, creditLimit: 50000);
    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    final emiRepository = container.read(emiRepositoryProvider);
    final emi = await emiRepository.createEmi(
      name: 'Fridge EMI',
      principalAmount: 15000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 3,
      linkedCreditCardId: cardId,
    );
    await container.read(emisStreamProvider.future);
    expect(container.read(creditCardStandingProvider(cardId)).available, 35000);

    await emiRepository.softDelete(emi);
    await container.read(emisStreamProvider.future);

    expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 0);
    expect(container.read(creditCardStandingProvider(cardId)).available, 50000);
  });

  test('permanently deleting an EMI (added by mistake) releases its reservation too', () async {
    final accountId = await createCardAccount('Standard Chartered Card');
    final cardId = await createCard(accountId, creditLimit: 50000);
    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);

    final emiRepository = container.read(emiRepositoryProvider);
    final emi = await emiRepository.createEmi(
      name: 'Mistaken EMI',
      principalAmount: 15000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 3,
      linkedCreditCardId: cardId,
    );
    await container.read(emisStreamProvider.future);
    expect(container.read(creditCardStandingProvider(cardId)).available, 35000);

    await emiRepository.permanentlyDeleteEmi(emi);
    await container.read(emisStreamProvider.future);

    expect(container.read(linkedEmiPrincipalForCardProvider(cardId)), 0);
    expect(container.read(creditCardStandingProvider(cardId)).available, 50000);
  });
}
