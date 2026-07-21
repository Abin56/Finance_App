import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/ledger_entry.dart';
import '../domain/ledger_entry_type.dart';
import '../domain/person.dart';
import 'person_repository.dart';

/// Ledger-entry persistence for one person's `users/{uid}/people/{personId}/ledger`
/// subcollection. Constructed per-person (see `ledgerRepositoryProvider`),
/// with a [personRepository] reference so every write can keep
/// [Person.currentBalance] in sync — the same dependency shape
/// `TransactionRepository` uses for `AccountRepository`.
class LedgerRepository extends FirestoreCrudRepository<LedgerEntry> {
  LedgerRepository(super.collection, this.personRepository);

  final PersonRepository personRepository;

  /// Creates the entry and applies its signed effect to the person's
  /// cached balance — mirrors `TransactionRepository.createTransaction`'s
  /// account-sync sequence exactly. Entries are otherwise append-only:
  /// besides [editEntryAmount]'s narrow amount-correction case, the only
  /// ways an entry's balance effect changes are [softDeleteEntry]/
  /// [restoreEntry].
  ///
  /// [amount] is always positive, matching [LedgerEntry.amount]'s
  /// invariant — direction comes from [type], never from the sign of
  /// [amount]. For [LedgerEntryType.adjustment], pass [increasesBalance] to
  /// choose which direction the correction moves the balance.
  Future<LedgerEntry> addEntry(
    Person person, {
    required LedgerEntryType type,
    required double amount,
    required DateTime date,
    String note = '',
    String? transactionRef,
    bool increasesBalance = true,
  }) async {
    if (amount <= 0) {
      throw const AppException('Amount must be greater than 0');
    }

    final entry = LedgerEntry(
      id: IdGenerator.generate(),
      personId: person.id,
      type: type,
      amount: amount,
      date: date,
      note: note,
      transactionRef: transactionRef,
      increasesBalance: increasesBalance,
      createdAt: DateTime.now(),
    );
    await add(entry.id, entry);
    await personRepository.adjustBalance(person, entry.signedAmount);
    return entry;
  }

  /// Corrects an already-posted entry's [LedgerEntry.amount] in place and
  /// re-syncs the person's cached balance by the delta — the one exception
  /// to "append-only" (see [LedgerEntry]'s class doc), used by
  /// `ExpenseRepository.editExpense` so editing a split/assigned expense's
  /// amount updates the same history line the user tapped instead of
  /// leaving it stale next to a separate "Correct Balance" entry.
  Future<void> editEntryAmount(Person person, LedgerEntry entry, double newAmount) async {
    if (newAmount <= 0) {
      throw const AppException('Amount must be greater than 0');
    }
    final oldSignedAmount = entry.signedAmount;
    entry.updateField(
      field: 'amount',
      oldValue: entry.amount,
      newValue: newAmount,
      apply: (v) => entry.amount = v,
    );
    await update(entry);
    await personRepository.adjustBalance(person, entry.signedAmount - oldSignedAmount);
  }

  /// Reverses the entry's balance effect, then soft-deletes it — mirrors
  /// `TransactionRepository.softDeleteTransaction`.
  Future<void> softDeleteEntry(Person person, LedgerEntry entry) async {
    await personRepository.adjustBalance(person, -entry.signedAmount);
    await softDelete(entry);
  }

  /// Re-applies the entry's balance effect, then restores it — mirrors
  /// `TransactionRepository.restoreTransaction`.
  Future<void> restoreEntry(Person person, LedgerEntry entry) async {
    await personRepository.adjustBalance(person, entry.signedAmount);
    await restore(entry);
  }

  /// No balance change — already reversed at soft-delete time. Mirrors
  /// `TransactionRepository.permanentlyDeleteTransaction`.
  Future<void> permanentlyDeleteEntry(LedgerEntry entry) => permanentlyDelete(entry);

  /// Active entries whose [LedgerEntry.transactionRef] matches
  /// [transactionId] — a targeted query for callers that only need "this
  /// expense's" ledger entries, instead of fetching the whole subcollection
  /// via [getAll] and filtering client-side.
  Future<List<LedgerEntry>> getByTransactionRef(String transactionId) async {
    final snapshot =
        await collection.where('deletedAt', isNull: true).where('transactionRef', isEqualTo: transactionId).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  /// [getByTransactionRef], but over trashed entries — mirrors [getTrash]
  /// vs [getAll].
  Future<List<LedgerEntry>> getTrashByTransactionRef(String transactionId) async {
    final snapshot =
        await collection.where('deletedAt', isNull: false).where('transactionRef', isEqualTo: transactionId).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}
