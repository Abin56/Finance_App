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
      createdAt: DateTime.now(),
    );
    await add(transaction.id, transaction);

    final account = await accountRepository.getByKey(accountId);
    if (account == null) throw NotFoundException('Account not found');
    await accountRepository.adjustBalance(account, transaction.signedAmount);

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
  }) async {
    final oldAccountId = transaction.accountId;
    final oldSignedAmount = transaction.signedAmount;

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

    final newSignedAmount = transaction.signedAmount;
    final newAccountId = transaction.accountId;

    if (oldAccountId == newAccountId) {
      final account = await accountRepository.getByKey(newAccountId);
      if (account == null) throw NotFoundException('Account not found');
      await accountRepository.adjustBalance(account, newSignedAmount - oldSignedAmount);
    } else {
      final oldAccount = await accountRepository.getByKey(oldAccountId);
      if (oldAccount == null) throw NotFoundException('Account not found');
      await accountRepository.adjustBalance(oldAccount, -oldSignedAmount);

      final newAccount = await accountRepository.getByKey(newAccountId);
      if (newAccount == null) throw NotFoundException('Account not found');
      await accountRepository.adjustBalance(newAccount, newSignedAmount);
    }

    await update(transaction);
  }

  /// Soft-deletes and reverses this transaction's effect on its account's
  /// balance, so trashed transactions don't keep counting toward it.
  Future<void> softDeleteTransaction(Transaction transaction) async {
    final account = await accountRepository.getByKey(transaction.accountId);
    if (account == null) throw NotFoundException('Account not found');
    await accountRepository.adjustBalance(account, -transaction.signedAmount);
    await softDelete(transaction);
  }

  /// Restores a trashed transaction and re-applies its balance effect.
  Future<void> restoreTransaction(Transaction transaction) async {
    final account = await accountRepository.getByKey(transaction.accountId);
    if (account == null) throw NotFoundException('Account not found');
    await accountRepository.adjustBalance(account, transaction.signedAmount);
    await restore(transaction);
  }

  /// Permanently removes a transaction document. No balance adjustment
  /// here — permanent delete is only reachable from the trash screen, and
  /// the balance was already reversed when the transaction was soft-deleted.
  Future<void> permanentlyDeleteTransaction(Transaction transaction) => permanentlyDelete(transaction);
}
