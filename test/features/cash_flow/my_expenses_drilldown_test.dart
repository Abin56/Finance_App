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

/// My Expenses drill-down: [myExpenseLinesForRangeProvider],
/// [myExpensesByCategoryProvider] and [myExpensesForCategoryProvider] must
/// all reconcile with [myExpensesForRangeProvider] and with each other,
/// since they're all folds/filters over the same line list.
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

  void setRange(DateTime start, DateTime end) {
    container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(DateRange(start, end));
  }

  test('category totals reconcile with the My Expenses total', () async {
    final accountId = await createAccount(container);
    final transactions = container.read(transactionRepositoryProvider);
    final expenses = container.read(expenseRepositoryProvider);

    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 500,
      dateTime: DateTime(2026, 9, 3),
      accountId: accountId,
      categoryId: 'food',
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 300,
      dateTime: DateTime(2026, 9, 4),
      accountId: accountId,
      categoryId: 'shopping',
    );
    await expenses.createExpense(
      description: 'Shared dinner',
      totalAmount: 300,
      date: DateTime(2026, 9, 7),
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

    setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 10));

    final total = container.read(myExpensesForRangeProvider).total;
    final categories = container.read(myExpensesByCategoryProvider);
    final categorySum = categories.fold(0.0, (sum, c) => sum + c.amount);

    expect(total, 900, reason: '500 food + 300 shopping + 100 my share of dinner');
    expect(categorySum, total, reason: 'category totals must reconcile with the overall total');

    final food = categories.firstWhere((c) => c.categoryId == 'food');
    expect(food.amount, 600, reason: '500 personal + 100 my share of the shared dinner');
    final shopping = categories.firstWhere((c) => c.categoryId == 'shopping');
    expect(shopping.amount, 300);
  });

  test('category detail lines total matches the category total', () async {
    final accountId = await createAccount(container);
    final transactions = container.read(transactionRepositoryProvider);
    final expenses = container.read(expenseRepositoryProvider);

    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 500,
      dateTime: DateTime(2026, 9, 1),
      accountId: accountId,
      categoryId: 'food',
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 200,
      dateTime: DateTime(2026, 9, 3),
      accountId: accountId,
      categoryId: 'food',
    );
    await expenses.createExpense(
      description: 'Dinner',
      totalAmount: 300,
      date: DateTime(2026, 9, 7),
      categoryId: 'food',
      accountId: accountId,
      splitType: SplitType.equal,
      participantInputs: const [
        ExpenseParticipantInput(name: 'Me', isMe: true),
        ExpenseParticipantInput(name: 'Person A'),
        ExpenseParticipantInput(name: 'Person B'),
      ],
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 100,
      dateTime: DateTime(2026, 9, 9),
      accountId: accountId,
      categoryId: 'food',
    );
    await container.read(transactionsStreamProvider.future);
    await container.read(expensesStreamProvider.future);

    setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 10));

    final categoryTotal = container.read(myExpensesByCategoryProvider).firstWhere((c) => c.categoryId == 'food').amount;
    final lines = container.read(myExpensesForCategoryProvider('food'));
    final lineSum = lines.fold(0.0, (sum, l) => sum + l.myShare);

    expect(categoryTotal, 900, reason: '500 + 200 + 100 (my share of dinner) + 100 = 900');
    expect(lineSum, categoryTotal, reason: 'category history total must match the category total');
    expect(lines.length, 4);
    expect(lines.any((l) => l.isSplit && l.myShare == 100), isTrue, reason: 'shared dinner line shows only my ₹100 share');
  });

  test('a category with no lines in range does not appear in the grouping', () async {
    final accountId = await createAccount(container);
    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 500,
      dateTime: DateTime(2026, 9, 3),
      accountId: accountId,
      categoryId: 'food',
    );
    await container.read(transactionsStreamProvider.future);

    setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 10));

    final categories = container.read(myExpensesByCategoryProvider);
    expect(categories.any((c) => c.categoryId == 'travel'), isFalse);
  });

  test('changing the selected range updates category totals and history', () async {
    final accountId = await createAccount(container);
    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 500,
      dateTime: DateTime(2026, 9, 3),
      accountId: accountId,
      categoryId: 'food',
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 250,
      dateTime: DateTime(2026, 9, 15),
      accountId: accountId,
      categoryId: 'food',
    );
    await container.read(transactionsStreamProvider.future);

    setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 10));
    expect(container.read(myExpensesForCategoryProvider('food')).length, 1);
    expect(container.read(myExpensesByCategoryProvider).first.amount, 500);

    setRange(DateTime(2026, 9, 11), DateTime(2026, 9, 20));
    expect(container.read(myExpensesForCategoryProvider('food')).length, 1);
    expect(container.read(myExpensesByCategoryProvider).first.amount, 250);
  });

  test('categories are sorted highest amount first', () async {
    final accountId = await createAccount(container);
    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 200,
      dateTime: DateTime(2026, 9, 3),
      accountId: accountId,
      categoryId: 'travel',
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 700,
      dateTime: DateTime(2026, 9, 4),
      accountId: accountId,
      categoryId: 'food',
    );
    await container.read(transactionsStreamProvider.future);

    setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 10));

    final categories = container.read(myExpensesByCategoryProvider);
    expect(categories.first.categoryId, 'food');
    expect(categories.last.categoryId, 'travel');
  });
}
