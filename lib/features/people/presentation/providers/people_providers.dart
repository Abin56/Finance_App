import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/ledger_repository.dart';
import '../../data/person_repository.dart';
import '../../domain/ledger_entry.dart';
import '../../domain/person.dart';

final personRepositoryProvider = Provider<PersonRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.people)
      .withConverter<Person>(
        fromFirestore: Person.fromFirestore,
        toFirestore: (person, _) => person.toFirestore(),
      );
  return PersonRepository(collection);
});

final peopleStreamProvider = StreamProvider<List<Person>>((ref) {
  return ref.watch(personRepositoryProvider).watchAll();
});

final peopleTrashStreamProvider = StreamProvider<List<Person>>((ref) {
  return ref.watch(personRepositoryProvider).watchTrash();
});

/// People who owe you money (positive balance), largest first.
final creditorsProvider = Provider<List<Person>>((ref) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  final creditors = people.where((p) => p.isCreditor).toList()
    ..sort((a, b) => b.currentBalance.compareTo(a.currentBalance));
  return creditors;
});

/// People you owe money to (negative balance), largest first.
final debtorsProvider = Provider<List<Person>>((ref) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  final debtors = people.where((p) => p.isDebtor).toList()
    ..sort((a, b) => a.currentBalance.compareTo(b.currentBalance));
  return debtors;
});

/// Sum of every positive balance — total money owed to you.
final totalReceivableProvider = Provider<double>((ref) {
  return ref.watch(creditorsProvider).fold(0.0, (total, p) => total + p.currentBalance);
});

/// Sum of the absolute value of every negative balance — total money you owe.
final totalPayableProvider = Provider<double>((ref) {
  return ref.watch(debtorsProvider).fold(0.0, (total, p) => total + p.currentBalance.abs());
});

/// The single person with the largest outstanding balance (either
/// direction), or null if no one has an outstanding balance.
final largestOutstandingProvider = Provider<Person?>((ref) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  final withBalance = people.where((p) => p.currentBalance != 0).toList();
  if (withBalance.isEmpty) return null;
  withBalance.sort((a, b) => b.currentBalance.abs().compareTo(a.currentBalance.abs()));
  return withBalance.first;
});

/// Ledger repository for a single person's subcollection, scoped by
/// [personId] — a fresh repository per person, since each addresses a
/// different Firestore subcollection path.
final ledgerRepositoryProvider = Provider.family<LedgerRepository, String>((ref, personId) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.people)
      .doc(personId)
      .collection(FirestoreCollections.ledger)
      .withConverter<LedgerEntry>(
        fromFirestore: LedgerEntry.fromFirestore,
        toFirestore: (entry, _) => entry.toFirestore(),
      );
  return LedgerRepository(collection, ref.watch(personRepositoryProvider));
});

final ledgerStreamProvider = StreamProvider.family<List<LedgerEntry>, String>((ref, personId) {
  return ref.watch(ledgerRepositoryProvider(personId)).watchAll();
});

final ledgerTrashStreamProvider = StreamProvider.family<List<LedgerEntry>, String>((ref, personId) {
  return ref.watch(ledgerRepositoryProvider(personId)).watchTrash();
});
