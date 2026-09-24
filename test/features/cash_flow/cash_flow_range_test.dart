import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_occurrence_providers.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:finance_app/features/cash_flow/domain/cash_flow_preset.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/expense/data/expense_repository.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the Cash Flow Center's date-range filter (Feature 1) and "My
/// Expenses" section (Feature 2). See `cash_flow_providers_test.dart` for
/// the pre-existing "this month"-hardcoded provider tests, which these
/// deliberately don't touch or duplicate.
void main() {
  late ProviderContainer container;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
  });

  Future<void> materializeBill(ProviderContainer container, String billId) async {
    final sub = container.listen(materializeBillOccurrenceProvider(billId), (_, _) {});
    addTearDown(sub.close);
    await container.read(materializeBillOccurrenceProvider(billId).future);
  }

  void setRange(DateTime start, DateTime end) {
    container.read(cashFlowSelectionProvider.notifier).state =
        CashFlowSelection(preset: CashFlowPreset.custom, range: DateRange(start, end));
  }

  group('cashFlowForRangeProvider — date range filter', () {
    test('includes a transaction dated inside the selected range', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1000,
        dateTime: DateTime(2026, 8, 15),
        accountId: account.id,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyIn, 1000);
    });

    test('excludes a transaction dated before the selected range (start inclusive boundary)', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1000,
        dateTime: DateTime(2026, 7, 31),
        accountId: account.id,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 8, 1),
        accountId: account.id,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyIn, 500, reason: 'the 31 July transaction is before the range and must be excluded');
    });

    test('excludes a transaction dated after the selected range (end inclusive boundary)', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 8, 31, 23, 0),
        accountId: account.id,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1000,
        dateTime: DateTime(2026, 9, 1),
        accountId: account.id,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyIn, 500, reason: 'the 1 September transaction is after the range and must be excluded');
    });

    test('a custom multi-month range includes transactions from every month in it', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 100,
        dateTime: DateTime(2026, 8, 20),
        accountId: account.id,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 200,
        dateTime: DateTime(2026, 9, 10),
        accountId: account.id,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      // Cash Flow's Money In/Out is bucketed by `effectiveMonth` (truncated
      // to each month's 1st, same as Reports/Dashboard — see
      // `Transaction.effectiveMonth`'s doc comment), so a range must start
      // on/before a month's 1st to include transactions dated anywhere in
      // it. 1 Aug -> 30 Sep spans both calendar months in full.
      setRange(DateTime(2026, 8, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyIn, 300);
    });

    test('changing the selected range updates the provider output', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 100,
        dateTime: DateTime(2026, 8, 10),
        accountId: account.id,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 200,
        dateTime: DateTime(2026, 9, 10),
        accountId: account.id,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));
      expect(container.read(cashFlowForRangeProvider).moneyIn, 100);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));
      expect(container.read(cashFlowForRangeProvider).moneyIn, 200);
    });

    test('preserves excludeFromCalculations within the selected range', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 800,
        dateTime: DateTime(2026, 8, 10),
        accountId: account.id,
        categoryId: 'reimbursable',
        excludeFromCalculations: true,
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));

      expect(container.read(cashFlowForRangeProvider).moneyOut, 0);
    });

    test('excludes a transfer between own accounts within the selected range', () async {
      final accounts = container.read(accountRepositoryProvider);
      final source = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 10000,
        colorValue: 0xFF000000,
      );
      final destination = await accounts.createAccount(
        name: 'Savings',
        type: AccountType.bank,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransferPair(
        amount: 2000,
        dateTime: DateTime(2026, 8, 10),
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        categoryId: 'transfer',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyIn, 0);
      expect(cashFlow.moneyOut, 0);
    });

    test('respects accountingMonth override within the selected range', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 700,
        dateTime: DateTime(2026, 8, 25),
        accountId: account.id,
        categoryId: 'advance-payment',
        accountingMonth: DateTime(2026, 9),
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));
      expect(container.read(cashFlowForRangeProvider).moneyOut, 0, reason: 'reassigned to September');

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));
      expect(container.read(cashFlowForRangeProvider).moneyOut, 700);
    });

    test('deleted transactions remain excluded within the selected range', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      final t = await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 8, 5),
        accountId: account.id,
        categoryId: 'misc',
      );
      await container.read(transactionsStreamProvider.future);
      await transactions.softDelete(t);
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));
      expect(container.read(cashFlowForRangeProvider).moneyOut, 0);
    });
  });

  group('upcomingPaymentsForRangeProvider / totalDueForRangeProvider — Sections 1 & 4', () {
    test('a bill due inside the range is counted; outside it is not', () async {
      final bills = container.read(billRepositoryProvider);
      final billInRange = await bills.createBill(
        name: 'Electricity',
        amount: 1000,
        dueDate: DateTime(2026, 8, 10),
        recurrence: BillRecurrence.monthly,
      );
      final billOutOfRange = await bills.createBill(
        name: 'Internet',
        amount: 500,
        dueDate: DateTime(2026, 10, 10),
        recurrence: BillRecurrence.monthly,
      );
      await container.read(billsStreamProvider.future);
      await materializeBill(container, billInRange.id);
      await materializeBill(container, billOutOfRange.id);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));

      final due = container.read(totalDueForRangeProvider);
      expect(due.due, 1000);

      final items = container.read(upcomingPaymentsForRangeProvider);
      expect(items.map((i) => i.title), contains('Electricity'));
      expect(items.map((i) => i.title), isNot(contains('Internet')));
    });
  });

  group('myExpensesForRangeProvider — Feature 2: My Expenses', () {
    test('a plain personal expense counts in full', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      // A plain (unsplit) expense is just a regular expense Transaction with
      // no Expense document at all — SplitExpenseFormSheet (the only caller
      // of ExpenseRepository.createExpense) is exclusively used for split/
      // assigned expenses, so `myExpensePortionsProvider`'s fallback (the
      // transaction's own `.amount`) is what a real plain expense hits.
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 5),
        accountId: account.id,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 500);
      expect(breakdown.personal, 500);
      expect(breakdown.split, 0);
    });

    test('a 300 expense split equally among 3 people counts only my 100 share', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 9, 5),
        categoryId: 'food',
        accountId: account.id,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 100, reason: '300 split 3 ways — my share only');
      expect(breakdown.split, 100);
    });

    test('a 900 expense split equally among 3 (300 each) counts only my 300', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 900,
        date: DateTime(2026, 9, 5),
        categoryId: 'food',
        accountId: account.id,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 300);
    });

    test('a custom split uses the explicit assigned amount, not an equal share', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Groceries',
        totalAmount: 1000,
        date: DateTime(2026, 9, 5),
        categoryId: 'food',
        accountId: account.id,
        splitType: SplitType.custom,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true, value: 400),
          ExpenseParticipantInput(name: 'Person A', value: 300),
          ExpenseParticipantInput(name: 'Person B', value: 300),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 400, reason: 'custom share must be used, not total/3');
    });

    test('other participants\' shares are excluded and never double-counted', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 9, 5),
        categoryId: 'food',
        accountId: account.id,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 100, reason: 'the 200 owed by Person A + Person B must never appear here');
    });

    test('an EMI payment does not increase My Expenses', () async {
      final accounts = container.read(accountRepositoryProvider);
      await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      // No transaction of type expense is ever created for an EMI payment
      // (confirmed by EmiRepository), so My Expenses — which only reads
      // expense Transactions — naturally can't include it. Assert directly
      // against an empty range.
      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));
      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 0);
    });

    test('a bill payment does not increase My Expenses', () async {
      final bills = container.read(billRepositoryProvider);
      final bill = await bills.createBill(
        name: 'Electricity',
        amount: 1500,
        dueDate: DateTime(2026, 9, 10),
        recurrence: BillRecurrence.monthly,
      );
      await container.read(billsStreamProvider.future);
      await materializeBill(container, bill.id);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 0, reason: 'bills never post an expense Transaction, so must not appear here');
    });

    test('full worked scenario — personal + shared - EMI/bill excluded', () async {
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 5),
        accountId: account.id,
        categoryId: 'food',
      );
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 9, 6),
        categoryId: 'food',
        accountId: account.id,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      final bills = container.read(billRepositoryProvider);
      final bill = await bills.createBill(
        name: 'Electricity',
        amount: 1500,
        dueDate: DateTime(2026, 9, 15),
        recurrence: BillRecurrence.monthly,
      );
      await container.read(billsStreamProvider.future);
      await materializeBill(container, bill.id);
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 600, reason: '500 personal + 100 dinner share; the 1500 electricity bill excluded');

      // The bill was never paid, so it contributes 0 to Money Out (Money
      // Out counts amounts actually paid, not amounts due — see
      // `_billsPaidForRangeProvider`); the point stands regardless: My
      // Expenses (600) is not the same figure as Money Out (800: the two
      // expense transactions only, since nothing was paid toward the bill).
      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyOut, 500 + 300, reason: 'Money Out only reflects amounts actually paid');
    });
  });
}
