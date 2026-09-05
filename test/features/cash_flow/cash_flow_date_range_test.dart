import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/cash_flow/domain/cash_flow_period.dart';
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

/// Feature 1 (Cash Flow date-range filter) and Feature 2 ("My Expenses")
/// provider tests. Both features build on `calculableTransactionsProvider`
/// and `Expense.myShare`, so these tests seed fixtures through the real
/// repositories (same path the app takes), same convention as
/// `cash_flow_providers_test.dart`.
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

  Future<String> createAccount(ProviderContainer container) async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: 'Wallet',
      type: AccountType.cash,
      openingBalance: 10000,
      colorValue: 0xFF000000,
    );
    return account.id;
  }

  group('Feature 1 — cashFlowDateRangeProvider / cashFlowForRangeProvider', () {
    test('a custom range includes transactions inside it', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 8, 15),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
      );

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyOut, 500);
    });

    test('excludes a transaction dated before the selected range', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 7, 31),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
      );

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyOut, 0, reason: 'dated before the range — must be excluded');
    });

    test('excludes a transaction dated after the selected range', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 1),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
      );

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyOut, 0, reason: 'dated after the range — must be excluded');
    });

    test('the start date is inclusive', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 8, 1),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
      );

      expect(container.read(cashFlowForRangeProvider).moneyOut, 500);
    });

    test('the end date is inclusive', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 8, 31),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
      );

      expect(container.read(cashFlowForRangeProvider).moneyOut, 500);
    });

    test('a custom multi-month range spans August through September', () async {
      // The range's own endpoints are month-aligned (1st of each month) —
      // matching how Cash Flow buckets by `effectiveMonth`, which truncates
      // to the first of a month, same rule `cashFlowThisMonthProvider`
      // already applies for a single calendar month.
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 200,
        dateTime: DateTime(2026, 8, 20),
        accountId: accountId,
        categoryId: 'food',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 9, 5),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 9, 30)),
      );

      expect(container.read(cashFlowForRangeProvider).moneyOut, 500);
    });

    test('changing the selected range changes the provider output', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 100,
        dateTime: DateTime(2026, 8, 10),
        accountId: accountId,
        categoryId: 'food',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 250,
        dateTime: DateTime(2026, 9, 10),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
      );
      expect(container.read(cashFlowForRangeProvider).moneyOut, 100);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );
      expect(container.read(cashFlowForRangeProvider).moneyOut, 250, reason: 'switching range must recompute, not cache the old one');
    });

    test('preset "This Month" resolves to the current calendar month', () {
      final now = DateTime.now();
      final period = const CashFlowPeriod.preset(CashFlowPreset.thisMonth);
      final range = period.rangeFor(now);
      expect(range.start.month, now.month);
      expect(range.end.month, now.month);
    });
  });

  group('Feature 2 — myExpensesForRangeProvider', () {
    test('a plain ₹500 personal expense counts in full', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 10),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 500);
      expect(breakdown.personal, 500);
      expect(breakdown.split, 0);
    });

    test('₹300 split equally among 3 (including me) counts only my ₹100 share', () async {
      final accountId = await createAccount(container);
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 9, 10),
        categoryId: 'food',
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 100, reason: 'only my ₹100 share of the ₹300 dinner, not the full ₹300');
      expect(breakdown.split, 100);
      expect(breakdown.personal, 0);
    });

    test('₹900 split equally among 3 counts only my ₹300 share', () async {
      final accountId = await createAccount(container);
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 900,
        date: DateTime(2026, 9, 10),
        categoryId: 'food',
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      expect(container.read(myExpensesForRangeProvider).total, 300);
    });

    test('a custom split uses my explicit assigned amount, not an equal share', () async {
      final accountId = await createAccount(container);
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Groceries run',
        totalAmount: 1000,
        date: DateTime(2026, 9, 10),
        categoryId: 'food',
        accountId: accountId,
        splitType: SplitType.custom,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true, value: 400),
          ExpenseParticipantInput(name: 'Person A', value: 300),
          ExpenseParticipantInput(name: 'Person B', value: 300),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      expect(container.read(myExpensesForRangeProvider).total, 400, reason: 'my explicit ₹400, not an equal ₹333 share');
    });

    test('other participants\' shares are excluded from My Expenses', () async {
      final accountId = await createAccount(container);
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 900,
        date: DateTime(2026, 9, 10),
        categoryId: 'food',
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      expect(container.read(myExpensesForRangeProvider).total, 300, reason: 'the other ₹600 must never appear as my expense');
    });

    test('a shared expense is not double-counted across personal + split', () async {
      final accountId = await createAccount(container);
      final expenses = container.read(expenseRepositoryProvider);
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 9, 10),
        categoryId: 'food',
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );
      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, breakdown.personal + breakdown.split);
      expect(breakdown.total, 100);
    });

    test('full scenario: personal + split share included, EMI/bills excluded', () async {
      final accountId = await createAccount(container);
      final expenses = container.read(expenseRepositoryProvider);

      // 1. Personal food expense = ₹500 (a plain Transaction, no Expense
      // doc — matches how AddExpenseScreen creates an ordinary expense with
      // no participants).
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 5),
        accountId: accountId,
        categoryId: 'food',
      );

      // 2. Dinner = ₹300 shared among 3 → my share ₹100
      await expenses.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 9, 12),
        categoryId: 'food',
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Person A'),
          ExpenseParticipantInput(name: 'Person B'),
        ],
      );

      // 3/4. EMI and electricity bill never post a Transaction of type
      // expense — nothing to seed for "must not increase My Expenses"; the
      // absence of any EMI/Bill transaction is the assertion itself.

      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      final breakdown = container.read(myExpensesForRangeProvider);
      expect(breakdown.total, 600, reason: '₹500 personal + ₹100 my share of dinner = ₹600');
    });

    test('a transaction marked excludeFromCalculations does not count toward My Expenses', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 800,
        dateTime: DateTime(2026, 9, 10),
        accountId: accountId,
        categoryId: 'reimbursable',
        excludeFromCalculations: true,
      );
      await container.read(transactionsStreamProvider.future);

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );

      expect(container.read(myExpensesForRangeProvider).total, 0);
    });

    test('a transaction reassigned to a different accountingMonth is bucketed by that month for a whole-month preset', () async {
      // Only a month-granular period (a whole-month preset) buckets by
      // `effectiveMonth`/`accountingMonth` — a `custom` range is day-precision
      // and must bucket by the transaction's real `dateTime` instead (see
      // `CashFlowPeriod.bucketDateFor`), same rule Money In/Out already
      // follows. Reassignment only matters for `lastMonth`, since `thisMonth`
      // always resolves against the real current date, not the fixed
      // September 2026 fixture date used here.
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 700,
        dateTime: DateTime(2026, 9, 25),
        accountId: accountId,
        categoryId: 'food',
        accountingMonth: DateTime(2026, 10, 1),
      );
      await container.read(transactionsStreamProvider.future);

      // A custom range covering the same window buckets by real `dateTime`
      // (September 25th) regardless of the accountingMonth reassignment.
      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );
      expect(
        container.read(myExpensesForRangeProvider).total,
        700,
        reason: 'a custom range is day-precision — it buckets by the real transaction date, not accountingMonth',
      );

      container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
        DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      );
      expect(container.read(myExpensesForRangeProvider).total, 0, reason: 'dateTime is in September, outside this October custom range');
    });

    test('a transaction reassigned to a different accountingMonth is bucketed by that month for a whole-month preset', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 700,
        dateTime: now,
        accountId: accountId,
        categoryId: 'food',
        accountingMonth: nextMonth,
      );
      await container.read(transactionsStreamProvider.future);

      // `thisMonth` is a whole-month, month-granular preset — it buckets by
      // `effectiveMonth`, which follows the accountingMonth reassignment.
      container.read(cashFlowDateRangeProvider.notifier).state = const CashFlowPeriod.preset(CashFlowPreset.thisMonth);
      expect(container.read(myExpensesForRangeProvider).total, 0, reason: 'reassigned to next month — must not count in this month');
    });
  });
}
