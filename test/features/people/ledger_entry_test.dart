import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LedgerEntryType.signFor sign table', () {
    test('gave increases the balance', () {
      expect(LedgerEntryType.gave.signFor(100), 100);
    });

    test('repaid increases the balance', () {
      expect(LedgerEntryType.repaid.signFor(100), 100);
    });

    test('borrowed decreases the balance', () {
      expect(LedgerEntryType.borrowed.signFor(100), -100);
    });

    test('receivedBack decreases the balance', () {
      expect(LedgerEntryType.receivedBack.signFor(100), -100);
    });

    test('adjustment passes the amount through unchanged', () {
      expect(LedgerEntryType.adjustment.signFor(100), 100);
    });
  });

  group('LedgerEntry.signedAmount', () {
    test('matches type.signFor for non-adjustment types', () {
      final entry = LedgerEntry(
        id: 'e1',
        personId: 'p1',
        type: LedgerEntryType.borrowed,
        amount: 50,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );
      expect(entry.signedAmount, -50);
    });

    test('adjustment respects increasesBalance rather than signFor', () {
      final increasing = LedgerEntry(
        id: 'e1',
        personId: 'p1',
        type: LedgerEntryType.adjustment,
        amount: 50,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        increasesBalance: true,
      );
      final decreasing = LedgerEntry(
        id: 'e2',
        personId: 'p1',
        type: LedgerEntryType.adjustment,
        amount: 50,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        increasesBalance: false,
      );
      expect(increasing.signedAmount, 50);
      expect(decreasing.signedAmount, -50);
    });
  });

  group('LedgerEntry Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every field including transactionRef', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('ledger').withConverter<LedgerEntry>(
            fromFirestore: LedgerEntry.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );

      final original = LedgerEntry(
        id: 'ignored',
        personId: 'p1',
        type: LedgerEntryType.repaid,
        amount: 75,
        date: DateTime(2026, 2, 1),
        note: 'Paid back for lunch',
        transactionRef: 'txn-123',
        createdAt: DateTime(2026, 2, 1),
      );

      await collection.doc('e1').set(original);
      final restored = (await collection.doc('e1').get()).data()!;

      expect(restored.id, 'e1');
      expect(restored.personId, 'p1');
      expect(restored.type, LedgerEntryType.repaid);
      expect(restored.amount, 75);
      expect(restored.date, DateTime(2026, 2, 1));
      expect(restored.note, 'Paid back for lunch');
      expect(restored.transactionRef, 'txn-123');
      expect(restored.increasesBalance, isTrue);
    });

    test('preserves increasesBalance=false for a decreasing adjustment', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('ledger').withConverter<LedgerEntry>(
            fromFirestore: LedgerEntry.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );

      final original = LedgerEntry(
        id: 'ignored',
        personId: 'p1',
        type: LedgerEntryType.adjustment,
        amount: 20,
        date: DateTime(2026, 2, 1),
        createdAt: DateTime(2026, 2, 1),
        increasesBalance: false,
      );

      await collection.doc('e2').set(original);
      final restored = (await collection.doc('e2').get()).data()!;

      expect(restored.increasesBalance, isFalse);
      expect(restored.signedAmount, -20);
    });
  });
}
