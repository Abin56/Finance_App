import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/models/payer_source.dart';
import 'package:finance_app/core/services/payment_attribution_service.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reproduction: retrying PaymentAttributionService duplicates the person ledger effect',
    () async {
      final firestore = FakeFirebaseFirestore();
      final people = firestore
          .collection('people')
          .withConverter<Person>(
            fromFirestore: Person.fromFirestore,
            toFirestore: (person, _) => person.toFirestore(),
          );
      final personRepository = PersonRepository(people);
      final bob = await personRepository.createPerson(
        name: 'Bob',
        avatarColorValue: 0xFF000000,
        openingBalance: 0,
      );
      final ledger = LedgerRepository(
        people
            .doc(bob.id)
            .collection('ledger')
            .withConverter<LedgerEntry>(
              fromFirestore: LedgerEntry.fromFirestore,
              toFirestore: (entry, _) => entry.toFirestore(),
            ),
        personRepository,
      );
      final service = PaymentAttributionService(
        ledgerRepositoryFor: (_) => ledger,
      );
      final items = [
        PaymentAttributionItem(
          obligationLabel: 'your loan payment',
          amount: 3000,
          record: ({required amount, required date, required note}) async {},
        ),
      ];

      await service.apply(
        items: items,
        payer: PayerSource.person(bob),
        date: DateTime.utc(2026, 1, 1),
      );
      await service.apply(
        items: items,
        payer: PayerSource.person(bob),
        date: DateTime.utc(2026, 1, 1),
      );

      final refreshed = await personRepository.getByKey(bob.id);
      expect(await ledger.getAll(), hasLength(2));
      expect(refreshed!.currentBalance, -6000);
    },
  );
}
