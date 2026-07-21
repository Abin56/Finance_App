import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
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

/// Ledger repository for a single person's subcollection, scoped by
/// [personId] — a fresh repository per person, since each addresses a
/// different Firestore subcollection path.
final ledgerRepositoryProvider = Provider.autoDispose.family<LedgerRepository, String>((ref, personId) {
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

final ledgerStreamProvider = StreamProvider.autoDispose.family<List<LedgerEntry>, String>((ref, personId) {
  return ref.watch(ledgerRepositoryProvider(personId)).watchAll();
});

final ledgerTrashStreamProvider = StreamProvider.autoDispose.family<List<LedgerEntry>, String>((ref, personId) {
  return ref.watch(ledgerRepositoryProvider(personId)).watchTrash();
});

/// Plain `Transaction`s linked to [personId] (`Transaction.linkedPersonId`)
/// with no backing `Expense` — i.e., a pure reference (the "owed" toggle was
/// never turned on, or was turned back off). An owed transaction already has
/// a real `Expense`/`LedgerEntry` and surfaces through
/// [ledgerStreamProvider] instead, so it's excluded here to avoid appearing
/// twice in [PersonTimelineBuilder.build]'s merged output.
final personReferencedTransactionsProvider = Provider.autoDispose.family<List<Transaction>, String>((ref, personId) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  final transactionIdsWithExpense = {for (final e in expenses) e.transactionId};
  return transactions
      .where((t) => t.linkedPersonId == personId && !transactionIdsWithExpense.contains(t.id))
      .toList();
});
