import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/payment_schedule/domain/payment_allocation_type.dart';
import '../../../core/utils/id_generator.dart';
import '../../accounts/data/account_repository.dart';
import '../domain/transaction.dart';
import '../domain/transaction_type.dart';

/// Thrown when [TransactionRepository.softDeleteTransaction]/
/// [TransactionRepository.restoreTransaction] is called directly on a
/// Transaction linked to a loan/EMI payment ([Transaction.loanId]/
/// [Transaction.emiId] set). Those generic single-document operations only
/// reverse the Transaction's own balance effect — they know nothing about
/// the linked `InstallmentPayment`/`Installment.amountPaid`, so calling them
/// directly desyncs the loan's payment history from the account balance
/// (reproduced in `test/features/lending/loan_advance_payment_reversal_test.dart`'s
/// "generic delete guard" coverage). Use
/// `LoanAdvancePaymentRepository.reversePayment` instead, which reverses
/// both atomically.
class LoanPaymentTransactionRestrictedError extends AppException {
  const LoanPaymentTransactionRestrictedError()
    : super(
        'This transaction is linked to a loan/EMI payment — deleting or '
        'restoring it directly would desync the loan\'s payment history '
        'from the account balance. Reverse the payment from the loan/EMI '
        'screen instead.',
      );
}

/// Transaction-specific persistence on top of the generic CRUD/soft-delete
/// repository. Every create/edit/soft-delete/restore here also adjusts the
/// affected account's `currentBalance` via [accountRepository] — this is
/// the single integration point that keeps balances accurate, so no other
/// code path should mutate a transaction's effect on a balance directly.
///
/// Every public method below (`createTransaction`/`editTransaction`/
/// `softDeleteTransaction`/`restoreTransaction`) opens exactly one Firestore
/// `runTransaction` and delegates to a matching `*InTransaction` method that
/// does the actual work using the caller-supplied `fs.Transaction`. This
/// makes the transaction-doc write and the account-balance write one atomic
/// unit instead of two independently-awaited operations (previously: `add()`
/// then a separately-transactional `adjustBalance()` — a crash between the
/// two could leave a `Transaction` doc with no balance effect applied, or
/// vice versa). The `*InTransaction` methods are also the composition point
/// for callers that need this write folded into a *larger* atomic
/// operation — e.g. the loan/EMI payment pipeline, which additionally
/// writes an `InstallmentPayment` and an `Installment` update in the same
/// transaction — rather than opening a second, nested `runTransaction`
/// (which Firestore does not support). Such callers must perform every read
/// they need (installment, loan, person, ...) before calling any
/// `*InTransaction` method here, since Firestore requires all reads in a
/// transaction to happen before any writes, and these methods write.
class TransactionRepository extends FirestoreCrudRepository<Transaction> {
  TransactionRepository(super.collection, this.accountRepository);

  final AccountRepository accountRepository;

  /// Composable form of [createTransaction] — builds the [Transaction] and
  /// writes it, plus the account-balance effect, via the caller's open
  /// [transaction] instead of opening a new one. See the class doc comment
  /// for why this exists and the read-before-write ordering constraint on
  /// callers.
  Future<Transaction> createTransactionInTransaction(
    fs.Transaction transaction, {
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
    String? loanId,
    String? emiId,
    String? installmentId,
    String? installmentPaymentId,
    PaymentAllocationType? paymentAllocationType,
  }) async {
    final built = Transaction(
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
      loanId: loanId,
      emiId: emiId,
      installmentId: installmentId,
      installmentPaymentId: installmentPaymentId,
      paymentAllocationType: paymentAllocationType,
    );

    // Always validates the account exists, regardless of balanceEffect —
    // matches this method's pre-refactor behavior (an explicit getByKey
    // null-check before ever calling adjustBalance).
    await accountRepository.applyBalanceDeltaInTransaction(
      transaction,
      accountId,
      built.balanceEffect,
    );
    transaction.set(collection.doc(built.id), built);
    return built;
  }

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
    String? loanId,
    String? emiId,
    String? installmentId,
    String? installmentPaymentId,
    PaymentAllocationType? paymentAllocationType,
  }) async {
    late final Transaction result;
    await collection.firestore.runTransaction((transaction) async {
      result = await createTransactionInTransaction(
        transaction,
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
        source: source,
        loanId: loanId,
        emiId: emiId,
        installmentId: installmentId,
        installmentPaymentId: installmentPaymentId,
        paymentAllocationType: paymentAllocationType,
      );
    });
    return result;
  }

  /// Composable form of [editTransaction] — see the class doc comment for
  /// why this exists and the read-before-write ordering constraint on
  /// callers. Handles every edit permutation — amount, type, or account can
  /// each change independently (or together) in one edit, and each affects
  /// balances differently:
  ///  - same account: apply the net delta between old and new signed amount.
  ///  - different account: fully reverse the old amount on the old account,
  ///    fully apply the new amount on the new account. Both accounts are
  ///    read before either is written, since Firestore transactions require
  ///    every read to precede every write.
  Future<void> editTransactionInTransaction(
    fs.Transaction transaction,
    Transaction entity, {
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
    final oldAccountId = entity.accountId;
    final oldBalanceEffect = entity.balanceEffect;

    entity.updateField(
      field: 'type',
      oldValue: entity.type,
      newValue: type,
      apply: (v) => entity.type = v,
    );
    entity.updateField(
      field: 'amount',
      oldValue: entity.amount,
      newValue: amount,
      apply: (v) => entity.amount = v,
    );
    entity.updateField(
      field: 'dateTime',
      oldValue: entity.dateTime,
      newValue: dateTime,
      apply: (v) => entity.dateTime = v,
    );
    entity.updateField(
      field: 'accountId',
      oldValue: entity.accountId,
      newValue: accountId,
      apply: (v) => entity.accountId = v,
    );
    entity.updateField(
      field: 'categoryId',
      oldValue: entity.categoryId,
      newValue: categoryId,
      apply: (v) => entity.categoryId = v,
    );
    entity.updateField(
      field: 'description',
      oldValue: entity.description,
      newValue: description,
      apply: (v) => entity.description = v,
    );
    entity.updateField(
      field: 'notes',
      oldValue: entity.notes,
      newValue: notes,
      apply: (v) => entity.notes = v,
    );
    entity.updateField(
      field: 'excludeFromCalculations',
      oldValue: entity.excludeFromCalculations,
      newValue: excludeFromCalculations,
      apply: (v) => entity.excludeFromCalculations = v,
    );
    if (clearAccountingMonth) {
      entity.recordEdit(
        field: 'accountingMonth',
        oldValue: entity.accountingMonth?.toString() ?? 'none',
        newValue: 'none',
      );
      entity.accountingMonth = null;
    } else {
      entity.updateField(
        field: 'accountingMonth',
        oldValue: entity.accountingMonth,
        newValue: accountingMonth,
        apply: (v) => entity.accountingMonth = v,
      );
    }
    if (clearLinkedPersonId) {
      entity.recordEdit(
        field: 'linkedPersonId',
        oldValue: entity.linkedPersonId ?? 'none',
        newValue: 'none',
      );
      entity.linkedPersonId = null;
    } else {
      entity.updateField(
        field: 'linkedPersonId',
        oldValue: entity.linkedPersonId,
        newValue: linkedPersonId,
        apply: (v) => entity.linkedPersonId = v,
      );
    }
    entity.updateField(
      field: 'owesPersonToggle',
      oldValue: entity.owesPersonToggle,
      newValue: owesPersonToggle,
      apply: (v) => entity.owesPersonToggle = v,
    );

    // Computed after every field update above so a same-transaction toggle of
    // excludeFromCalculations (in either direction) is captured by the delta
    // below exactly like an amount/account change would be — no separate
    // branch needed, since balanceEffect is already 0 whenever excluded.
    final newBalanceEffect = entity.balanceEffect;
    final newAccountId = entity.accountId;

    if (oldAccountId == newAccountId) {
      await accountRepository.applyBalanceDeltaInTransaction(
        transaction,
        newAccountId,
        newBalanceEffect - oldBalanceEffect,
      );
    } else {
      // Both accounts must be read before either is written — Firestore
      // transactions require every read to precede every write, so two
      // sequential read+write pairs (as the pre-atomicity code effectively
      // performed via two separate adjustBalance calls) would throw at
      // runtime once folded into a single transaction.
      final oldAccount = await accountRepository.getForUpdateInTransaction(
        transaction,
        oldAccountId,
      );
      final newAccount = await accountRepository.getForUpdateInTransaction(
        transaction,
        newAccountId,
      );
      accountRepository.applyBalanceDeltaWrite(
        transaction,
        oldAccount,
        -oldBalanceEffect,
      );
      accountRepository.applyBalanceDeltaWrite(
        transaction,
        newAccount,
        newBalanceEffect,
      );
    }

    transaction.set(collection.doc(entity.id), entity);
  }

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
    await collection.firestore.runTransaction((txn) async {
      await editTransactionInTransaction(
        txn,
        transaction,
        type: type,
        amount: amount,
        dateTime: dateTime,
        accountId: accountId,
        categoryId: categoryId,
        description: description,
        notes: notes,
        excludeFromCalculations: excludeFromCalculations,
        accountingMonth: accountingMonth,
        clearAccountingMonth: clearAccountingMonth,
        linkedPersonId: linkedPersonId,
        clearLinkedPersonId: clearLinkedPersonId,
        owesPersonToggle: owesPersonToggle,
      );
    });
  }

  /// Composable form of [softDeleteTransaction]. See the class doc comment.
  Future<void> softDeleteTransactionInTransaction(
    fs.Transaction transaction,
    Transaction entity,
  ) async {
    await accountRepository.applyBalanceDeltaInTransaction(
      transaction,
      entity.accountId,
      -entity.balanceEffect,
    );
    entity.markDeleted();
    transaction.set(collection.doc(entity.id), entity);
  }

  /// Soft-deletes and reverses this transaction's effect on its account's
  /// balance, so trashed transactions don't keep counting toward it.
  ///
  /// Throws [LoanPaymentTransactionRestrictedError] for a loan/EMI-linked
  /// transaction — see that error's doc comment.
  Future<void> softDeleteTransaction(Transaction transaction) async {
    if (transaction.loanId != null || transaction.emiId != null) {
      throw const LoanPaymentTransactionRestrictedError();
    }
    await collection.firestore.runTransaction((txn) async {
      await softDeleteTransactionInTransaction(txn, transaction);
    });
  }

  /// Composable form of [restoreTransaction]. See the class doc comment.
  Future<void> restoreTransactionInTransaction(
    fs.Transaction transaction,
    Transaction entity,
  ) async {
    await accountRepository.applyBalanceDeltaInTransaction(
      transaction,
      entity.accountId,
      entity.balanceEffect,
    );
    entity.restoreFromTrash();
    transaction.set(collection.doc(entity.id), entity);
  }

  /// Restores a trashed transaction and re-applies its balance effect.
  ///
  /// Throws [LoanPaymentTransactionRestrictedError] for a loan/EMI-linked
  /// transaction — see that error's doc comment.
  Future<void> restoreTransaction(Transaction transaction) async {
    if (transaction.loanId != null || transaction.emiId != null) {
      throw const LoanPaymentTransactionRestrictedError();
    }
    await collection.firestore.runTransaction((txn) async {
      await restoreTransactionInTransaction(txn, transaction);
    });
  }

  /// Permanently removes a transaction document. No balance adjustment
  /// here — permanent delete is only reachable from the trash screen, and
  /// the balance was already reversed when the transaction was soft-deleted.
  Future<void> permanentlyDeleteTransaction(Transaction transaction) =>
      permanentlyDelete(transaction);

  /// Every transaction referencing [accountId], active and trashed alike —
  /// the full set the account/credit-card permanent-delete cascade
  /// (`account_deletion_service.dart`) needs to wipe alongside the account
  /// itself, unlike a plain [getAll]/[getTrash] (which each only see one
  /// side of `deletedAt`).
  Future<List<Transaction>> getAllForAccountIncludingTrash(
    String accountId,
  ) async {
    final snapshot = await collection
        .where('accountId', isEqualTo: accountId)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}
