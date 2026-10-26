import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/core/dashboard/domain/date_range_strategy.dart';
import 'package:finance_app/core/dashboard/presentation/providers/dashboard_display_providers.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_allocation_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/shared_credit_limit.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/lending/domain/loan_balance_sheet.dart';
import 'package:finance_app/features/lending/domain/ownership_share.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_balance_sheet_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/people/presentation/providers/person_position_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/reports/presentation/providers/category_spending_breakdown_provider.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';

/// Financial-risk fixtures R1, R3, R4 and R5 from the Dashboard audit.
///
/// These are DIAGNOSTIC tests: each builds the cross-platform scenario,
/// asserts what Flutter computes TODAY, and records Web's answer for the
/// same data (from `C:\Users\anjel\Flow-Fi-WEB`, read-only) as a constant so
/// the divergence is visible in one place. No financial logic was changed
/// for these. When a fix is approved, the "Flutter today" expectation is the
/// line that must change — the suite fails loudly instead of the behavior
/// drifting silently.
void main() {
  final now = DateTime.now();
  final longAgo = DateTime(now.year - 1, 1, 1);

  Transaction txn(
    String id,
    TransactionType type,
    double amount,
    DateTime at, {
    String accountId = 'bank',
    String categoryId = 'general',
    String? transferId,
    String? emiId,
    PaymentAllocationType? allocation,
  }) => Transaction(
    id: id,
    type: type,
    amount: amount,
    dateTime: at,
    accountId: accountId,
    categoryId: categoryId,
    createdAt: at,
    transferId: transferId,
    emiId: emiId,
    paymentAllocationType: allocation,
    // Transfer legs are always stored excluded (see TransactionRepository).
    excludeFromCalculations: transferId != null,
  );

  // -------------------------------------------------------------------------
  group('R1 — card bill paid on Web, cached Statement.amountPaid stale', () {
    // Web pays a card bill with a transfer into the card account and never
    // writes Statement.amountPaid / statementPayments (Web
    // `use-dashboard-data.ts`, WFI-P2-02) — it derives what's left from the
    // card's transactions (`cardBillsForCard`).
    const webRemaining = 0.0;

    test('CONFIRMED: Flutter still shows the full bill as remaining', () async {
      final periodStart = DateTime(now.year, now.month - 1, 1);
      final periodEnd = DateTime(now.year, now.month - 1, 28);
      final paidOn = DateTime(now.year, now.month - 1, 28, 18);
      final card = CreditCardProfile(
        id: 'card1',
        accountId: 'cardAcc',
        statementDay: 28,
        paymentDueDay: 15,
        creditLimit: 100000,
        createdAt: longAgo,
      );
      final statement = Statement(
        id: 's1',
        cardId: 'card1',
        periodStart: periodStart,
        periodEnd: periodEnd,
        generatedDate: periodEnd,
        dueDate: DateTime(now.year, now.month, 15),
        totalAmount: 1000,
        createdAt: periodEnd,
        // amountPaid: 0 — what Web leaves behind.
      );
      final transactions = [
        txn(
          'buy',
          TransactionType.expense,
          1000,
          DateTime(now.year, now.month - 1, 10),
          accountId: 'cardAcc',
        ),
        // The Web payment: bank → card transfer for the full bill.
        txn('legOut', TransactionType.expense, 1000, paidOn, transferId: 't1'),
        txn(
          'legIn',
          TransactionType.income,
          1000,
          paidOn,
          accountId: 'cardAcc',
          transferId: 't1',
        ),
      ];
      final c = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(signedIn: true),
          ),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
          statementsStreamProvider.overrideWith(
            (ref, cardId) => Stream.value([statement]),
          ),
          transactionsStreamProvider.overrideWith(
            (ref) => Stream.value(transactions),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authStateProvider.future);
      c.listen(statementsWithLiveTotalsProvider('card1'), (_, _) {});
      c.listen(creditCardsStreamProvider, (_, _) {});
      c.listen(transactionsStreamProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final live = c.read(statementsWithLiveTotalsProvider('card1')).single;
      // Live total is right (recomputed from the card's purchases)…
      expect(live.totalAmount, 1000);
      // …but what's left comes from the cached amountPaid, and the card
      // statement logic never sees the payment at all: transfer legs are
      // dropped by calculableTransactionsProvider before it.
      expect(c.read(transactionsForCardProvider('card1')).map((t) => t.id), [
        'buy',
      ]);
      expect(live.remainingAmount, 1000, reason: 'Flutter today');
      expect(live.remainingAmount, isNot(webRemaining), reason: 'Web: paid');
      // upcomingDueProvider lists a card statement with exactly this
      // `remainingAmount`, so the Dashboard's Upcoming / Attention would
      // show ₹1,000 due on a bill Web considers paid.
    });
  });

  // -------------------------------------------------------------------------
  group('R3 — People in Net Worth: EMI shares and advances', () {
    test('CONFIRMED: a Web shared-EMI share owed to me is not in Flutter '
        'Net Worth', () async {
      // Web: People balance = Σ(directBalance + emiReceivable), where
      // emiReceivable = the person's share of every installment already due
      // (`peopleNetWorthPosition`, `emiReceivableThrough`). Flutter parses
      // the same `ownershipShares` field but no People / Net Worth provider
      // reads it.
      final shared = Emi(
        id: 'e1',
        name: 'Shared phone EMI',
        principalAmount: 60000,
        startDate: DateTime(now.year, now.month - 6, 5),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        endDate: DateTime(now.year, now.month + 6, 5),
        scheduleId: 'sch1',
        createdAt: longAgo,
        ownershipShares: const [
          OwnershipShare(personId: 'p1', amount: 30000),
          OwnershipShare(personId: null, amount: 30000),
        ],
      );
      final c = ProviderContainer(
        overrides: [
          peopleStreamProvider.overrideWith(
            (ref) => Stream.value([
              Person(
                id: 'p1',
                name: 'Co-owner',
                avatarColorValue: 0,
                openingBalance: 0,
                currentBalance: 0,
                createdAt: longAgo,
              ),
            ]),
          ),
          emisStreamProvider.overrideWith((ref) => Stream.value([shared])),
          loansStreamProvider.overrideWith((ref) => Stream.value(const [])),
          loansTrashStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
      );
      addTearDown(c.dispose);
      for (final p in [
        peopleStreamProvider,
        emisStreamProvider,
        loansStreamProvider,
        loansTrashStreamProvider,
      ]) {
        c.listen(p, (_, _) {});
      }
      await Future<void>.delayed(Duration.zero);

      expect(c.read(personPositionProvider('p1')).net, 0);
      expect(c.read(peopleDirectBalanceProvider), 0, reason: 'Flutter today');
      // Web, six installments in: p1 owes their half of each due
      // installment, so Web's People balance (and Net Worth) is higher by
      // that receivable. Exact amount depends on the installment schedule.
    });

    test(
      'CONFIRMED: an unapplied advance is counted as debt, not "held"',
      () async {
        // A person who paid me ₹2,000 ahead is a negative direct balance.
        // Net Worth is the same on both apps (Web: assets − debt − held), but
        // Web reports it as "Held for people", never as debt; Flutter has no
        // advance concept at the Net Worth level, so the Dashboard's Debt line
        // includes it.
        final c = ProviderContainer(
          overrides: [
            netWorthWithLoansProvider.overrideWithValue(48000),
            liabilityTotalsProvider.overrideWithValue(
              const LiabilityTotals(creditCards: 0, loans: 0, emis: 0),
            ),
            peopleStreamProvider.overrideWith(
              (ref) => Stream.value([
                Person(
                  id: 'adv',
                  name: 'Paid ahead',
                  avatarColorValue: 0,
                  openingBalance: 0,
                  currentBalance: -2000,
                  createdAt: longAgo,
                ),
              ]),
            ),
            loansStreamProvider.overrideWith((ref) => Stream.value(const [])),
            loansTrashStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        );
        addTearDown(c.dispose);
        c.listen(peopleStreamProvider, (_, _) {});
        c.listen(loansStreamProvider, (_, _) {});
        c.listen(loansTrashStreamProvider, (_, _) {});
        await Future<void>.delayed(Duration.zero);

        final composition = c.read(netWorthCompositionProvider);
        expect(composition.peopleDebt, 2000, reason: 'Flutter today');
        expect(composition.debt, 2000);
        expect(composition.assets - composition.debt, 48000); // NW unchanged
        // Web for the same data: debt 0, heldForPeople 2000, assets 50000.
      },
    );
  });

  // -------------------------------------------------------------------------
  group('R4 — EMI repayment in category spending', () {
    test('CONFIRMED: an EMI repayment is counted as category spend when its '
        'purchase is already recorded', () async {
      // Web `classifyForMySpend`: a regularEmi/advanceEmi/principalPrepayment
      // payment on an agreement whose purchase is recorded is a liability
      // repayment, not consumption (the purchase was the spend).
      const webTotal = 60000.0;
      final month = DateTime(now.year, now.month, 2);
      final transactions = [
        txn(
          'buy',
          TransactionType.expense,
          60000,
          month,
          categoryId: 'electronics',
        ),
        txn(
          'emiPay',
          TransactionType.expense,
          5000,
          month.add(const Duration(days: 1)),
          categoryId: 'emi',
          emiId: 'e1',
          allocation: PaymentAllocationType.regularEmi,
        ),
      ];
      Category category(String id) => Category(
        id: id,
        name: id,
        type: CategoryType.expense,
        iconKey: 'category',
        colorValue: 0xFF000000,
        createdAt: longAgo,
      );
      final c = ProviderContainer(
        overrides: [
          calculableTransactionsProvider.overrideWithValue(transactions),
          categoriesStreamProvider.overrideWith(
            (ref) => Stream.value([category('electronics'), category('emi')]),
          ),
          expensesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      addTearDown(c.dispose);
      c.listen(categoriesStreamProvider, (_, _) {});
      c.listen(expensesStreamProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final range = const ReportsPeriodStrategy(
        ReportsPeriod.thisMonth,
      ).resolve(now);
      final entries = c.read(
        categorySpendingBreakdownProvider((
          range: range,
          period: ReportsPeriod.thisMonth,
        )),
      );
      final total = entries.fold(0.0, (s, e) => s + e.amount);
      expect(entries.map((e) => e.category.id), ['electronics', 'emi']);
      expect(total, 65000, reason: 'Flutter today');
      expect(total, isNot(webTotal));
    });
  });

  // -------------------------------------------------------------------------
  group('R5 — shared credit limit with locked EMI', () {
    test('CONFIRMED: dashboard utilization omits the locked EMI and repeats '
        'the facility once per card', () async {
      // One facility: ₹2,00,000 shared limit, ₹50,000 outstanding, ₹50,000
      // locked card-EMI principal. Flutter's available =
      // limit − outstanding − locked = ₹1,00,000 (`_availableFor`).
      const facility = (
        outstanding: 50000.0,
        available: 100000.0,
        currentCycleSpend: 0.0,
      );
      CreditCardProfile card(String id) => CreditCardProfile(
        id: id,
        accountId: '$id-acc',
        statementDay: 1,
        paymentDueDay: 20,
        creditLimit: 200000,
        createdAt: longAgo,
        sharedLimitId: 'g1',
      );
      final cards = [card('visa'), card('rupay')];
      final c = ProviderContainer(
        overrides: [
          activeCreditCardsProvider.overrideWithValue(cards),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value(cards)),
          accountsStreamProvider.overrideWith(
            (ref) => Stream.value([
              for (final k in cards)
                Account(
                  id: k.accountId,
                  name: k.id,
                  type: AccountType.card,
                  openingBalance: 0,
                  currentBalance: 0,
                  colorValue: 0,
                  createdAt: longAgo,
                ),
            ]),
          ),
          sharedCreditLimitsStreamProvider.overrideWith(
            (ref) => Stream.value([
              SharedCreditLimit(
                id: 'g1',
                name: 'HDFC facility',
                creditLimit: 200000,
                createdAt: longAgo,
              ),
            ]),
          ),
          sharedCreditLimitStandingProvider.overrideWith((ref, id) => facility),
        ],
      );
      addTearDown(c.dispose);
      c.listen(creditCardsStreamProvider, (_, _) {});
      c.listen(sharedCreditLimitsStreamProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      // What CreditUtilizationWidgetCard computes.
      final outstanding = c.read(totalCreditCardOutstandingProvider);
      final available = c.read(totalCreditAvailableProvider);
      final flutterPercent = (outstanding / (outstanding + available) * 100)
          .round();
      expect(flutterPercent, 33, reason: 'Flutter today: 50k / 150k');

      // Web: (outstanding + locked EMI) / the facility's ONE limit.
      final limit = c.read(totalCreditLimitProvider);
      expect(limit, 200000); // counted once — this part already matches
      const webPercent = 50; // (50k + 50k) / 200k
      expect(flutterPercent, isNot(webPercent));

      // Per-card rows: each sibling card reports the pooled facility
      // standing, so the facility appears twice (Web: one row, "shared (2
      // cards)").
      c.listen(creditCardStandingProvider('visa'), (_, _) {});
      c.listen(creditCardStandingProvider('rupay'), (_, _) {});
      expect(c.read(creditCardStandingProvider('visa')), facility);
      expect(c.read(creditCardStandingProvider('rupay')), facility);
    });
  });
}
