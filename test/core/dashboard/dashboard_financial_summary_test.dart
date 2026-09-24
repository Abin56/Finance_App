import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/dashboard/presentation/providers/dashboard_financial_summary_provider.dart';
import 'package:finance_app/core/dashboard/presentation/providers/upcoming_due_provider.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Coverage for [dashboardFinancialSummaryProvider] — the Dashboard's single
/// cross-feature financial-summary composition layer. Every case below
/// checks that the summary is a strict passthrough/addition of already-final
/// source-provider numbers, never a recalculation — the source providers
/// themselves (`netWorthProvider`, `cashFlowThisMonthProvider`,
/// `totalCreditCardOutstandingProvider`, `totalAmountToPayProvider`,
/// `upcomingDueProvider`) are overridden directly, the same boundary
/// `test/core/dashboard/upcoming_due_provider_test.dart` overrides at,
/// rather than rebuilding every feature's full Firestore-backed stack.
void main() {
  late ProviderContainer container;

  ProviderContainer buildContainer({
    double netWorth = 0,
    ({double moneyIn, double moneyOut, double net}) cashFlow = (moneyIn: 0, moneyOut: 0, net: 0),
    double creditCardOutstanding = 0,
    double loanPayable = 0,
    double loanReceivable = 0,
    double peoplePayable = 0,
    double peopleReceivable = 0,
    List<UpcomingDueItem> upcomingItems = const [],
  }) {
    final c = ProviderContainer(
      overrides: [
        netWorthProvider.overrideWithValue(netWorth),
        cashFlowThisMonthProvider.overrideWithValue(cashFlow),
        totalCreditCardOutstandingProvider.overrideWithValue(creditCardOutstanding),
        totalAmountToPayProvider.overrideWithValue(loanPayable),
        totalAmountToReceiveProvider.overrideWithValue(loanReceivable),
        totalPayableProvider.overrideWithValue(peoplePayable),
        totalReceivableProvider.overrideWithValue(peopleReceivable),
        upcomingDueProvider.overrideWith((ref, cycle) => upcomingItems),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  UpcomingDueItem item({
    required UpcomingDueKind kind,
    required double remaining,
    required bool isCarriedOver,
    String routeId = 'r1',
  }) {
    return (
      kind: kind,
      title: 'item',
      dueDate: DateTime.now(),
      remaining: remaining,
      urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgency.upcoming,
      isCarriedOver: isCarriedOver,
      routeId: routeId,
      secondaryRouteId: null,
    );
  }

  test('1. correct aggregation of a mixed portfolio (accounts + credit card + loan + bills present)', () {
    container = buildContainer(
      netWorth: 50000,
      cashFlow: (moneyIn: 20000, moneyOut: 12000, net: 8000),
      creditCardOutstanding: 3000,
      loanPayable: 7000,
      upcomingItems: [
        item(kind: UpcomingDueKind.bill, remaining: 1500, isCarriedOver: false),
        item(kind: UpcomingDueKind.emi, remaining: 2500, isCarriedOver: true),
      ],
    );
    final summary = container.read(dashboardFinancialSummaryProvider);

    expect(summary.netWorth, 50000);
    expect(summary.moneyIn, 20000);
    expect(summary.moneyOut, 12000);
    expect(summary.netCashFlow, 8000);
    expect(summary.outstandingDebt, 10000); // 3000 + 7000
    expect(summary.upcomingObligationsTotal, 1500);
    expect(summary.overdueObligationsTotal, 2500);
  });

  test('2. empty data — all fields zero, no exceptions', () {
    container = buildContainer();
    final summary = container.read(dashboardFinancialSummaryProvider);

    expect(summary.netWorth, 0);
    expect(summary.moneyIn, 0);
    expect(summary.moneyOut, 0);
    expect(summary.netCashFlow, 0);
    expect(summary.outstandingDebt, 0);
    expect(summary.upcomingObligationsTotal, 0);
    expect(summary.overdueObligationsTotal, 0);
  });

  test('3. mixed financial products present simultaneously does not throw and sums independently', () {
    container = buildContainer(
      netWorth: 1000,
      cashFlow: (moneyIn: 500, moneyOut: 200, net: 300),
      creditCardOutstanding: 100,
      loanPayable: 50,
      upcomingItems: [
        item(kind: UpcomingDueKind.creditCard, remaining: 10, isCarriedOver: false),
        item(kind: UpcomingDueKind.loan, remaining: 20, isCarriedOver: false),
        item(kind: UpcomingDueKind.bill, remaining: 30, isCarriedOver: true),
        item(kind: UpcomingDueKind.splitExpense, remaining: 40, isCarriedOver: false),
      ],
    );
    final summary = container.read(dashboardFinancialSummaryProvider);
    expect(summary.upcomingObligationsTotal, 10 + 20 + 40);
    expect(summary.overdueObligationsTotal, 30);
  });

  test('4. credit card outstanding correctly included in outstandingDebt', () {
    container = buildContainer(creditCardOutstanding: 4321, loanPayable: 0);
    expect(container.read(dashboardFinancialSummaryProvider).outstandingDebt, 4321);
  });

  test('5. loan payable correctly included in outstandingDebt', () {
    container = buildContainer(creditCardOutstanding: 0, loanPayable: 1234);
    expect(container.read(dashboardFinancialSummaryProvider).outstandingDebt, 1234);
  });

  test('6. EMI-related upcoming obligations reflected (in scope of upcomingDueProvider)', () {
    container = buildContainer(
      upcomingItems: [item(kind: UpcomingDueKind.emi, remaining: 999, isCarriedOver: false)],
    );
    expect(container.read(dashboardFinancialSummaryProvider).upcomingObligationsTotal, 999);
  });

  test('7. Bills-related upcoming obligations reflected (in scope of upcomingDueProvider)', () {
    container = buildContainer(
      upcomingItems: [item(kind: UpcomingDueKind.bill, remaining: 777, isCarriedOver: false)],
    );
    expect(container.read(dashboardFinancialSummaryProvider).upcomingObligationsTotal, 777);
  });

  test(
    '8. People payable/receivable are deliberately NOT netted into outstandingDebt — '
    'DashboardFinancialSummary has no field composing totalPayableProvider/totalReceivableProvider',
    () {
      // Two containers differing ONLY in People payable/receivable — since
      // DashboardFinancialSummary has no field sourced from those providers,
      // changing them must never move outstandingDebt or any other field.
      final withoutPeopleDebt = buildContainer(creditCardOutstanding: 100, loanPayable: 50);
      final withPeopleDebt = buildContainer(
        creditCardOutstanding: 100,
        loanPayable: 50,
        peoplePayable: 99999,
        peopleReceivable: 99999,
      );
      final a = withoutPeopleDebt.read(dashboardFinancialSummaryProvider);
      final b = withPeopleDebt.read(dashboardFinancialSummaryProvider);
      expect(a.outstandingDebt, b.outstandingDebt);
      expect(a.outstandingDebt, 150);
    },
  );

  test(
    '9. No TransactionType.transfer exists in this codebase — TransactionType only has '
    '{income, expense} — so DashboardFinancialSummary has no transfer handling to omit or invent',
    () {
      expect(TransactionType.values.map((t) => t.name), containsAll(['income', 'expense']));
      expect(TransactionType.values, hasLength(2));
    },
  );

  group('10-11. soft-delete and excludeFromCalculations propagate through real repositories', () {
    late ProviderContainer realContainer;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LocalSettingsService.init();
      final auth = MockFirebaseAuth(signedIn: true);
      final firestore = FakeFirebaseFirestore();
      realContainer = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          // Keep the non-account-related composed figures deterministic —
          // this group only exercises netWorth (accounts) and moneyIn/moneyOut
          // (calculableTransactionsProvider), which the composition provider
          // never re-filters itself; every other source stays at its
          // Firestore-backed default (empty streams).
        ],
      );
      addTearDown(realContainer.dispose);
      await realContainer.read(authStateProvider.future);
    });

    test('10. a soft-deleted account is excluded from netWorth (via netWorthProvider itself)', () async {
      final accounts = realContainer.read(accountRepositoryProvider);
      final kept = await accounts.createAccount(
        name: 'Kept',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );
      final deleted = await accounts.createAccount(
        name: 'Deleted',
        type: AccountType.cash,
        openingBalance: 5000,
        colorValue: 0xFF000000,
      );
      await accounts.softDelete(deleted);

      await realContainer.read(accountsStreamProvider.future);
      final summary = realContainer.read(dashboardFinancialSummaryProvider);

      // Only the kept account's balance should count — proves the summary
      // never bypasses netWorthProvider's own soft-delete-aware stream.
      expect(summary.netWorth, kept.openingBalance);
    });

    test('11. excludeFromCalculations flag excludes a transaction from moneyIn/moneyOut', () async {
      final accounts = realContainer.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final transactions = realContainer.read(transactionRepositoryProvider);
      final now = DateTime.now();

      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1000,
        dateTime: now,
        accountId: account.id,
        categoryId: 'cat',
        description: 'Included income',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 99999,
        dateTime: now,
        accountId: account.id,
        categoryId: 'cat',
        description: 'Excluded income',
        excludeFromCalculations: true,
      );

      await realContainer.read(transactionsStreamProvider.future);
      final summary = realContainer.read(dashboardFinancialSummaryProvider);

      expect(summary.moneyIn, 1000);
    });
  });

  test(
    '12. date-range correctness for the cash-flow portion matches cashFlowThisMonthProvider '
    'exactly — moneyIn/moneyOut/netCashFlow are read from it, never recomputed for a '
    'different window',
    () {
      const cashFlow = (moneyIn: 4000.0, moneyOut: 1500.0, net: 2500.0);
      container = buildContainer(cashFlow: cashFlow);
      final summary = container.read(dashboardFinancialSummaryProvider);
      expect(summary.moneyIn, cashFlow.moneyIn);
      expect(summary.moneyOut, cashFlow.moneyOut);
      expect(summary.netCashFlow, cashFlow.net);
    },
  );

  test('13. provider failure/error state does not crash — upcomingDueProvider empty list is handled', () {
    // upcomingDueProvider is a plain (non-async) Provider.family that always
    // returns a resolved list (see upcoming_due_provider.dart) — there is no
    // AsyncValue/error state for this composition to guard against, matching
    // the audit's finding that no Dashboard widget distinguishes
    // loading/error from empty today. An empty list must resolve cleanly.
    container = buildContainer(upcomingItems: const []);
    expect(() => container.read(dashboardFinancialSummaryProvider), returnsNormally);
  });

  test('14. refresh/invalidation propagates — changing an override and invalidating updates the summary', () {
    var netWorth = 100.0;
    container = ProviderContainer(
      overrides: [
        netWorthProvider.overrideWith((ref) => netWorth),
        cashFlowThisMonthProvider.overrideWithValue((moneyIn: 0.0, moneyOut: 0.0, net: 0.0)),
        totalCreditCardOutstandingProvider.overrideWithValue(0),
        totalAmountToPayProvider.overrideWithValue(0),
        upcomingDueProvider.overrideWith((ref, cycle) => const []),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(dashboardFinancialSummaryProvider).netWorth, 100);

    netWorth = 250;
    container.invalidate(netWorthProvider);
    container.invalidate(dashboardFinancialSummaryProvider);

    expect(container.read(dashboardFinancialSummaryProvider).netWorth, 250);
  });
}
