import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PersonRepository repository;

  setUp(() {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('people').withConverter<Person>(
          fromFirestore: Person.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    repository = PersonRepository(collection);
  });

  group('PersonRepository.createPerson', () {
    test('initializes currentBalance to openingBalance', () async {
      final person = await repository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: 300);
      expect(person.currentBalance, 300);
    });

    test('allows a negative opening balance', () async {
      final person = await repository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: -150);
      expect(person.openingBalance, -150);
      expect(person.currentBalance, -150);
    });

    test('rejects a duplicate name+phone', () async {
      await repository.createPerson(
        name: 'Alex',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        phone: '5551234',
      );

      await expectLater(
        repository.createPerson(
          name: 'Alex',
          avatarColorValue: 0xFF00C2A8,
          openingBalance: 0,
          phone: '5551234',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a duplicate name+email', () async {
      await repository.createPerson(
        name: 'Alex',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        email: 'alex@example.com',
      );

      await expectLater(
        repository.createPerson(
          name: 'Alex',
          avatarColorValue: 0xFF00C2A8,
          openingBalance: 0,
          email: 'alex@example.com',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('is case-insensitive on name when checking duplicates', () async {
      await repository.createPerson(
        name: 'Alex',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        phone: '5551234',
      );

      await expectLater(
        repository.createPerson(
          name: 'ALEX',
          avatarColorValue: 0xFF00C2A8,
          openingBalance: 0,
          phone: '5551234',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('allows the same name with no phone or email on either record', () async {
      await repository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final second = await repository.createPerson(
        name: 'Alex',
        avatarColorValue: 0xFF00C2A8,
        openingBalance: 0,
      );
      expect(second.name, 'Alex');
    });

    test('allows a different name with the same phone', () async {
      await repository.createPerson(
        name: 'Alex',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        phone: '5551234',
      );

      final second = await repository.createPerson(
        name: 'Jordan',
        avatarColorValue: 0xFF00C2A8,
        openingBalance: 0,
        phone: '5551234',
      );
      expect(second.name, 'Jordan');
    });
  });

  group('PersonRepository.editPerson', () {
    test('does not expose a way to change openingBalance', () async {
      final person = await repository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: 300);

      await repository.editPerson(person, name: 'Alexandra');

      expect(person.openingBalance, 300, reason: 'opening balance is immutable post-creation');
      expect(person.name, 'Alexandra');
    });

    test('records an audit entry per changed field', () async {
      final person = await repository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      await repository.editPerson(person, name: 'Alexandra', notes: 'Updated');

      expect(person.editHistory.map((e) => e.field), containsAll(['name', 'notes']));
    });
  });

  group('PersonRepository.adjustBalance', () {
    test('applies a signed delta and records an audit entry', () async {
      final person = await repository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: 100);

      await repository.adjustBalance(person, 50);

      expect(person.currentBalance, 150);
      expect(person.editHistory, hasLength(1));
      expect(person.editHistory.first.field, 'currentBalance');
    });

    test('is a no-op for a zero delta', () async {
      final person = await repository.createPerson(name: 'Alex', avatarColorValue: 0xFF5B5FEF, openingBalance: 100);

      await repository.adjustBalance(person, 0);

      expect(person.editHistory, isEmpty);
    });
  });
}
