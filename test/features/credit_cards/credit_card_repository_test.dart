import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/credit_cards/data/credit_card_repository.dart';
import 'package:finance_app/features/credit_cards/domain/card_network.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late CreditCardRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('creditCards').withConverter<CreditCardProfile>(
          fromFirestore: CreditCardProfile.fromFirestore,
          toFirestore: (c, _) => c.toFirestore(),
        );
    repository = CreditCardRepository(collection);
  });

  group('CreditCardRepository.createCard — loan-management-style fields', () {
    test('persists network/last-4/fees/reward notes passed at creation', () async {
      final card = await repository.createCard(
        accountId: 'a1',
        statementDay: 17,
        paymentDueDay: 5,
        creditLimit: 80000,
        cardNetwork: CardNetwork.mastercard,
        lastFourDigits: '4321',
        annualFee: 500,
        joiningFee: 1000,
        interestRatePercent: 3.5,
        rewardNotes: '5% cashback on dining',
        autoDebitAccount: 'Savings XXXX',
      );

      expect(card.cardNetwork, CardNetwork.mastercard);
      expect(card.lastFourDigits, '4321');
      expect(card.annualFee, 500);
      expect(card.joiningFee, 1000);
      expect(card.interestRatePercent, 3.5);
      expect(card.rewardNotes, '5% cashback on dining');
      expect(card.autoDebitAccount, 'Savings XXXX');
    });

    test('defaults fees to 0 and network to null when not provided', () async {
      final card = await repository.createCard(
        accountId: 'a1',
        statementDay: 17,
        paymentDueDay: 5,
        creditLimit: 80000,
      );

      expect(card.cardNetwork, isNull);
      expect(card.annualFee, 0);
      expect(card.joiningFee, 0);
    });

    test('rejects a last-4-digits value that is not exactly 4 digits', () async {
      await expectLater(
        repository.createCard(
          accountId: 'a1',
          statementDay: 17,
          paymentDueDay: 5,
          creditLimit: 80000,
          lastFourDigits: '123',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a last-4-digits value containing non-digit characters', () async {
      await expectLater(
        repository.createCard(
          accountId: 'a1',
          statementDay: 17,
          paymentDueDay: 5,
          creditLimit: 80000,
          lastFourDigits: 'ab12',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('CreditCardRepository.editCard — loan-management-style fields', () {
    test('updates network/last-4/fees/reward notes/auto debit account', () async {
      final card = await repository.createCard(
        accountId: 'a1',
        statementDay: 17,
        paymentDueDay: 5,
        creditLimit: 80000,
      );

      await repository.editCard(
        card,
        cardNetwork: CardNetwork.rupay,
        lastFourDigits: '9999',
        annualFee: 250,
        joiningFee: 0,
        interestRatePercent: 2.9,
        rewardNotes: '2x points on fuel',
        autoPay: true,
        autoDebitAccount: 'Checking XXXX',
      );

      expect(card.cardNetwork, CardNetwork.rupay);
      expect(card.lastFourDigits, '9999');
      expect(card.annualFee, 250);
      expect(card.interestRatePercent, 2.9);
      expect(card.rewardNotes, '2x points on fuel');
      expect(card.autoPay, true);
      expect(card.autoDebitAccount, 'Checking XXXX');
    });

    test('rejects changing last-4-digits to an invalid value', () async {
      final card = await repository.createCard(
        accountId: 'a1',
        statementDay: 17,
        paymentDueDay: 5,
        creditLimit: 80000,
      );

      await expectLater(
        repository.editCard(card, lastFourDigits: '12'),
        throwsA(isA<AppException>()),
      );
    });

    test('transitions status to blocked and back to active', () async {
      final card = await repository.createCard(
        accountId: 'a1',
        statementDay: 17,
        paymentDueDay: 5,
        creditLimit: 80000,
      );

      await repository.editCard(card, status: CreditCardStatus.blocked);
      expect(card.status, CreditCardStatus.blocked);
      expect(card.status.isActive, false);

      await repository.editCard(card, status: CreditCardStatus.active);
      expect(card.status, CreditCardStatus.active);
      expect(card.status.isActive, true);
    });
  });
}
