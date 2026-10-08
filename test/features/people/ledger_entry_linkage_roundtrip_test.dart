import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: this app's `update()` is a full-document `set()`. Before the
/// linkage fields existed on [LedgerEntry], soft-deleting / restoring /
/// editing a settlement the web app wrote silently removed its
/// `parentEntryId` / `sourceKind` / `obligationRef` / `receivedStatus` /
/// `paymentId` — detaching the payment from the obligation it paid.
void main() {
  test('soft delete + restore + amount edit keep every web-written link', () async {
    final firestore = FakeFirebaseFirestore();
    final people = firestore.collection('people').withConverter<Person>(
          fromFirestore: Person.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    final personRepository = PersonRepository(people);
    final person = await personRepository.createPerson(
      name: 'Amma',
      avatarColorValue: 0xFF5B5FEF,
      openingBalance: 0,
    );
    final raw = firestore.collection('people').doc(person.id).collection('ledger');
    final ledger = LedgerRepository(
      raw.withConverter<LedgerEntry>(
        fromFirestore: LedgerEntry.fromFirestore,
        toFirestore: (e, _) => e.toFirestore(),
      ),
      personRepository,
    );

    // A settlement as the web app's Record Payment writes it.
    final webDoc = {
      'personId': person.id,
      'type': 'receivedBack',
      'amount': 600.0,
      'date': Timestamp.fromDate(DateTime(2026, 9, 30)),
      'note': '',
      'transactionRef': 'cash-leg-1',
      'increasesBalance': true,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
      'parentEntryId': 'kseb',
      'sourceKind': 'manual',
      'obligationRef': 'emi-inst:i1',
      'receivedStatus': 'received',
      'paymentId': 'pay-1',
      'installmentPaymentRef': 's/i/p',
      'incomeTransactionRef': 'inc-1',
      'deletedAt': null,
      'lastEditedAt': null,
      'editHistory': <dynamic>[],
    };
    await raw.doc('settle-1').set(webDoc);

    final entry = (await ledger.getByKey('settle-1'))!;
    await ledger.softDeleteEntry(person, entry);
    await ledger.restoreEntry(person, (await ledger.getTrash()).single);
    await ledger.editEntryAmount(person, (await ledger.getByKey('settle-1'))!, 500);

    final stored = (await raw.doc('settle-1').get()).data()!;
    for (final key in [
      'parentEntryId',
      'sourceKind',
      'obligationRef',
      'receivedStatus',
      'paymentId',
      'installmentPaymentRef',
      'incomeTransactionRef',
    ]) {
      expect(stored[key], webDoc[key], reason: key);
    }
    expect(stored['amount'], 500);
  });

  test('entries created here carry the same defaults as the web app', () async {
    final firestore = FakeFirebaseFirestore();
    final people = firestore.collection('people').withConverter<Person>(
          fromFirestore: Person.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    final personRepository = PersonRepository(people);
    final person = await personRepository.createPerson(
      name: 'Amma',
      avatarColorValue: 0xFF5B5FEF,
      openingBalance: 0,
    );
    final ledger = LedgerRepository(
      firestore.collection('people').doc(person.id).collection('ledger').withConverter<LedgerEntry>(
            fromFirestore: LedgerEntry.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          ),
      personRepository,
    );
    final entry = await ledger.addEntry(
      person,
      type: LedgerEntryType.gave,
      amount: 1000,
      date: DateTime(2026, 9, 29),
    );
    expect(entry.sourceKind, 'manual');
    expect(entry.receivedStatus, 'yetToReceive');
  });
}
