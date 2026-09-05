import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/cash_flow/domain/cash_flow_period.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces exactly what CashFlowPeriodSelector does when the user picks
/// ONE single date via showDateRangePicker (start == end, both at midnight,
/// then the widget pushes end to 23:59:59.999), with a food transaction
/// entered at a real time of day (e.g. 1:30pm) — the realistic case, not a
/// midnight-only fixture.
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

  test('single-date pick shows a food expense entered that same day at 1:30pm', () async {
    final accounts = container.read(accountRepositoryProvider);
    final accountId = (await accounts.createAccount(
      name: 'Wallet',
      type: AccountType.cash,
      openingBalance: 10000,
      colorValue: 0xFF000000,
    )).id;

    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 500,
      dateTime: DateTime(2026, 9, 5, 13, 30),
      accountId: accountId,
      categoryId: 'food',
      description: 'Lunch',
    );
    await container.read(transactionsStreamProvider.future);

    // Exactly what CashFlowPeriodSelector does for a single-day pick.
    final pickedStart = DateTime(2026, 9, 5); // midnight
    final pickedEnd = DateTime(2026, 9, 5); // midnight (same day picked twice)
    final end = DateTime(pickedEnd.year, pickedEnd.month, pickedEnd.day, 23, 59, 59, 999);
    container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
      DateRange(pickedStart, end),
    );

    final lines = container.read(myExpenseLinesForRangeProvider);
    final total = container.read(myExpensesForRangeProvider).total;
    final categories = container.read(myExpensesByCategoryProvider);

    expect(lines.length, 1, reason: 'the lunch transaction should be in range');
    expect(total, 500);
    expect(categories.any((c) => c.categoryId == 'food'), isTrue);
  });
}
