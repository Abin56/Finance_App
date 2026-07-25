import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/dashboard/domain/dashboard_widget_type.dart';
import 'package:finance_app/core/dashboard/domain/date_range_strategy.dart';
import 'package:finance_app/core/dashboard/domain/financial_view_module.dart';
import 'package:finance_app/core/dashboard/domain/widget_configuration.dart';
import 'package:finance_app/core/dashboard/presentation/providers/expense_calculator_provider.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/expense/data/expense_repository.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for the "Spent This Pay Period" bug: `_myExpenses`/
/// `_sharedExpenses` used to read `expensesStreamProvider` raw and filter by
/// `Expense.date`, silently ignoring `excludeFromCalculations` and never
/// joining through `Expense.myShare`/`othersShare` for split expenses. Now
/// routed through `calculableTransactionsProvider` +
/// `myExpenseBreakdownForTransactionsProvider`/
/// `othersShareForTransactionsProvider`, the same join Reports uses.
///
/// Also covers the salary-cycle strategy's date bucketing: a day-granular
/// range (17th→17th) correctly ignores `accountingMonth` and stays on the
/// transaction's real date, mirroring `ReportsPeriodX.reportDateFor`'s
/// month-granular-only rule for Accounting Month.
void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
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

  WidgetConfiguration payPeriodConfig({int anchorDay = 17}) {
    return WidgetConfiguration(
      id: 'test-financial-view',
      type: DashboardWidgetType.financialView,
      title: 'Spent This Pay Period',
      dateStrategy: SalaryCycleFull(anchorDay: anchorDay),
      financialViewModule: FinancialViewModule.combinedExpenses,
    );
  }

  test('excludes a plain expense transaction marked excludeFromCalculations', () async {
    final accountId = await seedAccount();
    final expenses = container.read(expenseRepositoryProvider);
    final now = DateTime.now();

    await expenses.createExpense(
      description: 'Groceries',
      totalAmount: 600,
      date: now,
      categoryId: 'food',
      accountId: accountId,
      splitType: SplitType.none,
      participantInputs: const [ExpenseParticipantInput(name: 'Me')],
    );
    await expenses.createExpense(
      description: 'Reimbursable',
      totalAmount: 999,
      date: now,
      categoryId: 'work',
      accountId: accountId,
      splitType: SplitType.none,
      participantInputs: const [ExpenseParticipantInput(name: 'Me')],
      excludeFromCalculations: true,
    );

    await container.read(transactionsStreamProvider.future);
    await container.read(expensesStreamProvider.future);

    final result = container.read(financialViewResultProvider(payPeriodConfig()));
    expect(result.amount, 600, reason: 'excludeFromCalculations must never contribute to Spent This Pay Period');
  });

  test(
    'a pay-period (day-granular) range ignores accountingMonth and stays on the real transaction date, '
    'exactly like Reports does for today/week/year',
    () async {
      final accountId = await seedAccount();
      final expenses = container.read(expenseRepositoryProvider);
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 2);

      await expenses.createExpense(
        description: 'Advance payment',
        totalAmount: 900,
        date: now,
        categoryId: 'misc',
        accountId: accountId,
        splitType: SplitType.none,
        participantInputs: const [ExpenseParticipantInput(name: 'Me')],
        accountingMonth: nextMonth,
      );

      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      final result = container.read(financialViewResultProvider(payPeriodConfig()));
      expect(
        result.amount,
        900,
        reason: 'accountingMonth only ever encodes a month, so it has no well-defined day inside a 17th→17th '
            'salary-cycle window — the transaction must stay bucketed by its real date, not silently disappear',
      );
    },
  );

  test('a split expense only counts my own share toward Spent This Pay Period, not the total', () async {
    final accountId = await seedAccount();
    final expenses = container.read(expenseRepositoryProvider);
    final now = DateTime.now();

    await expenses.createExpense(
      description: 'Dinner with Rahul',
      totalAmount: 1000,
      date: now,
      categoryId: 'food',
      accountId: accountId,
      splitType: SplitType.equal,
      participantInputs: const [
        ExpenseParticipantInput(name: 'Me', isMe: true),
        ExpenseParticipantInput(name: 'Rahul'),
      ],
    );

    await container.read(transactionsStreamProvider.future);
    await container.read(expensesStreamProvider.future);

    final myExpensesResult = container.read(
      financialViewResultProvider(
        payPeriodConfig().copyWith(financialViewModule: FinancialViewModule.myExpenses),
      ),
    );
    expect(myExpensesResult.amount, 500, reason: 'only my own share of a split expense is money I spent');

    final sharedResult = container.read(
      financialViewResultProvider(
        payPeriodConfig().copyWith(financialViewModule: FinancialViewModule.sharedExpenses),
      ),
    );
    expect(sharedResult.amount, 500, reason: "the other participant's share is money owed, not money I spent");
  });

  test('an excluded split expense contributes neither my share nor the shared share', () async {
    final accountId = await seedAccount();
    final expenses = container.read(expenseRepositoryProvider);
    final now = DateTime.now();

    await expenses.createExpense(
      description: 'Reimbursed trip',
      totalAmount: 2000,
      date: now,
      categoryId: 'travel',
      accountId: accountId,
      splitType: SplitType.equal,
      excludeFromCalculations: true,
      participantInputs: const [
        ExpenseParticipantInput(name: 'Me', isMe: true),
        ExpenseParticipantInput(name: 'Priya'),
      ],
    );

    await container.read(transactionsStreamProvider.future);
    await container.read(expensesStreamProvider.future);

    final result = container.read(financialViewResultProvider(payPeriodConfig()));
    expect(result.amount, 0, reason: 'excludeFromCalculations must zero out both my share and the shared share');
  });

  test(
    'a "This Month" financial view widget (month-granular) DOES follow accountingMonth, unlike the pay-period one',
    () async {
      final accountId = await seedAccount();
      final expenses = container.read(expenseRepositoryProvider);
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);

      await expenses.createExpense(
        description: 'Advance payment',
        totalAmount: 900,
        date: now,
        categoryId: 'misc',
        accountId: accountId,
        splitType: SplitType.none,
        participantInputs: const [ExpenseParticipantInput(name: 'Me')],
        accountingMonth: nextMonth,
      );

      await container.read(transactionsStreamProvider.future);
      await container.read(expensesStreamProvider.future);

      final thisMonthConfig = WidgetConfiguration(
        id: 'test-this-month',
        type: DashboardWidgetType.financialView,
        title: 'This Month',
        dateStrategy: const ReportsPeriodStrategy(ReportsPeriod.thisMonth),
        financialViewModule: FinancialViewModule.combinedExpenses,
      );

      final result = container.read(financialViewResultProvider(thisMonthConfig));
      expect(
        result.amount,
        0,
        reason: 'a calendar-month-granular widget must respect accountingMonth and move the expense out, '
            'exactly like Reports "This Month" does',
      );
    },
  );
}
