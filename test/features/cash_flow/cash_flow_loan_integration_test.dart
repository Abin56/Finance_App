import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/cash_flow/domain/cash_flow_period.dart';
import 'package:finance_app/features/cash_flow/domain/money_flow_line.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 8 — "Integrate Loans Correctly With Cash Flow": Loans never post
/// their own `Transaction` (see `loan_repository.dart`/
/// `installment_payment_repository.dart`), so these tests exercise Cash
/// Flow's own `moneyIn`/`moneyOutLinesForRangeFamilyProvider` reaching
/// directly into `Installment`/`InstallmentPayment`, exactly like it already
/// does for EMI/Bill — never a parallel calculation, and never a new
/// Transaction record for a loan event.
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

  void setCustomRange(DateTime start, DateTime end) {
    container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(DateRange(start, end));
  }

  void setPreset(CashFlowPreset preset) {
    container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.preset(preset);
  }

  Future<String> createAccountOfType(AccountType type) async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: type.name,
      type: type,
      openingBalance: 10000,
      colorValue: 0xFF000000,
    );
    return account.id;
  }

  Future<String> createPerson(String name) async {
    final people = container.read(personRepositoryProvider);
    final person = await people.createPerson(name: name, avatarColorValue: 0xFF000000, openingBalance: 0);
    return person.id;
  }

  /// Creates a loan and awaits its schedule's installments being readable.
  Future<({String scheduleId, List<String> installmentIds})> createLoanAndAwaitInstallments({
    required String personId,
    required LoanDirection direction,
    required double loanAmount,
    required DateTime loanDate,
    LoanRepaymentType repaymentType = LoanRepaymentType.oneTime,
    DateTime? dueDate,
    ScheduleType? installmentFrequency,
    int? installmentCount,
  }) async {
    final loans = container.read(loanRepositoryProvider);
    final loan = await loans.createLoan(
      personId: personId,
      direction: direction,
      loanAmount: loanAmount,
      loanDate: loanDate,
      repaymentType: repaymentType,
      dueDate: dueDate,
      installmentFrequency: installmentFrequency,
      installmentCount: installmentCount,
    );
    await container.read(loansStreamProvider.future);
    final sub = container.listen(installmentsStreamProvider(loan.scheduleId), (_, _) {});
    addTearDown(sub.close);
    await container.read(installmentsStreamProvider(loan.scheduleId).future);
    final installments = container.read(installmentsStreamProvider(loan.scheduleId)).value!;
    return (scheduleId: loan.scheduleId, installmentIds: installments.map((i) => i.id).toList());
  }

  /// Records one payment against an installment and awaits the payment
  /// stream so the cash flow providers (which `.watch` it) see it
  /// synchronously on the next `container.read`.
  Future<void> payInstallment({
    required String scheduleId,
    required String installmentId,
    required double amount,
    required DateTime date,
  }) async {
    final key = (scheduleId: scheduleId, installmentId: installmentId);
    final sub = container.listen(installmentPaymentsStreamProvider(key), (_, _) {});
    addTearDown(sub.close);
    final installments = container.read(installmentsStreamProvider(scheduleId)).value!;
    final installment = installments.firstWhere((i) => i.id == installmentId);
    await container.read(installmentPaymentRepositoryProvider(key)).recordPayment(installment, amount: amount, date: date);
    await container.read(installmentsStreamProvider(scheduleId).future);
    await container.read(installmentPaymentsStreamProvider(key).future);
  }

  group('Money borrowed / lent (loan direction)', () {
    test('a taken loan\'s installment payment is Money Out, not Money In', () async {
      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 3333,
        date: DateTime(2026, 9, 5),
      );

      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));

      final summary = container.read(cashFlowForRangeProvider);
      expect(summary.moneyOut, 3333);
      expect(summary.moneyIn, 0);

      final outLines = container.read(moneyOutLinesForRangeProvider);
      expect(outLines.length, 1);
      expect(outLines.single.kind, MoneyFlowKind.loan);
      expect(outLines.single.amount, 3333);
    });

    test('a given loan\'s installment payment (repayment received) is Money In, not Money Out', () async {
      final personId = await createPerson('Friend');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.given,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 5000,
        date: DateTime(2026, 9, 5),
      );

      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));

      final summary = container.read(cashFlowForRangeProvider);
      expect(summary.moneyIn, 5000);
      expect(summary.moneyOut, 0);

      final inLines = container.read(moneyInLinesForRangeProvider);
      expect(inLines.length, 1);
      expect(inLines.single.kind, MoneyFlowKind.loan);
      expect(inLines.single.amount, 5000);
    });
  });

  group('EMI-style installment payments on a loan', () {
    test('a full installment payment counts once, exactly the paid amount', () async {
      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 10000,
        loanDate: DateTime(2026, 9, 1),
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.first,
        amount: 2500,
        date: DateTime(2026, 9, 1),
      );

      setCustomRange(DateTime(2026, 9, 1), DateTime(2026, 9, 1, 23, 59, 59, 999));

      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines.length, 1);
      expect(lines.single.amount, 2500);
    });

    test('a partial installment payment counts only the amount actually paid', () async {
      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 10000,
        loanDate: DateTime(2026, 9, 1),
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.first,
        amount: 1000, // partial: installment is due 2500
        date: DateTime(2026, 9, 1),
      );

      setCustomRange(DateTime(2026, 9, 1), DateTime(2026, 9, 1, 23, 59, 59, 999));

      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines.length, 1);
      expect(lines.single.amount, 1000);
    });

    test('a lump-sum payment across multiple installments contributes one line per actual payment, summing correctly', () async {
      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 10000,
        loanDate: DateTime(2026, 9, 1),
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      // Simulate a lump-sum settlement fanning out oldest-due-first across
      // two installments (mirrors `InstallmentSettlement.plan`'s output —
      // this test only verifies Cash Flow sums whatever real payments
      // landed, not the allocation algorithm itself).
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds[0],
        amount: 2500,
        date: DateTime(2026, 9, 10),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds[1],
        amount: 2500,
        date: DateTime(2026, 9, 10),
      );

      setCustomRange(DateTime(2026, 9, 10), DateTime(2026, 9, 10, 23, 59, 59, 999));

      final summary = container.read(cashFlowForRangeProvider);
      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines.length, 2);
      expect(lines.fold(0.0, (sum, l) => sum + l.amount), 5000);
      expect(summary.moneyOut, 5000);
    });
  });

  group('Repayment received', () {
    test('a given loan repayment appears in Money In on its actual payment date, not the due date', () async {
      final personId = await createPerson('Friend');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.given,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 1), // due 1 Sep
      );
      // Paid late, on 5 Sep — Cash Flow must use the payment date, not the
      // due date, per the task's date-range contract.
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 5000,
        date: DateTime(2026, 9, 5),
      );

      // A range covering only the due date (1 Sep) must NOT show it.
      setCustomRange(DateTime(2026, 9, 1), DateTime(2026, 9, 1, 23, 59, 59, 999));
      expect(container.read(moneyInLinesForRangeProvider), isEmpty);

      // A range covering the actual payment date (5 Sep) must show it.
      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));
      final lines = container.read(moneyInLinesForRangeProvider);
      expect(lines.length, 1);
      expect(lines.single.amount, 5000);
    });
  });

  group('Credit card / bank sources do not interfere with loan lines', () {
    test('a credit-card expense and a loan EMI payment both count once each, no double counting', () async {
      final cardId = await createAccountOfType(AccountType.card);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 800,
        dateTime: DateTime(2026, 9, 5),
        accountId: cardId,
        categoryId: 'shopping',
      );
      await container.read(transactionsStreamProvider.future);

      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 3333,
        date: DateTime(2026, 9, 5),
      );

      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));

      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines.length, 2);
      expect(lines.where((l) => l.kind == MoneyFlowKind.expense).length, 1);
      expect(lines.where((l) => l.kind == MoneyFlowKind.loan).length, 1);
      expect(container.read(cashFlowForRangeProvider).moneyOut, 800 + 3333);
    });

    test('a bank expense and a loan EMI payment both count once each, no double counting', () async {
      final bankId = await createAccountOfType(AccountType.bank);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 400,
        dateTime: DateTime(2026, 9, 5),
        accountId: bankId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 3333,
        date: DateTime(2026, 9, 5),
      );

      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));

      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines.length, 2);
      expect(lines.fold(0.0, (sum, l) => sum + l.amount), 400 + 3333);
      expect(container.read(cashFlowForRangeProvider).moneyOut, 400 + 3333);
    });
  });

  group('Date ranges', () {
    test('one-day range: a loan payment on 5 Sep appears in a 5 Sep -> 5 Sep range', () async {
      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 3333,
        date: DateTime(2026, 9, 5),
      );

      // Exactly "5 Sep -> 5 Sep" padded to end-of-day, the same convention
      // every other Cash Flow custom-range test in this suite uses — the
      // provider itself does inclusive isBefore/isAfter comparison, so a
      // same-day payment must not disappear from a one-day range.
      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));

      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines.length, 1);
      expect(lines.single.amount, 3333);
    });

    test('monthly range: a loan payment counts under the This Month preset', () async {
      final now = DateTime.now();
      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 65000,
        loanDate: DateTime(now.year, now.month, 1),
        dueDate: now,
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 3333,
        date: now,
      );

      setPreset(CashFlowPreset.thisMonth);
      expect(container.read(cashFlowForRangeProvider).moneyOut, 3333);
    });

    test('custom range: a loan payment outside the picked window is excluded', () async {
      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 3333,
        date: DateTime(2026, 9, 5),
      );

      // A custom range that doesn't include 5 Sep must exclude the payment.
      setCustomRange(DateTime(2026, 9, 10), DateTime(2026, 9, 20, 23, 59, 59, 999));
      expect(container.read(moneyOutLinesForRangeProvider), isEmpty);
      expect(container.read(cashFlowForRangeProvider).moneyOut, 0);

      // Widening the custom range to include it brings it back.
      setCustomRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59, 999));
      expect(container.read(moneyOutLinesForRangeProvider).length, 1);
      expect(container.read(cashFlowForRangeProvider).moneyOut, 3333);
    });
  });

  group('Double-counting prevention', () {
    test('Money Out detail total always equals cashFlowForRangeProvider.moneyOut with a loan present', () async {
      final bankId = await createAccountOfType(AccountType.bank);
      final transactions = container.read(transactionRepositoryProvider);
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 9, 5),
        accountId: bankId,
        categoryId: 'food',
      );
      await container.read(transactionsStreamProvider.future);

      final personId = await createPerson('Bank');
      final result = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 65000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: result.scheduleId,
        installmentId: result.installmentIds.single,
        amount: 3333,
        date: DateTime(2026, 9, 5),
      );

      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));

      final summary = container.read(cashFlowForRangeProvider);
      final lines = container.read(moneyOutLinesForRangeProvider);
      expect(lines.fold(0.0, (sum, l) => sum + l.amount), summary.moneyOut);
      // Reading it a second time must not double-apply/re-fold anything.
      expect(container.read(cashFlowForRangeProvider).moneyOut, summary.moneyOut);
    });

    test('a taken loan\'s payment never appears in Money In, and a given loan\'s payment never appears in Money Out', () async {
      final personId = await createPerson('Both');
      final taken = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.taken,
        loanAmount: 1000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      final given = await createLoanAndAwaitInstallments(
        personId: personId,
        direction: LoanDirection.given,
        loanAmount: 2000,
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: taken.scheduleId,
        installmentId: taken.installmentIds.single,
        amount: 500,
        date: DateTime(2026, 9, 5),
      );
      await payInstallment(
        scheduleId: given.scheduleId,
        installmentId: given.installmentIds.single,
        amount: 700,
        date: DateTime(2026, 9, 5),
      );

      setCustomRange(DateTime(2026, 9, 5), DateTime(2026, 9, 5, 23, 59, 59, 999));

      final outLines = container.read(moneyOutLinesForRangeProvider);
      final inLines = container.read(moneyInLinesForRangeProvider);

      // Exactly one loan line in each direction — never both loans in both
      // lists, and never the same payment counted twice anywhere.
      expect(outLines.where((l) => l.kind == MoneyFlowKind.loan).length, 1);
      expect(outLines.where((l) => l.kind == MoneyFlowKind.loan).single.amount, 500);
      expect(inLines.where((l) => l.kind == MoneyFlowKind.loan).length, 1);
      expect(inLines.where((l) => l.kind == MoneyFlowKind.loan).single.amount, 700);

      expect(container.read(cashFlowForRangeProvider).moneyOut, 500);
      expect(container.read(cashFlowForRangeProvider).moneyIn, 700);
    });
  });
}
