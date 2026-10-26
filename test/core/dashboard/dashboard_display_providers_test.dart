import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/core/dashboard/presentation/providers/dashboard_display_providers.dart';
import 'package:finance_app/core/dashboard/presentation/providers/upcoming_due_provider.dart';
import 'package:finance_app/core/extensions/date_extensions.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/cash_flow/domain/money_flow_line.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/lending/domain/loan_balance_sheet.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_balance_sheet_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/domain/person_position.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/people/presentation/providers/person_position_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';

/// Display-only Dashboard compositions (`dashboard_display_providers.dart`).
/// Every source is overridden at its stream / already-final-total boundary.
void main() {
  final today = DateTime.now().dateOnly;
  final longAgo = today.subtract(const Duration(days: 60));

  Transaction txn(
    String id,
    TransactionType type,
    double amount,
    DateTime at, {
    String? transferId,
    String? loanId,
    String? linkedPersonId,
  }) => Transaction(
    id: id,
    type: type,
    amount: amount,
    dateTime: at,
    accountId: 'bank',
    categoryId: 'c1',
    createdAt: at,
    transferId: transferId,
    loanId: loanId,
    linkedPersonId: linkedPersonId,
  );

  Account account({DateTime? createdAt}) => Account(
    id: 'bank',
    name: 'Bank',
    type: AccountType.bank,
    openingBalance: 0,
    currentBalance: 10000,
    colorValue: 0xFF000000,
    createdAt: createdAt ?? longAgo,
  );

  Future<ProviderContainer> trendContainer({
    required List<Transaction> transactions,
    List<Account>? accounts,
    double netWorth = 10000,
  }) async {
    final c = ProviderContainer(
      overrides: [
        transactionsStreamProvider.overrideWith(
          (ref) => Stream.value(transactions),
        ),
        accountsStreamProvider.overrideWith(
          (ref) => Stream.value(accounts ?? [account()]),
        ),
        loansStreamProvider.overrideWith((ref) => Stream.value(const [])),
        emisStreamProvider.overrideWith((ref) => Stream.value(const [])),
        peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
        expensesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        netWorthWithLoansProvider.overrideWithValue(netWorth),
      ],
    );
    addTearDown(c.dispose);
    // Keep each stream subscribed while its first value lands.
    for (final p in [
      transactionsStreamProvider,
      accountsStreamProvider,
      loansStreamProvider,
      emisStreamProvider,
      peopleStreamProvider,
      expensesStreamProvider,
    ]) {
      c.listen(p, (_, _) {});
    }
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  group('B1 — Net Worth 7-day trend', () {
    test('replays plain account transactions back from today', () async {
      final c = await trendContainer(
        transactions: [
          txn(
            'in',
            TransactionType.income,
            1000,
            today.subtract(const Duration(days: 2, hours: -12)),
          ),
          txn(
            'out',
            TransactionType.expense,
            300,
            today.add(const Duration(hours: 9)),
          ),
          // Old activity outside the window never moves the line.
          txn('old', TransactionType.expense, 5000, longAgo),
        ],
      );
      final trend = c.read(netWorthTrendProvider);
      expect(trend.status, NetWorthTrendStatus.available);
      // End of (today−6 … today−3): before the income and the expense.
      // End of today−2 and −1: after the income, before today's expense.
      // End of today: the headline figure itself.
      expect(trend.values, [9300, 9300, 9300, 9300, 10300, 10300, 10000]);
      expect(trend.values!.last, 10000);
    });

    test('transfer legs are Net-Worth-neutral', () async {
      final c = await trendContainer(
        transactions: [
          txn('leg1', TransactionType.expense, 4000, today, transferId: 't1'),
          txn('leg2', TransactionType.income, 4000, today, transferId: 't1'),
        ],
      );
      final trend = c.read(netWorthTrendProvider);
      expect(trend.status, NetWorthTrendStatus.available);
      expect(trend.isFlat, isTrue);
    });

    test(
      'a loan payment in the window makes it unavailable, not guessed',
      () async {
        final c = await trendContainer(
          transactions: [
            txn('emi', TransactionType.expense, 2500, today, loanId: 'loan1'),
          ],
        );
        expect(
          c.read(netWorthTrendProvider).status,
          NetWorthTrendStatus.unavailable,
        );
      },
    );

    test(
      'a person-linked expense in the window makes it unavailable',
      () async {
        final c = await trendContainer(
          transactions: [
            txn(
              'p',
              TransactionType.expense,
              800,
              today,
              linkedPersonId: 'person1',
            ),
          ],
        );
        expect(
          c.read(netWorthTrendProvider).status,
          NetWorthTrendStatus.unavailable,
        );
      },
    );

    test('an account opened this week makes it unavailable', () async {
      final c = await trendContainer(
        transactions: const [],
        accounts: [account(createdAt: today.subtract(const Duration(days: 1)))],
      );
      expect(
        c.read(netWorthTrendProvider).status,
        NetWorthTrendStatus.unavailable,
      );
    });

    test('still loading while transactions have not arrived', () {
      final c = ProviderContainer(
        overrides: [
          transactionsStreamProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(netWorthTrendProvider).status, NetWorthTrendStatus.loading);
    });
  });

  test('Assets − Debt reconciles to Net Worth exactly', () async {
    final c = ProviderContainer(
      overrides: [
        netWorthWithLoansProvider.overrideWithValue(50000),
        liabilityTotalsProvider.overrideWithValue(
          const LiabilityTotals(creditCards: 2000, loans: 3000, emis: 1000),
        ),
        peopleStreamProvider.overrideWith(
          (ref) => Stream.value([
            Person(
              id: 'owes-me',
              name: 'A',
              avatarColorValue: 0,
              openingBalance: 0,
              currentBalance: 0,
              createdAt: longAgo,
            ),
            Person(
              id: 'i-owe',
              name: 'B',
              avatarColorValue: 0,
              openingBalance: 0,
              currentBalance: 0,
              createdAt: longAgo,
            ),
          ]),
        ),
        personPositionProvider.overrideWith(
          (ref, id) => PersonPosition(
            directBalance: id == 'i-owe' ? -700 : 1200,
            loanReceivable: 0,
            loanPayable: 0,
            legacyLoanLedger: 0,
            net: id == 'i-owe' ? -700 : 1200,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(peopleStreamProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);

    final composition = c.read(netWorthCompositionProvider);
    expect(composition.debt, 6700); // 2000 + 3000 + 1000 + 700 owed to B
    expect(composition.loanDebt, 4000);
    expect(composition.peopleDebt, 700);
    expect(composition.assets - composition.debt, 50000);
  });

  test('weekly cash-flow bars add up to the month net', () {
    final month = DateTime(today.year, today.month);
    MoneyFlowLine line(int day, double amount) => (
      kind: MoneyFlowKind.income,
      date: DateTime(month.year, month.month, day),
      title: 't',
      amount: amount,
      categoryLabel: null,
      accountLabel: null,
    );
    final ins = [line(2, 50000), line(16, 1200)];
    final outs = [line(3, 8000), line(10, 4500), line(23, 9000)];
    final c = ProviderContainer(
      overrides: [
        moneyInLinesForRangeFamilyProvider.overrideWith((ref, key) => ins),
        moneyOutLinesForRangeFamilyProvider.overrideWith((ref, key) => outs),
      ],
    );
    addTearDown(c.dispose);

    final weeks = c.read(dashboardWeeklyCashFlowProvider);
    expect(weeks.map((w) => w.net), [42000, -4500, 1200, -9000]);
    expect(weeks.fold(0.0, (s, w) => s + w.net), 50000 + 1200 - 21500);
    expect(weeks.first.label, '1–7');
    expect(weeks.last.label, startsWith('22–'));
  });

  test(
    'attention: overdue outgoing items + the next one; receivables never',
    () {
      UpcomingDueItem item(
        UpcomingDueKind kind,
        int dueInDays,
        double remaining,
      ) => (
        kind: kind,
        title: kind.name,
        dueDate: today.add(Duration(days: dueInDays)),
        remaining: remaining,
        urgency: dueInDays < 0
            ? PaymentUrgency.overdue
            : PaymentUrgency.upcoming,
        isCarriedOver: false,
        routeId: kind.name,
        secondaryRouteId: null,
      );
      final c = ProviderContainer(
        overrides: [
          upcomingDueProvider.overrideWith(
            (ref, cycle) => [
              item(UpcomingDueKind.splitExpense, -9, 999), // owed TO me
              item(UpcomingDueKind.emi, 3, 2500),
              item(UpcomingDueKind.bill, -2, 1200),
              item(UpcomingDueKind.creditCard, -5, 4000),
              item(UpcomingDueKind.loan, 0, 700), // due today = not overdue
            ],
          ),
        ],
      );
      addTearDown(c.dispose);

      final attention = c.read(dashboardAttentionProvider);
      expect(attention.overdue.map((i) => i.kind), [
        UpcomingDueKind.creditCard, // oldest first
        UpcomingDueKind.bill,
      ]);
      expect(attention.overdueTotal, 5200);
      expect(attention.next?.kind, UpcomingDueKind.loan);
    },
  );
}
