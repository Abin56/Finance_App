import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_occurrence_providers.dart';
import 'package:finance_app/features/cash_flow/domain/cash_flow_period.dart';
import 'package:finance_app/features/cash_flow/domain/money_flow_line.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the bug fix (Money In/Out leaking the whole month into a
/// one/two-day custom range, because the old `cashFlowForRangeProvider`
/// bucketed by `Transaction.effectiveMonth` instead of the real date) and
/// for the new Money In/Out drill-down line providers
/// (`moneyInLinesForRangeProvider`/`moneyOutLinesForRangeProvider`), which
/// must always sum to exactly `cashFlowForRangeProvider`'s totals.
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

  group('Bug fix — one/two-day ranges no longer leak the whole month', () {
    test('one-day range: Sep 1 -> Sep 1 includes only Sep 1\'s income/expense', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);

      // Sep 1: income 500, expense 200
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 9, 1, 10),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 200,
        dateTime: DateTime(2026, 9, 1, 12),
        accountId: accountId,
        categoryId: 'food',
      );
      // Sep 2: income 1000, expense 300
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1000,
        dateTime: DateTime(2026, 9, 2, 10),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 9, 2, 12),
        accountId: accountId,
        categoryId: 'food',
      );
      // Sep 3: income 2000, expense 400
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 2000,
        dateTime: DateTime(2026, 9, 3, 10),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 400,
        dateTime: DateTime(2026, 9, 3, 12),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1, 0, 0, 0), DateTime(2026, 9, 1, 23, 59, 59, 999));

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyIn, 500, reason: 'must not include Sep 2/3\'s income');
      expect(cashFlow.moneyOut, 200, reason: 'must not include Sep 2/3\'s expense');
      expect(cashFlow.net, 300);
    });

    test('two-day range: Sep 1 -> Sep 2 includes only those two days', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 9, 1, 10),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 200,
        dateTime: DateTime(2026, 9, 1, 12),
        accountId: accountId,
        categoryId: 'food',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1000,
        dateTime: DateTime(2026, 9, 2, 10),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 9, 2, 12),
        accountId: accountId,
        categoryId: 'food',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 2000,
        dateTime: DateTime(2026, 9, 3, 10),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 400,
        dateTime: DateTime(2026, 9, 3, 12),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1, 0, 0, 0), DateTime(2026, 9, 2, 23, 59, 59, 999));

      final cashFlow = container.read(cashFlowForRangeProvider);
      expect(cashFlow.moneyIn, 1500, reason: '500 (Sep 1) + 1000 (Sep 2), not Sep 3\'s 2000');
      expect(cashFlow.moneyOut, 500, reason: '200 (Sep 1) + 300 (Sep 2), not Sep 3\'s 400');
    });

    test('one-week range only includes that week', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 700,
        dateTime: DateTime(2026, 9, 5),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 9999,
        dateTime: DateTime(2026, 9, 20),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7, 23, 59, 59));

      expect(container.read(cashFlowForRangeProvider).moneyIn, 700);
    });

    test('one-month range still works (whole-month preset)', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 5000,
        dateTime: DateTime(2026, 9, 15),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1234,
        dateTime: DateTime(2026, 10, 1),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59));

      expect(container.read(cashFlowForRangeProvider).moneyIn, 5000);
    });

    test('multi-month range spans August through September', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 300,
        dateTime: DateTime(2026, 8, 20),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 400,
        dateTime: DateTime(2026, 9, 5),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 8, 1), DateTime(2026, 9, 30, 23, 59, 59));

      expect(container.read(cashFlowForRangeProvider).moneyIn, 700);
    });

    test('a transaction exactly on the start date is included', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 9, 1, 0, 0, 1),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1, 0, 0, 0), DateTime(2026, 9, 1, 23, 59, 59, 999));
      expect(container.read(cashFlowForRangeProvider).moneyIn, 500);
    });

    test('a transaction exactly on the end date is included', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 9, 2, 23, 59, 0),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1, 0, 0, 0), DateTime(2026, 9, 2, 23, 59, 59, 999));
      expect(container.read(cashFlowForRangeProvider).moneyIn, 500);
    });

    test('a transaction immediately before the range is excluded', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 8, 31, 23, 59, 59),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1, 0, 0, 0), DateTime(2026, 9, 1, 23, 59, 59, 999));
      expect(container.read(cashFlowForRangeProvider).moneyIn, 0);
    });

    test('a transaction immediately after the range is excluded', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 9, 2, 0, 0, 0),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1, 0, 0, 0), DateTime(2026, 9, 1, 23, 59, 59, 999));
      expect(container.read(cashFlowForRangeProvider).moneyIn, 0);
    });
  });

  group('Money In / Money Out detail lines match the summary total', () {
    test('Money In detail total equals cashFlowForRangeProvider.moneyIn', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 3000,
        dateTime: DateTime(2026, 9, 2),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 1000,
        dateTime: DateTime(2026, 9, 1),
        accountId: accountId,
        categoryId: 'deposit',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 2, 23, 59, 59, 999));

      final summary = container.read(cashFlowForRangeProvider);
      final lines = container.read(moneyInLinesForRangeProvider);
      final linesTotal = lines.fold(0.0, (sum, l) => sum + l.amount);
      expect(linesTotal, summary.moneyIn);
      expect(linesTotal, 4000);
    });

    test('Money Out detail total equals cashFlowForRangeProvider.moneyOut, across expense + EMI + Loan + Bill', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 2),
        accountId: accountId,
        categoryId: 'food',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 1000,
        dateTime: DateTime(2026, 9, 2),
        accountId: accountId,
        categoryId: 'shopping',
      );

      // Both EMI and Loan are paid PARTIALLY (not in full) — a fully-paid
      // single-installment EMI/Loan flips to `EmiStatus.closed`/
      // `LoanStatus.closed` and drops out of `activeEmisProvider`/
      // `activeLoansProvider`, which both `moneyOutLinesForRangeProvider`
      // and the pre-existing `emiPaidThisMonthProvider`/
      // `_loanPaidThisMonthProvider` iterate over — a pre-existing
      // limitation this test isn't meant to exercise.
      final emis = container.read(emiRepositoryProvider);
      await emis.createEmi(
        name: 'Bike EMI',
        principalAmount: 2000,
        startDate: DateTime(2026, 9, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 1,
      );
      await container.read(emisStreamProvider.future);
      final emi = container.read(emisStreamProvider).value!.single;
      final emiInstallmentsSub = container.listen(installmentsStreamProvider(emi.scheduleId), (_, _) {});
      addTearDown(emiInstallmentsSub.close);
      await container.read(installmentsStreamProvider(emi.scheduleId).future);
      final emiInstallment = container.read(installmentsStreamProvider(emi.scheduleId)).value!.single;
      final emiPaymentKey = (scheduleId: emi.scheduleId, installmentId: emiInstallment.id);
      await container
          .read(installmentPaymentRepositoryProvider(emiPaymentKey))
          .recordPayment(emiInstallment, amount: 1500, date: DateTime(2026, 9, 1));
      await container.read(installmentsStreamProvider(emi.scheduleId).future);

      final people = container.read(personRepositoryProvider);
      final person = await people.createPerson(name: 'Alex', avatarColorValue: 0xFF000000, openingBalance: 0);

      final loans = container.read(loanRepositoryProvider);
      final loan = await loans.createLoan(
        personId: person.id,
        loanAmount: 1000,
        loanDate: DateTime(2026, 9, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 9, 1),
      );
      await container.read(loansStreamProvider.future);
      final loanInstallmentsSub = container.listen(installmentsStreamProvider(loan.scheduleId), (_, _) {});
      addTearDown(loanInstallmentsSub.close);
      await container.read(installmentsStreamProvider(loan.scheduleId).future);
      final loanInstallment = container.read(installmentsStreamProvider(loan.scheduleId)).value!.single;
      final loanPaymentKey = (scheduleId: loan.scheduleId, installmentId: loanInstallment.id);
      await container
          .read(installmentPaymentRepositoryProvider(loanPaymentKey))
          .recordPayment(loanInstallment, amount: 700, date: DateTime(2026, 9, 1));
      await container.read(installmentsStreamProvider(loan.scheduleId).future);

      final bills = container.read(billRepositoryProvider);
      final bill = await bills.createBill(
        name: 'Netflix',
        amount: 300,
        dueDate: DateTime(2026, 9, 1),
        recurrence: BillRecurrence.oneTime,
      );
      await container.read(billsStreamProvider.future);
      final billSub = container.listen(materializeBillOccurrenceProvider(bill.id), (_, _) {});
      addTearDown(billSub.close);
      await container.read(materializeBillOccurrenceProvider(bill.id).future);
      final occurrence = container.read(currentBillOccurrenceProvider(bill.id))!;
      final paymentRepo = container.read(paymentRepositoryProvider(bill.id));
      await paymentRepo.recordPayment(bill, occurrence, amount: 300, date: DateTime(2026, 9, 1));
      await container.read(billOccurrencesStreamProvider(bill.id).future);

      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 2, 23, 59, 59, 999));

      final summary = container.read(cashFlowForRangeProvider);
      final lines = container.read(moneyOutLinesForRangeProvider);
      final linesTotal = lines.fold(0.0, (sum, l) => sum + l.amount);
      expect(linesTotal, summary.moneyOut);
      expect(linesTotal, 500 + 1000 + 1500 + 700 + 300);

      // Different outgoing sources correctly identified.
      expect(lines.where((l) => l.kind == MoneyFlowKind.expense).length, 2);
      expect(lines.where((l) => l.kind == MoneyFlowKind.emi).length, 1);
      expect(lines.where((l) => l.kind == MoneyFlowKind.loan).length, 1);
      expect(lines.where((l) => l.kind == MoneyFlowKind.bill).length, 1);
    });

    test('only selected-range items appear in Money Out lines; out-of-range items do not', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 1),
        accountId: accountId,
        categoryId: 'food',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 9999,
        dateTime: DateTime(2026, 9, 10),
        accountId: accountId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 1, 23, 59, 59, 999));

      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines, hasLength(1));
      expect(lines.single.amount, 500);
      expect(lines.any((l) => l.amount == 9999), isFalse);
    });

    test('Money In lines correct date/amount/category, empty state when nothing in range', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 3000,
        dateTime: DateTime(2026, 9, 2, 9),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 2), DateTime(2026, 9, 2, 23, 59, 59, 999));
      final lines = container.read(moneyInLinesForRangeProvider);
      expect(lines, hasLength(1));
      expect(lines.single.amount, 3000);
      expect(lines.single.date.day, 2);
      expect(lines.single.date.month, 9);

      setRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));
      expect(container.read(moneyInLinesForRangeProvider), isEmpty, reason: 'empty state must have no lines');
      expect(container.read(cashFlowForRangeProvider).moneyIn, 0);
    });

    test('Money Out lines empty state when nothing spent in range', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 9, 1),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 1, 23, 59, 59, 999));
      expect(container.read(moneyOutLinesForRangeProvider), isEmpty);
    });

    test('changing the range changes the drill-down lines, never a stale previous range', () async {
      final accountId = await createAccount(container);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 100,
        dateTime: DateTime(2026, 9, 1),
        accountId: accountId,
        categoryId: 'salary',
      );
      await transactions.createTransaction(
        type: TransactionType.income,
        amount: 900,
        dateTime: DateTime(2026, 9, 12),
        accountId: accountId,
        categoryId: 'salary',
      );
      await container.read(transactionsStreamProvider.future);

      setRange(DateTime(2026, 9, 1), DateTime(2026, 9, 2, 23, 59, 59, 999));
      expect(container.read(moneyInLinesForRangeProvider).fold(0.0, (s, l) => s + l.amount), 100);

      setRange(DateTime(2026, 9, 10), DateTime(2026, 9, 15, 23, 59, 59, 999));
      expect(container.read(moneyInLinesForRangeProvider).fold(0.0, (s, l) => s + l.amount), 900);
    });
  });
}
