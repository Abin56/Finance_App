import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves "My Spending" respects `excludeFromCalculations`/`accountingMonth`
/// exactly like Budgets/Cash Flow/Dashboard do, since it reduces over the
/// same shared `calculableTransactionsProvider` choke point.
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

  Future<String> seedAccount() async {
    final account = await container.read(accountRepositoryProvider).createAccount(
          name: 'Wallet',
          type: AccountType.cash,
          openingBalance: 10000,
          colorValue: 0xFF000000,
        );
    return account.id;
  }

  group('myThisMonthExpenseProvider', () {
    test('excludes a transaction marked excludeFromCalculations', () async {
      final now = DateTime.now();
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 600,
        dateTime: now,
        accountId: accountId,
        categoryId: 'groceries',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 250,
        dateTime: now,
        accountId: accountId,
        categoryId: 'reimbursable',
        excludeFromCalculations: true,
      );

      await container.read(transactionsStreamProvider.future);

      expect(container.read(myThisMonthExpenseProvider), 600);
    });

    test('a transaction reassigned to next month via accountingMonth is excluded from this month\'s total', () async {
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 900,
        dateTime: now,
        accountId: accountId,
        categoryId: 'advance-payment',
        accountingMonth: nextMonth,
      );

      await container.read(transactionsStreamProvider.future);

      expect(container.read(myThisMonthExpenseProvider), 0);
    });
  });

  group('myTodayExpenseProvider', () {
    test('is unaffected by accountingMonth — stays on the real date', () async {
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 150,
        dateTime: now,
        accountId: accountId,
        categoryId: 'lunch',
        accountingMonth: nextMonth,
      );

      await container.read(transactionsStreamProvider.future);

      expect(container.read(myTodayExpenseProvider), 150, reason: 'daily granularity always uses the real date');
    });
  });

  group('myExpenseBreakdownForTransactionsProvider', () {
    // Reports (reports_screen.dart) is the sole caller and is responsible
    // for pre-filtering via calculableTransactionsProvider + reportDateFor
    // before calling this provider — so these tests exercise exactly that:
    // Reports' own exclusion/accounting-month filter, then the My-Share
    // math on top of it. Regression coverage for the bug where this
    // provider used to filter independently (raw transactionsStreamProvider
    // + raw dateTime), silently disagreeing with the rest of the screen.
    test('an excluded transaction never reaches the breakdown once Reports pre-filters it', () async {
      final now = DateTime.now();
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 400,
        dateTime: now,
        accountId: accountId,
        categoryId: 'groceries',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 999,
        dateTime: now,
        accountId: accountId,
        categoryId: 'reimbursable',
        excludeFromCalculations: true,
      );

      await container.read(transactionsStreamProvider.future);
      final calculable = container.read(calculableTransactionsProvider);

      final breakdown = container.read(myExpenseBreakdownForTransactionsProvider(calculable));
      expect(breakdown.total, 400, reason: 'excludeFromCalculations must never contribute to My Expense');
    });

    test('an accounting-month-reassigned transaction lands in the period Reports actually filtered for', () async {
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 700,
        dateTime: now,
        accountId: accountId,
        categoryId: 'advance-payment',
        accountingMonth: nextMonth,
      );

      await container.read(transactionsStreamProvider.future);
      final calculable = container.read(calculableTransactionsProvider);

      // Reports filters via ReportsPeriod.thisMonth.reportDateFor before
      // calling this provider — the reassigned transaction must NOT appear
      // in "this month"'s breakdown...
      final thisMonthFiltered =
          calculable.where((t) => t.effectiveMonth.year == now.year && t.effectiveMonth.month == now.month).toList();
      expect(container.read(myExpenseBreakdownForTransactionsProvider(thisMonthFiltered)).total, 0);

      // ...but must appear once Reports is viewing the month it was
      // reassigned to.
      final nextMonthFiltered = calculable
          .where((t) => t.effectiveMonth.year == nextMonth.year && t.effectiveMonth.month == nextMonth.month)
          .toList();
      expect(container.read(myExpenseBreakdownForTransactionsProvider(nextMonthFiltered)).total, 700);
    });

    test('splits personal vs split-expense share correctly given a pre-filtered list', () async {
      final now = DateTime.now();
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      // Plain (non-split) expense — counts as "personal".
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: now,
        accountId: accountId,
        categoryId: 'groceries',
      );

      await container.read(transactionsStreamProvider.future);
      final calculable = container.read(calculableTransactionsProvider);

      final breakdown = container.read(myExpenseBreakdownForTransactionsProvider(calculable));
      expect(breakdown.personal, 300);
      expect(breakdown.split, 0);
      expect(breakdown.total, 300);
    });
  });
}
