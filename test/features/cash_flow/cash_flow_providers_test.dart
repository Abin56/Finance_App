import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Provider-level tests for the Cash Flow Center's aggregation logic —
/// each test seeds fixtures through the real repositories (same path the
/// app takes) and asserts on the composed provider's output, since these
/// providers are pure composition over other providers with no repository
/// layer of their own to unit-test directly.
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

  group('totalDueThisMonthProvider', () {
    test('sums due/paid/remaining across this-month bills only (current month only)', () async {
      final now = DateTime.now();
      final bills = container.read(billRepositoryProvider);

      final billA = await bills.createBill(
        name: 'Electricity',
        amount: 1000,
        dueDate: DateTime(now.year, now.month, 10),
        recurrence: BillRecurrence.monthly,
      );
      final paymentRepo = container.read(paymentRepositoryProvider(billA.id));
      await paymentRepo.recordPayment(billA, amount: 400, date: now);

      await container.read(billsStreamProvider.future);

      final breakdown = container.read(billsDueThisMonthBreakdownProvider);
      expect(breakdown.due, 1000);
      expect(breakdown.paid, 400);
      expect(breakdown.remaining, 600);

      final total = container.read(totalDueThisMonthProvider);
      expect(total.due, 1000);
      expect(total.paid, 400);
      expect(total.remaining, 600);
    });

    test('still counts an unpaid bill carried over from a prior month (overdue only)', () async {
      final now = DateTime.now();
      final bills = container.read(billRepositoryProvider);

      // Due last month, never paid — dueDate never rolled forward since
      // BillRepository only advances it on full payment/skip.
      final lastMonth = DateTime(now.year, now.month - 1, 10);
      await bills.createBill(
        name: 'Old bill',
        amount: 500,
        dueDate: lastMonth,
        recurrence: BillRecurrence.monthly,
      );

      await container.read(billsStreamProvider.future);

      final breakdown = container.read(billsDueThisMonthBreakdownProvider);
      expect(breakdown.due, 500);
      expect(breakdown.paid, 0);
      expect(breakdown.remaining, 500);

      final total = container.read(totalDueThisMonthProvider);
      expect(total.due, 500, reason: 'an overdue carry-over must still show up as due, not be dropped');
    });

    test('sums current-month due plus prior-month overdue (current month + overdue)', () async {
      final now = DateTime.now();
      final bills = container.read(billRepositoryProvider);

      final current = await bills.createBill(
        name: 'Electricity',
        amount: 1000,
        dueDate: DateTime(now.year, now.month, 10),
        recurrence: BillRecurrence.monthly,
      );
      final paymentRepo = container.read(paymentRepositoryProvider(current.id));
      await paymentRepo.recordPayment(current, amount: 400, date: now);

      final lastMonth = DateTime(now.year, now.month - 1, 10);
      await bills.createBill(
        name: 'Old bill',
        amount: 500,
        dueDate: lastMonth,
        recurrence: BillRecurrence.monthly,
      );

      await container.read(billsStreamProvider.future);

      final breakdown = container.read(billsDueThisMonthBreakdownProvider);
      expect(breakdown.due, 1500, reason: '1000 this month + 500 overdue');
      expect(breakdown.paid, 400);
      expect(breakdown.remaining, 1100);
    });

    test('excludes a prior-month bill that has since been fully paid off (paid overdue)', () async {
      final now = DateTime.now();
      final bills = container.read(billRepositoryProvider);

      // One-time (non-recurring) so a full payment settles it in place
      // instead of rolling it forward to a new this-month occurrence —
      // isolates "already paid" from "rolled over to a new due date".
      final lastMonth = DateTime(now.year, now.month - 1, 10);
      final oldBill = await bills.createBill(
        name: 'Old bill',
        amount: 500,
        dueDate: lastMonth,
        recurrence: BillRecurrence.oneTime,
      );
      final paymentRepo = container.read(paymentRepositoryProvider(oldBill.id));
      await paymentRepo.recordPayment(oldBill, amount: 500, date: now);

      await container.read(billsStreamProvider.future);

      final breakdown = container.read(billsDueThisMonthBreakdownProvider);
      expect(breakdown.due, 0, reason: 'a fully-paid overdue bill must not be counted as still due');
      expect(breakdown.paid, 0);
    });

    test('never double-counts a bill that already belongs to this month (duplicate prevention)', () async {
      final now = DateTime.now();
      final bills = container.read(billRepositoryProvider);

      await bills.createBill(
        name: 'Electricity',
        amount: 1000,
        dueDate: DateTime(now.year, now.month, 10),
        recurrence: BillRecurrence.monthly,
      );

      await container.read(billsStreamProvider.future);

      // This-month items and carry-over overdue items are drawn from the
      // same single pass over `billsStreamProvider` — assert the row count
      // implied by the total matches exactly one bill's amount, not two.
      final breakdown = container.read(billsDueThisMonthBreakdownProvider);
      expect(breakdown.due, 1000, reason: 'billA must be counted exactly once, not once per branch');
    });

    test('EMI installment breakdown also merges an unpaid prior-month installment', () async {
      final now = DateTime.now();
      final emis = container.read(emiRepositoryProvider);

      // Single-installment EMI whose only (unpaid) installment falls on
      // startDate, in a prior month — installment #1's dueDate always
      // equals firstDueDate/startDate exactly.
      final lastMonth = DateTime(now.year, now.month - 1, 10);
      await emis.createEmi(
        name: 'Old EMI',
        principalAmount: 1200,
        startDate: lastMonth,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 1,
      );

      await container.read(emisStreamProvider.future);
      final createdEmi = container.read(emisStreamProvider).value!.single;
      await container.read(installmentsStreamProvider(createdEmi.scheduleId).future);

      final breakdown = container.read(emiDueThisMonthBreakdownProvider);
      expect(breakdown.due, 1200, reason: 'an overdue EMI installment from a prior month must still be counted');
      expect(breakdown.remaining, 1200);
    });
  });

  group('totalMoneyToReceiveProvider', () {
    test('sums People-ledger and Lending receivables independently, no double-count', () async {
      final people = container.read(personRepositoryProvider);
      final person = await people.createPerson(name: 'Alex', avatarColorValue: 0xFF000000, openingBalance: 0);

      // Person owes the user money via the ledger (creditor).
      final ledger = container.read(ledgerRepositoryProvider(person.id));
      await ledger.addEntry(person, type: LedgerEntryType.gave, amount: 300, date: DateTime.now());

      // A separate loan given to the SAME person — proves the two totals
      // don't double-count even when they share a person, since Loan has
      // no link to the person ledger.
      final loans = container.read(loanRepositoryProvider);
      final loan = await loans.createLoan(
        personId: person.id,
        loanAmount: 500,
        loanDate: DateTime.now(),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );

      await container.read(peopleStreamProvider.future);
      await container.read(loansStreamProvider.future);
      await container.read(installmentsStreamProvider(loan.scheduleId).future);

      expect(container.read(peoplePendingReceivableProvider).amount, 300);
      expect(container.read(loanRecoveriesReceivableProvider).amount, 500);
      expect(container.read(totalMoneyToReceiveProvider), 800);
    });
  });

  group('upcomingPaymentsTimelineProvider', () {
    test('sorts overdue items before upcoming items regardless of relative dates', () async {
      final now = DateTime.now();
      final bills = container.read(billRepositoryProvider);

      final overdueBill = await bills.createBill(
        name: 'Overdue rent',
        amount: 2000,
        dueDate: now.subtract(const Duration(days: 5)),
        recurrence: BillRecurrence.monthly,
      );
      await bills.createBill(
        name: 'Upcoming internet',
        amount: 999,
        dueDate: now.add(const Duration(days: 1)),
        recurrence: BillRecurrence.monthly,
      );

      await container.read(billsStreamProvider.future);

      final items = container.read(upcomingPaymentsTimelineProvider);
      expect(items, isNotEmpty);
      expect(items.first.title, 'Overdue rent');
      expect(items.first.urgency, PaymentUrgency.overdue);
      expect(items.first.routeId, overdueBill.id);
    });
  });

  group('cashFlowThisMonthProvider', () {
    test('moneyOut adds bill payments on top of expense transactions, not double-counted', () async {
      final now = DateTime.now();
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 10000,
        colorValue: 0xFF000000,
      );

      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 5000,
        dateTime: now,
        accountId: account.id,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 1200,
        dateTime: now,
        accountId: account.id,
        categoryId: 'groceries',
      );

      final bills = container.read(billRepositoryProvider);
      // Paid partially (not in full) so the bill stays in this month's
      // breakdown rather than rolling over to its next recurring
      // occurrence (see `Bill`'s rollover-on-full-payment behavior).
      final bill = await bills.createBill(
        name: 'Water',
        amount: 300,
        dueDate: DateTime(now.year, now.month, 15),
        recurrence: BillRecurrence.monthly,
      );
      final paymentRepo = container.read(paymentRepositoryProvider(bill.id));
      await paymentRepo.recordPayment(bill, amount: 150, date: now);

      await container.read(transactionsStreamProvider.future);
      await container.read(billsStreamProvider.future);

      final cashFlow = container.read(cashFlowThisMonthProvider);
      expect(cashFlow.moneyIn, 5000);
      // 1200 (expense transaction) + 150 (bill payment, which never posts
      // its own Transaction) — must be additive, not one or the other.
      expect(cashFlow.moneyOut, 1350);
      expect(cashFlow.net, 3650);
    });

    test('excludes a transfer between the user\'s own accounts from both moneyIn and moneyOut', () async {
      final now = DateTime.now();
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
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 5000,
        dateTime: now,
        accountId: source.id,
        categoryId: 'salary',
      );
      // A transfer's two legs must not count as real income/expense — if
      // they did, moneyIn and moneyOut would both include this 2000.
      await transactions.createTransferPair(
        amount: 2000,
        dateTime: now,
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        categoryId: 'transfer',
      );

      await container.read(transactionsStreamProvider.future);

      final cashFlow = container.read(cashFlowThisMonthProvider);
      expect(cashFlow.moneyIn, 5000);
      expect(cashFlow.moneyOut, 0);
    });

    test('excludes a transaction marked excludeFromCalculations from both moneyIn and moneyOut', () async {
      final now = DateTime.now();
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 10000,
        colorValue: 0xFF000000,
      );

      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 5000,
        dateTime: now,
        accountId: account.id,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 800,
        dateTime: now,
        accountId: account.id,
        categoryId: 'reimbursable',
        excludeFromCalculations: true,
      );

      await container.read(transactionsStreamProvider.future);

      final cashFlow = container.read(cashFlowThisMonthProvider);
      expect(cashFlow.moneyIn, 5000);
      expect(cashFlow.moneyOut, 0, reason: 'excluded expense must not count toward Money Out');
    });

    test('a transaction assigned to next month via accountingMonth is excluded from this month\'s cash flow', () async {
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      final accounts = container.read(accountRepositoryProvider);
      final account = await accounts.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 10000,
        colorValue: 0xFF000000,
      );

      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 700,
        dateTime: now,
        accountId: account.id,
        categoryId: 'advance-payment',
        accountingMonth: nextMonth,
      );

      await container.read(transactionsStreamProvider.future);

      final cashFlow = container.read(cashFlowThisMonthProvider);
      expect(cashFlow.moneyOut, 0, reason: 'reassigned to next month — must not count toward this month');
    });
  });
}
