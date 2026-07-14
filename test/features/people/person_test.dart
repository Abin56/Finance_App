import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Person.isCreditor / isDebtor', () {
    test('positive balance is a creditor, not a debtor', () {
      final person = Person(
        id: 'p1',
        name: 'Alex',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        currentBalance: 500,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(person.isCreditor, isTrue);
      expect(person.isDebtor, isFalse);
    });

    test('negative balance is a debtor, not a creditor', () {
      final person = Person(
        id: 'p1',
        name: 'Alex',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        currentBalance: -500,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(person.isCreditor, isFalse);
      expect(person.isDebtor, isTrue);
    });

    test('zero balance is neither', () {
      final person = Person(
        id: 'p1',
        name: 'Alex',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        currentBalance: 0,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(person.isCreditor, isFalse);
      expect(person.isDebtor, isFalse);
    });
  });

  group('Person Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every field', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('people').withConverter<Person>(
            fromFirestore: Person.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          );

      final original = Person(
        id: 'ignored',
        name: 'Alex Rivera',
        phone: '+1 555 0100',
        email: 'alex@example.com',
        notes: 'Coworker',
        avatarColorValue: 0xFF00C2A8,
        openingBalance: -200,
        currentBalance: -200,
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('p1').set(original);
      final restored = (await collection.doc('p1').get()).data()!;

      expect(restored.id, 'p1');
      expect(restored.name, 'Alex Rivera');
      expect(restored.phone, '+1 555 0100');
      expect(restored.email, 'alex@example.com');
      expect(restored.notes, 'Coworker');
      expect(restored.openingBalance, -200);
      expect(restored.currentBalance, -200);
      expect(restored.isDebtor, isTrue);
    });

    test('preserves null phone and email', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('people').withConverter<Person>(
            fromFirestore: Person.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          );

      final original = Person(
        id: 'ignored',
        name: 'No contact info',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
        currentBalance: 0,
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('p2').set(original);
      final restored = (await collection.doc('p2').get()).data()!;

      expect(restored.phone, isNull);
      expect(restored.email, isNull);
    });
  });
}
