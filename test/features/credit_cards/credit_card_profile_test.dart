import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/credit_cards/domain/card_network.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  CollectionReference<CreditCardProfile> cards() => firestore.collection('creditCards').withConverter<CreditCardProfile>(
        fromFirestore: CreditCardProfile.fromFirestore,
        toFirestore: (c, _) => c.toFirestore(),
      );

  test('round-trips a non-active status', () async {
    final card = CreditCardProfile(
      id: 'c1',
      accountId: 'a1',
      statementDay: 17,
      paymentDueDay: 5,
      creditLimit: 80000,
      createdAt: DateTime(2026, 1, 1),
      status: CreditCardStatus.cancelled,
    );
    await cards().doc('c1').set(card);

    final read = (await cards().doc('c1').get()).data()!;
    expect(read.status, CreditCardStatus.cancelled);
  });

  test('defaults to active for documents written before the status field existed', () async {
    await firestore.collection('creditCards').doc('c2').set({
      'accountId': 'a1',
      'statementDay': 17,
      'paymentDueDay': 5,
      'creditLimit': 80000,
      'autoPay': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });

    final read = (await cards().doc('c2').get()).data()!;
    expect(read.status, CreditCardStatus.active);
  });

  test('round-trips blocked status', () async {
    final card = CreditCardProfile(
      id: 'c3',
      accountId: 'a1',
      statementDay: 17,
      paymentDueDay: 5,
      creditLimit: 80000,
      createdAt: DateTime(2026, 1, 1),
      status: CreditCardStatus.blocked,
    );
    await cards().doc('c3').set(card);

    final read = (await cards().doc('c3').get()).data()!;
    expect(read.status, CreditCardStatus.blocked);
    expect(read.status.isActive, false);
  });

  test('round-trips every new loan-management-style field', () async {
    final card = CreditCardProfile(
      id: 'c4',
      accountId: 'a1',
      statementDay: 17,
      paymentDueDay: 5,
      creditLimit: 80000,
      createdAt: DateTime(2026, 1, 1),
      cardNetwork: CardNetwork.visa,
      lastFourDigits: '1234',
      annualFee: 500,
      joiningFee: 1000,
      interestRatePercent: 3.5,
      rewardNotes: '5% cashback on groceries',
      autoPay: true,
      autoDebitAccount: 'Savings XXXX',
    );
    await cards().doc('c4').set(card);

    final read = (await cards().doc('c4').get()).data()!;
    expect(read.cardNetwork, CardNetwork.visa);
    expect(read.lastFourDigits, '1234');
    expect(read.annualFee, 500);
    expect(read.joiningFee, 1000);
    expect(read.interestRatePercent, 3.5);
    expect(read.rewardNotes, '5% cashback on groceries');
    expect(read.autoDebitAccount, 'Savings XXXX');
  });

  test('defaults new fields safely for a document written before this upgrade', () async {
    await firestore.collection('creditCards').doc('c5').set({
      'accountId': 'a1',
      'statementDay': 17,
      'paymentDueDay': 5,
      'creditLimit': 80000,
      'autoPay': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });

    final read = (await cards().doc('c5').get()).data()!;
    expect(read.cardNetwork, isNull);
    expect(read.lastFourDigits, isNull);
    expect(read.annualFee, 0);
    expect(read.joiningFee, 0);
    expect(read.interestRatePercent, isNull);
    expect(read.rewardNotes, isNull);
    expect(read.autoDebitAccount, isNull);
  });
}
