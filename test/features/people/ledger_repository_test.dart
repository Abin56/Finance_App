import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late PersonRepository personRepository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final peopleCollection = firestore.collection('people').withConverter<Person>(
          fromFirestore: Person.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    personRepository = PersonRepository(peopleCollection);
  });

  LedgerRepository ledgerRepositoryFor(String personId) {
    final collection = firestore
        .collection('people')
        .doc(personId)
        .collection('ledger')
        .withConverter<LedgerEntry>(
          fromFirestore: LedgerEntry.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        );
    return LedgerRepository(collection, personRepository);
  }

  Future<Person> seedPerson({double openingBalance = 0}) {
    return personRepository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: openingBalance);
  }

  group('LedgerRepository.addEntry balance sync', () {
    test('gave increases the balance', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);

      await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 50, date: DateTime(2026, 1, 1));

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 150);
    });

    test('borrowed decreases the balance', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);

      await ledger.addEntry(person, type: LedgerEntryType.borrowed, amount: 30, date: DateTime(2026, 1, 1));

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 70);
    });

    test('receivedBack decreases the balance', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);

      await ledger.addEntry(person, type: LedgerEntryType.receivedBack, amount: 40, date: DateTime(2026, 1, 1));

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 60);
    });

    test('repaid increases the balance', () async {
      final person = await seedPerson(openingBalance: -100);
      final ledger = ledgerRepositoryFor(person.id);

      await ledger.addEntry(person, type: LedgerEntryType.repaid, amount: 40, date: DateTime(2026, 1, 1));

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, -60);
    });

    test('adjustment can move the balance either way', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);

      await ledger.addEntry(
        person,
        type: LedgerEntryType.adjustment,
        amount: 25,
        date: DateTime(2026, 1, 1),
        increasesBalance: false,
      );

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 75);
    });

    test('adjustment with increasesBalance: true (the AdjustBalanceSheet "increase" direction) raises the balance', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);

      await ledger.addEntry(
        person,
        type: LedgerEntryType.adjustment,
        amount: 25,
        date: DateTime(2026, 1, 1),
        note: 'Correcting a missed cash payment',
      );

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 125);
    });

    test('rejects a non-positive amount', () async {
      final person = await seedPerson();
      final ledger = ledgerRepositoryFor(person.id);

      await expectLater(
        ledger.addEntry(person, type: LedgerEntryType.gave, amount: 0, date: DateTime(2026, 1, 1)),
        throwsA(isA<AppException>()),
      );
    });

    test('a sequence of entries produces the expected final balance', () async {
      final person = await seedPerson(openingBalance: 1000);
      final ledger = ledgerRepositoryFor(person.id);

      await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 500, date: DateTime(2026, 1, 1));
      await ledger.addEntry(person, type: LedgerEntryType.receivedBack, amount: 200, date: DateTime(2026, 1, 2));
      await ledger.addEntry(person, type: LedgerEntryType.borrowed, amount: 100, date: DateTime(2026, 1, 3));
      await ledger.addEntry(person, type: LedgerEntryType.repaid, amount: 50, date: DateTime(2026, 1, 4));

      // 1000 + 500 - 200 - 100 + 50 = 1250
      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 1250);
    });
  });

  group('LedgerRepository.editEntryAmount', () {
    test('updates the entry\'s amount in place and adjusts the balance by the delta', () async {
      final person = await seedPerson(openingBalance: 0);
      final ledger = ledgerRepositoryFor(person.id);
      final entry = await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 50, date: DateTime(2026, 1, 1));

      await ledger.editEntryAmount(person, entry, 80);

      expect(entry.amount, 80);
      final stored = await ledger.getByKey(entry.id);
      expect(stored!.amount, 80);
      final updatedPerson = await personRepository.getByKey(person.id);
      expect(updatedPerson!.currentBalance, 80);
    });

    test('records the change in editHistory/lastEditedAt', () async {
      final person = await seedPerson();
      final ledger = ledgerRepositoryFor(person.id);
      final entry = await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 50, date: DateTime(2026, 1, 1));

      await ledger.editEntryAmount(person, entry, 60);

      expect(entry.lastEditedAt, isNotNull);
      expect(entry.editHistory, hasLength(1));
      expect(entry.editHistory.single.field, 'amount');
    });

    test('rejects a non-positive amount', () async {
      final person = await seedPerson();
      final ledger = ledgerRepositoryFor(person.id);
      final entry = await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 50, date: DateTime(2026, 1, 1));

      await expectLater(
        ledger.editEntryAmount(person, entry, 0),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('LedgerRepository.softDeleteEntry / restoreEntry', () {
    test('softDeleteEntry reverses the balance effect', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);
      final entry = await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 50, date: DateTime(2026, 1, 1));

      await ledger.softDeleteEntry(person, entry);

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 100);
      expect(entry.isDeleted, isTrue);
    });

    test('restoreEntry re-applies the balance effect', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);
      final entry = await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 50, date: DateTime(2026, 1, 1));
      await ledger.softDeleteEntry(person, entry);

      await ledger.restoreEntry(person, entry);

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 150);
      expect(entry.isDeleted, isFalse);
    });

    test('permanentlyDeleteEntry does not change the balance again', () async {
      final person = await seedPerson(openingBalance: 100);
      final ledger = ledgerRepositoryFor(person.id);
      final entry = await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 50, date: DateTime(2026, 1, 1));
      await ledger.softDeleteEntry(person, entry);

      await ledger.permanentlyDeleteEntry(entry);

      final updated = await personRepository.getByKey(person.id);
      expect(updated!.currentBalance, 100);
      expect(await ledger.getByKey(entry.id), isNull);
    });
  });
}
