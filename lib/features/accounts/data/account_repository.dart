import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/account.dart';
import '../domain/account_type.dart';

/// Account-specific persistence on top of the generic CRUD/soft-delete
/// repository.
class AccountRepository extends FirestoreCrudRepository<Account> {
  AccountRepository(super.collection);

  Future<Account> createAccount({
    required String name,
    required AccountType type,
    required double openingBalance,
    required int colorValue,
    bool isDefault = false,
  }) async {
    final account = Account(
      id: IdGenerator.generate(),
      name: name,
      type: type,
      openingBalance: openingBalance,
      currentBalance: openingBalance,
      colorValue: colorValue,
      isDefault: isDefault,
      createdAt: DateTime.now(),
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
  }) async {
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
    await update(account);
  }

  /// Applies a signed delta to an account's running balance — the hook
  /// Milestone 3's transaction repository calls on every add/edit/delete
  /// so an account's `currentBalance` never has to be derived by summing
  /// every transaction on each read. Recorded as an audit entry like any
  /// other field change, so balance history stays traceable.
  Future<void> adjustBalance(Account account, double delta) async {
    if (delta == 0) return;
    final newBalance = account.currentBalance + delta;
    account.recordEdit(
      field: 'currentBalance',
      oldValue: account.currentBalance.toString(),
      newValue: newBalance.toString(),
    );
    account.currentBalance = newBalance;
    await update(account);
  }

  /// Recomputes `currentBalance` from scratch (opening balance + the sum
  /// of every transaction against this account) and overwrites the cached
  /// value. A safety net against drift if a transaction write is ever
  /// interrupted mid-way — wire this up once Milestone 3's
  /// TransactionRepository exists to supply [transactionsTotal].
  Future<void> reconcileBalance(Account account, double transactionsTotal) async {
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
