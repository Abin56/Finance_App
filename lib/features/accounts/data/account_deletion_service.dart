import '../../bills/data/bill_deletion_service.dart';
import '../../bills/data/bill_occurrence_repository.dart';
import '../../bills/data/bill_repository.dart';
import '../../bills/data/payment_repository.dart';
import '../../bills/domain/bill.dart';
import '../../expense/data/expense_repository.dart';
import '../../expense/domain/expense.dart';
import '../../people/data/ledger_repository.dart';
import '../../people/data/person_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../../../core/payment_schedule/data/installment_repository.dart';
import '../../../core/payment_schedule/data/payment_schedule_repository.dart';
import 'account_repository.dart';

/// Every repository the account permanent-delete cascade needs, gathered in
/// one place so `permanentlyDeleteAccountHistory` doesn't take a dozen
/// positional/named parameters. Not methods on [AccountRepository] itself —
/// [TransactionRepository] already depends on [AccountRepository] (see
/// `transactionRepositoryProvider`), so the reverse dependency would be
/// circular. Built by `accountDeletionRepositoriesProvider`.
class AccountDeletionRepositories {
  const AccountDeletionRepositories({
    required this.accountRepository,
    required this.transactionRepository,
    required this.billRepository,
    required this.expenseRepository,
    required this.personRepository,
    required this.ledgerRepositoryFor,
    required this.paymentScheduleRepository,
    required this.installmentRepositoryFor,
    required this.billOccurrenceRepositoryFor,
    required this.paymentRepositoryFor,
  });

  final AccountRepository accountRepository;
  final TransactionRepository transactionRepository;
  final BillRepository billRepository;
  final ExpenseRepository expenseRepository;
  final PersonRepository personRepository;
  final LedgerRepository Function(String personId) ledgerRepositoryFor;
  final PaymentScheduleRepository paymentScheduleRepository;
  final InstallmentRepository Function(String scheduleId) installmentRepositoryFor;
  final BillOccurrenceRepository Function(String billId) billOccurrenceRepositoryFor;
  final PaymentRepository Function(String billId) paymentRepositoryFor;
}

/// What permanently deleting an account will destroy — shown by the
/// type-to-confirm warning dialog before it runs.
class AccountDeletionImpact {
  const AccountDeletionImpact({
    required this.transactionCount,
    required this.transferSiblingCount,
    required this.expenseCount,
    required this.affectedPersonCount,
    required this.billCount,
  });

  /// Active + trashed transactions with `accountId` set to this account.
  final int transactionCount;

  /// Transfer legs on *other* (surviving) accounts that will also be
  /// removed, since their sibling leg lives on the account being deleted.
  final int transferSiblingCount;

  /// Split/assigned expenses funded from this account.
  final int expenseCount;

  /// Distinct people whose ledger balance will be recalculated.
  final int affectedPersonCount;

  /// Bills paying from this account.
  final int billCount;
}

class _AccountDeletionPlan {
  const _AccountDeletionPlan({
    required this.transactions,
    required this.foreignSiblings,
    required this.expenses,
    required this.bills,
    required this.affectedPersonCount,
  });

  final List<Transaction> transactions;
  final List<Transaction> foreignSiblings;
  final List<Expense> expenses;
  final List<Bill> bills;
  final int affectedPersonCount;
}

Future<_AccountDeletionPlan> _gatherAccountDeletionPlan(
  String accountId,
  AccountDeletionRepositories repos,
) async {
  final transactions = await repos.transactionRepository.getAllForAccountIncludingTrash(accountId);
  final transactionIds = transactions.map((t) => t.id).toSet();

  // Any transfer leg on a *surviving* account whose sibling is being deleted here needs its own
  // balance reversed (the account being deleted needs no such reversal — it's being destroyed
  // wholesale). Deduped by id in case two of this account's own legs somehow point at the same
  // sibling (never happens in practice, but cheap to guard).
  final foreignSiblingsById = <String, Transaction>{};
  for (final transaction in transactions) {
    if (transaction.transferId == null) continue;
    final sibling = await repos.transactionRepository.findTransferSibling(transaction);
    if (sibling != null && sibling.accountId != accountId && !transactionIds.contains(sibling.id)) {
      foreignSiblingsById[sibling.id] = sibling;
    }
  }

  final allExpenses = [...await repos.expenseRepository.getAll(), ...await repos.expenseRepository.getTrash()];
  final expenses = allExpenses.where((e) => transactionIds.contains(e.transactionId)).toList();

  final affectedPersonIds = <String>{};
  for (final expense in expenses) {
    for (final participant in expense.participants) {
      if (participant.personId != null) affectedPersonIds.add(participant.personId!);
    }
  }

  final allBills = [...await repos.billRepository.getAll(), ...await repos.billRepository.getTrash()];
  final bills = allBills.where((b) => b.accountId == accountId).toList();

  return _AccountDeletionPlan(
    transactions: transactions,
    foreignSiblings: foreignSiblingsById.values.toList(),
    expenses: expenses,
    bills: bills,
    affectedPersonCount: affectedPersonIds.length,
  );
}

/// Read-only preview for the type-to-confirm delete dialog — runs the exact
/// same gather logic [permanentlyDeleteAccountHistory] executes against, so
/// the counts shown to the user are exactly what will be destroyed.
Future<AccountDeletionImpact> previewAccountDeletionImpact(
  String accountId,
  AccountDeletionRepositories repos,
) async {
  final plan = await _gatherAccountDeletionPlan(accountId, repos);
  return AccountDeletionImpact(
    transactionCount: plan.transactions.length,
    transferSiblingCount: plan.foreignSiblings.length,
    expenseCount: plan.expenses.length,
    affectedPersonCount: plan.affectedPersonCount,
    billCount: plan.bills.length,
  );
}

/// Deletes everything *linked to* the account (transactions, transfer
/// siblings, expenses, ledger entries, bills) but NOT the account document
/// itself — callers delete their own root document(s) afterward (a plain
/// account delete vs. a credit-card delete, which also owns a
/// `CreditCardProfile`; see `credit_card_deletion_service.dart`). Every step
/// is a genuine permanent delete, never soft-delete — only ever reached
/// after the destructive-delete dialog's type-to-confirm gate.
Future<void> permanentlyDeleteAccountHistory(String accountId, AccountDeletionRepositories repos) async {
  final plan = await _gatherAccountDeletionPlan(accountId, repos);

  // 1. Split/assigned expenses funded from this account — also permanently
  //    deletes each expense's own linked Transaction, so step 2 below must
  //    skip those transactions to avoid a redundant (harmless, but wasteful)
  //    second delete attempt.
  final expenseTransactionIds = plan.expenses.map((e) => e.transactionId).toSet();
  for (final expense in plan.expenses) {
    await repos.expenseRepository.permanentlyDeleteExpense(expense);
  }

  // 2. The account's own remaining transactions — no balance reversal
  //    needed, the account is being destroyed wholesale.
  for (final transaction in plan.transactions) {
    if (expenseTransactionIds.contains(transaction.id)) continue;
    await repos.transactionRepository.permanentlyDeleteTransaction(transaction);
  }

  // 3. Transfer legs on *surviving* accounts: reverse that account's balance,
  //    then delete the sibling transaction itself.
  for (final sibling in plan.foreignSiblings) {
    final otherAccount = await repos.accountRepository.getByKey(sibling.accountId);
    if (otherAccount != null) {
      await repos.accountRepository.adjustBalance(otherAccount, -sibling.balanceEffect);
    }
    await repos.transactionRepository.permanentlyDeleteTransaction(sibling);
  }

  // 4. Bills paying from this account.
  for (final bill in plan.bills) {
    await permanentlyDeleteBillAndHistory(
      bill,
      billRepository: repos.billRepository,
      occurrenceRepository: repos.billOccurrenceRepositoryFor(bill.id),
      paymentRepository: repos.paymentRepositoryFor(bill.id),
    );
  }
}
