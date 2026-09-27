import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Emi.purchaseTransactionId` persistence rules — identical to Web's
/// `tests/integration/card-emi-ownership.test.ts` "persistence" block.
void main() {
  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
  });

  Future create({String? card = 'card-1', String? purchase = 'txn-1'}) =>
      container.read(emiRepositoryProvider).createEmi(
            name: 'iPhone EMI',
            principalAmount: 60000,
            startDate: DateTime(2026, 9, 1),
            installmentFrequency: ScheduleType.monthly,
            installmentCount: 12,
            linkedCreditCardId: card,
            purchaseTransactionId: purchase,
          );

  test('round-trips on create', () async {
    final emi = await create();
    final read = await container.read(emiRepositoryProvider).getByKey(emi.id);
    expect(read!.purchaseTransactionId, 'txn-1');
  });

  test('a purchase link without a credit card is refused', () async {
    await expectLater(create(card: null), throwsA(isA<AppException>()));
  });

  test('editing other fields keeps the link; unlinking the card clears it', () async {
    final repository = container.read(emiRepositoryProvider);
    final emi = await create();
    await repository.editEmi(emi, hasPayments: false, name: 'Renamed');
    final renamed = (await repository.getByKey(emi.id))!;
    expect(renamed.name, 'Renamed');
    expect(renamed.purchaseTransactionId, 'txn-1');
    await repository.editEmi(renamed, hasPayments: false, clearLinkedCreditCardId: true);
    final unlinked = (await repository.getByKey(emi.id))!;
    expect(unlinked.linkedCreditCardId, isNull);
    expect(unlinked.purchaseTransactionId, isNull);
  });
}
