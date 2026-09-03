import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../../accounts/data/account_repository.dart';
import '../domain/transaction.dart';
import '../domain/transaction_type.dart';

/// Transaction-specific persistence on top of the generic CRUD/soft-delete
/// repository. Every create/edit/soft-delete/restore here also adjusts the
/// affected account's `currentBalance` via [accountRepository] — this is
/// the single integration point that keeps balances accurate, so no other
/// code path should mutate a transaction's effect on a balance directly.
class TransactionRepository extends FirestoreCrudRepository<Transaction> {
  TransactionRepository(super.collection, this.accountRepository);

  final AccountRepository accountRepository;

  Future<Transaction> createTransaction({
    required TransactionType type,
    required double amount,
    required DateTime dateTime,
    required String accountId,
    required String categoryId,
    String description = '',
    String notes = '',
    String? receiptPurpose,
    bool excludeFromCalculations = false,
    DateTime? accountingMonth,
    String? linkedPersonId,
    bool owesPersonToggle = false,
    String? source,
  }) async {
    final transaction = Transaction(
      id: IdGenerator.generate(),
      type: type,
      amount: amount,
      dateTime: dateTime,
      accountId: accountId,
      categoryId: categoryId,
      description: description,
      notes: notes,
      receiptPurpose: receiptPurpose,
      excludeFromCalculations: excludeFromCalculations,
      accountingMonth: accountingMonth,
      linkedPersonId: linkedPersonId,
      owesPersonToggle: owesPersonToggle,
      createdAt: DateTime.now(),
      source: source,
    );
    await add(transaction.id, transaction);

    final account = await accountRepository.getByKey(accountId);
    if (account == null) throw NotFoundException('Account not found');
    await accountRepository.adjustBalance(account, transaction.balanceEffect);

    return transaction;
  }

  /// Handles every edit permutation — amount, type, or account can each
  /// change independently (or together) in one edit, and each affects
  /// balances differently:
  ///  - same account: apply the net delta between old and new signed amount.
  ///  - different account: fully reverse the old amount on the old account,
  ///    fully apply the new amount on the new account.
  Future<void> editTransaction(
    Transaction transaction, {
    TransactionType? type,
    double? amount,
    DateTime? dateTime,
    String? accountId,
    String? categoryId,
    String? description,
    String? notes,
    bool? excludeFromCalculations,
    DateTime? accountingMonth,
    bool clearAccountingMonth = false,
    String? linkedPersonId,
    bool clearLinkedPersonId = false,
    bool? owesPersonToggle,
  }) async {
    final oldAccountId = transaction.accountId;
    final oldBalanceEffect = transaction.balanceEffect;

    transaction.updateField(
      field: 'type',
      oldValue: transaction.type,
      newValue: type,
      apply: (v) => transaction.type = v,
    );
    transaction.updateField(
      field: 'amount',
      oldValue: transaction.amount,
      newValue: amount,
      apply: (v) => transaction.amount = v,
    );
    transaction.updateField(
      field: 'dateTime',
      oldValue: transaction.dateTime,
      newValue: dateTime,
      apply: (v) => transaction.dateTime = v,
    );
    transaction.updateField(
      field: 'accountId',
      oldValue: transaction.accountId,
      newValue: accountId,
      apply: (v) => transaction.accountId = v,
    );
    transaction.updateField(
      field: 'categoryId',
      oldValue: transaction.categoryId,
      newValue: categoryId,
      apply: (v) => transaction.categoryId = v,
    );
    transaction.updateField(
      field: 'description',
      oldValue: transaction.description,
      newValue: description,
      apply: (v) => transaction.description = v,
    );
    transaction.updateField(
      field: 'notes',
      oldValue: transaction.notes,
      newValue: notes,
      apply: (v) => transaction.notes = v,
    );
    transaction.updateField(
      field: 'excludeFromCalculations',
      oldValue: transaction.excludeFromCalculations,
      newValue: excludeFromCalculations,
      apply: (v) => transaction.excludeFromCalculations = v,
    );
    if (clearAccountingMonth) {
      transaction.recordEdit(
        field: 'accountingMonth',
        oldValue: transaction.accountingMonth?.toString() ?? 'none',
        newValue: 'none',
      );
      transaction.accountingMonth = null;
    } else {
      transaction.updateField(
        field: 'accountingMonth',
        oldValue: transaction.accountingMonth,
        newValue: accountingMonth,
        apply: (v) => transaction.accountingMonth = v,
      );
    }
    if (clearLinkedPersonId) {
      transaction.recordEdit(
        field: 'linkedPersonId',
        oldValue: transaction.linkedPersonId ?? 'none',
        newValue: 'none',
      );
      transaction.linkedPersonId = null;
    } else {
      transaction.updateField(
        field: 'linkedPersonId',
        oldValue: transaction.linkedPersonId,
        newValue: linkedPersonId,
        apply: (v) => transaction.linkedPersonId = v,
      );
    }
    transaction.updateField(
      field: 'owesPersonToggle',
      oldValue: transaction.owesPersonToggle,
      newValue: owesPersonToggle,
      apply: (v) => transaction.owesPersonToggle = v,
    );

    // Computed after every field update above so a same-transaction toggle of
    // excludeFromCalculations (in either direction) is captured by the delta
    // below exactly like an amount/account change would be — no separate
    // branch needed, since balanceEffect is already 0 whenever excluded.
    final newBalanceEffect = transaction.balanceEffect;
    final newAccountId = transaction.accountId;

    if (oldAccountId == newAccountId) {
      final account = await accountRepository.getByKey(newAccountId);
      if (account == null) throw NotFoundException('Account not found');
      await accountRepository.adjustBalance(account, newBalanceEffect - oldBalanceEffect);
    } else {
      final oldAccount = await accountRepository.getByKey(oldAccountId);
      if (oldAccount == null) throw NotFoundException('Account not found');
      await accountRepository.adjustBalance(oldAccount, -oldBalanceEffect);

      final newAccount = await accountRepository.getByKey(newAccountId);
      if (newAccount == null) throw NotFoundException('Account not found');
      await accountRepository.adjustBalance(newAccount, newBalanceEffect);
    }

    await update(transaction);
  }

  /// Soft-deletes and reverses this transaction's effect on its account's
  /// balance, so trashed transactions don't keep counting toward it.
  Future<void> softDeleteTransaction(Transaction transaction) async {
    final account = await accountRepository.getByKey(transaction.accountId);
    if (account == null) throw NotFoundException('Account not found');
    await accountRepository.adjustBalance(account, -transaction.balanceEffect);
    await softDelete(transaction);
  }

  /// Restores a trashed transaction and re-applies its balance effect.
  Future<void> restoreTransaction(Transaction transaction) async {
    final account = await accountRepository.getByKey(transaction.accountId);
    if (account == null) throw NotFoundException('Account not found');
    await accountRepository.adjustBalance(account, transaction.balanceEffect);
    await restore(transaction);
  }

  /// Permanently removes a transaction document. No balance adjustment
  /// here — permanent delete is only reachable from the trash screen, and
  /// the balance was already reversed when the transaction was soft-deleted.
  Future<void> permanentlyDeleteTransaction(Transaction transaction) => permanentlyDelete(transaction);

  /// Every transaction referencing [accountId], active and trashed alike —
  /// the full set the account/credit-card permanent-delete cascade
  /// (`account_deletion_service.dart`) needs to wipe alongside the account
  /// itself, unlike a plain [getAll]/[getTrash] (which each only see one
  /// side of `deletedAt`).
  Future<List<Transaction>> getAllForAccountIncludingTrash(String accountId) async {
    final snapshot = await collection.where('accountId', isEqualTo: accountId).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}
