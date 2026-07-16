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
      accountNumberLast4: clearAccountNumberLast4 ? null : accountNumberLast4 ?? account.accountNumberLast4,
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
      account.recordEdit(field: 'bankId', oldValue: account.bankId ?? 'none', newValue: 'none');
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
      account.recordEdit(field: 'notes', oldValue: account.notes ?? 'none', newValue: 'none');
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
    if (accountNumberLast4 != null && !_last4DigitsPattern.hasMatch(accountNumberLast4)) {
      throw const AppException('Account number must be exactly 4 digits');
    }
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
