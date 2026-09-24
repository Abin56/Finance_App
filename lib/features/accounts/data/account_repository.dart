import 'package:cloud_firestore/cloud_firestore.dart' show Transaction;

import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/account.dart';
import '../domain/account_type.dart';

/// Account-specific persistence on top of the generic CRUD/soft-delete
/// repository.
class AccountRepository extends FirestoreCrudRepository<Account> {
  AccountRepository(super.collection);

  static final _last4DigitsPattern = RegExp(r'^\d{4}$');

  Future<Account> createAccount({
    required String name,
    required AccountType type,
    required double openingBalance,
    required int colorValue,
    bool isDefault = false,
    String? bankId,
    String? accountHolderName,
    String? notes,
    String? accountNumberLast4,
  }) async {
    _validate(accountNumberLast4: accountNumberLast4);
    final account = Account(
      id: IdGenerator.generate(),
      name: name,
      type: type,
      openingBalance: openingBalance,
      currentBalance: openingBalance,
      colorValue: colorValue,
      isDefault: isDefault,
      createdAt: DateTime.now(),
      bankId: bankId,
      accountHolderName: accountHolderName,
      notes: notes,
      accountNumberLast4: accountNumberLast4,
    );
    await add(account.id, account);
    return account;
  }

  /// Edits preserve history: each changed field is recorded before the
  /// new values are written, so nothing is silently overwritten.
  /// Opening balance is deliberately not editable here — see [Account].
  Future<void> editAccount(
    Account account, {
    String? name,
    AccountType? type,
    int? colorValue,
    String? bankId,
    bool clearBankId = false,
    String? accountHolderName,
    bool clearAccountHolderName = false,
    String? notes,
    bool clearNotes = false,
    String? accountNumberLast4,
    bool clearAccountNumberLast4 = false,
  }) async {
    _validate(
      accountNumberLast4: clearAccountNumberLast4
          ? null
          : accountNumberLast4 ?? account.accountNumberLast4,
    );

    account.updateField(
      field: 'name',
      oldValue: account.name,
      newValue: name,
      apply: (v) => account.name = v,
    );
    account.updateField(
      field: 'type',
      oldValue: account.type,
      newValue: type,
      apply: (v) => account.type = v,
    );
    account.updateField(
      field: 'color',
      oldValue: account.colorValue,
      newValue: colorValue,
      apply: (v) => account.colorValue = v,
    );
    if (clearBankId) {
      account.recordEdit(
        field: 'bankId',
        oldValue: account.bankId ?? 'none',
        newValue: 'none',
      );
      account.bankId = null;
    } else {
      account.updateField(
        field: 'bankId',
        oldValue: account.bankId,
        newValue: bankId,
        apply: (v) => account.bankId = v,
      );
    }
    if (clearAccountHolderName) {
      account.recordEdit(
        field: 'accountHolderName',
        oldValue: account.accountHolderName ?? 'none',
        newValue: 'none',
      );
      account.accountHolderName = null;
    } else {
      account.updateField(
        field: 'accountHolderName',
        oldValue: account.accountHolderName,
        newValue: accountHolderName,
        apply: (v) => account.accountHolderName = v,
      );
    }
    if (clearNotes) {
      account.recordEdit(
        field: 'notes',
        oldValue: account.notes ?? 'none',
        newValue: 'none',
      );
      account.notes = null;
    } else {
      account.updateField(
        field: 'notes',
        oldValue: account.notes,
        newValue: notes,
        apply: (v) => account.notes = v,
      );
    }
    if (clearAccountNumberLast4) {
      account.recordEdit(
        field: 'accountNumberLast4',
        oldValue: account.accountNumberLast4 ?? 'none',
        newValue: 'none',
      );
      account.accountNumberLast4 = null;
    } else {
      account.updateField(
        field: 'accountNumberLast4',
        oldValue: account.accountNumberLast4,
        newValue: accountNumberLast4,
        apply: (v) => account.accountNumberLast4 = v,
      );
    }
    await update(account);
  }

  void _validate({String? accountNumberLast4}) {
    if (accountNumberLast4 != null &&
        !_last4DigitsPattern.hasMatch(accountNumberLast4)) {
      throw const AppException('Account number must be exactly 4 digits');
    }
  }

  /// Applies a signed delta to an account's running balance — the hook
  /// Milestone 3's transaction repository calls on every add/edit/delete
  /// so an account's `currentBalance` never has to be derived by summing
  /// every transaction on each read. Recorded as an audit entry like any
  /// other field change, so balance history stays traceable.
  ///
  /// Runs inside a Firestore transaction that re-reads the account fresh
  /// rather than trusting [account]'s possibly-stale in-memory snapshot —
  /// this app and the web app share the same accounts, and both can write
  /// to the same account concurrently (mirrors the web app's own
  /// `AccountRepository`/`TransactionRepository`, which already wrap every
  /// balance mutation in `runTransaction` for exactly this reason). Without
  /// this, two deltas computed from the same stale starting balance would
  /// have the second write silently clobber the first's effect instead of
  /// composing with it — see `account_repository_test.dart`'s regression
  /// test for a reproduction of the bug this fixes.
  ///
  /// [account]'s `currentBalance`/`editHistory` are synced to the value
  /// actually persisted (which may differ from a naive `account.
  /// currentBalance + delta` if another writer landed a change in between),
  /// preserving every existing caller's "mutates in place" expectation.
  Future<void> adjustBalance(Account account, double delta) async {
    if (delta == 0) return;
    final docRef = collection.doc(account.id);
    await collection.firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final current = snapshot.data();
      if (current == null) {
        throw const AppException('Account not found');
      }
      final newBalance = current.currentBalance + delta;
      current.recordEdit(
        field: 'currentBalance',
        oldValue: current.currentBalance.toString(),
        newValue: newBalance.toString(),
      );
      current.currentBalance = newBalance;
      transaction.set(docRef, current);
      account.currentBalance = current.currentBalance;
      account.editHistory = current.editHistory;
    });
  }

  /// The "read" half of a composable balance update — for callers that need
  /// to fold a balance mutation into a *larger* atomic write set they
  /// already own (e.g. `TransactionRepository` writing a `Transaction` doc
  /// alongside the balance change, or the loan/EMI payment pipeline writing
  /// an `InstallmentPayment` + `Transaction` + `Account` update together).
  /// Unlike [adjustBalance], this never opens its own `runTransaction` — the
  /// caller does, and passes it in here.
  ///
  /// Split from the "write" half ([applyBalanceDeltaWrite]) so a caller that
  /// must touch *two* accounts in one transaction (e.g. moving a
  /// transaction from one account to another) can read both before writing
  /// either — Firestore transactions require every read to happen before
  /// any write, so composing two read+write pairs back-to-back would throw
  /// at runtime on the second read. Always validates the account exists,
  /// regardless of what delta (if any) the caller goes on to apply —
  /// matching the account-existence check every current caller of this data
  /// already performs before adjusting a balance.
  ///
  /// Throws [NotFoundException] (not the plainer [AppException] `adjustBalance`
  /// throws) so it matches what every current call site of that check
  /// already throws — see [TransactionRepository]'s pre-existing
  /// `NotFoundException('Account not found')` guard, which this composable
  /// primitive is designed to fold into one atomic transaction rather than
  /// replace.
  Future<Account> getForUpdateInTransaction(
    Transaction transaction,
    String accountId,
  ) async {
    final snapshot = await transaction.get(collection.doc(accountId));
    final current = snapshot.data();
    if (current == null) {
      throw const NotFoundException('Account not found');
    }
    return current;
  }

  /// The "write" half of a composable balance update — applies [delta] to
  /// [account] (as returned by [getForUpdateInTransaction]) via the
  /// caller's open [transaction]. A no-op when [delta] is zero, matching
  /// [adjustBalance]'s existing no-write-on-zero-delta behavior exactly.
  /// Synchronous because it only stages a write on the already-open
  /// [transaction]; nothing here performs I/O itself.
  void applyBalanceDeltaWrite(
    Transaction transaction,
    Account account,
    double delta,
  ) {
    if (delta == 0) return;
    final newBalance = account.currentBalance + delta;
    account.recordEdit(
      field: 'currentBalance',
      oldValue: account.currentBalance.toString(),
      newValue: newBalance.toString(),
    );
    account.currentBalance = newBalance;
    transaction.set(collection.doc(account.id), account);
  }

  /// Convenience wrapper combining [getForUpdateInTransaction] and
  /// [applyBalanceDeltaWrite] for the common single-account case, where the
  /// caller has no other account to read first. Reach for the two halves
  /// directly instead when more than one account must be read before any of
  /// them can be written (see [getForUpdateInTransaction]'s doc comment).
  Future<Account> applyBalanceDeltaInTransaction(
    Transaction transaction,
    String accountId,
    double delta,
  ) async {
    final account = await getForUpdateInTransaction(transaction, accountId);
    applyBalanceDeltaWrite(transaction, account, delta);
    return account;
  }

  /// Recomputes `currentBalance` from scratch (opening balance + the sum
  /// of every transaction against this account) and overwrites the cached
  /// value. A safety net against drift if a transaction write is ever
  /// interrupted mid-way — wire this up once Milestone 3's
  /// TransactionRepository exists to supply [transactionsTotal].
  Future<void> reconcileBalance(
    Account account,
    double transactionsTotal,
  ) async {
    final correctBalance = account.openingBalance + transactionsTotal;
    if (correctBalance == account.currentBalance) return;
    account.recordEdit(
      field: 'currentBalance (reconciled)',
      oldValue: account.currentBalance.toString(),
      newValue: correctBalance.toString(),
    );
    account.currentBalance = correctBalance;
    await update(account);
  }
}
