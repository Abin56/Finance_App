import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/lending/data/loan_advance_payment_repository.dart';
import 'package:finance_app/features/lending/data/loan_repository.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_interest.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'test-uid';

/// REGRESSION (reversal-architecture audit): reproduces and then guards
/// against the danger scenario — calling the generic
/// `TransactionRepository.softDeleteTransaction`/`restoreTransaction`
/// directly on a loan/EMI-linked `Transaction` reverses the account balance
/// but leaves the linked `Installment.amountPaid`/`InstallmentPayment`
/// untouched, desyncing loan state from account state. Both platforms must
/// block this and direct callers to `LoanAdvancePaymentRepository.
/// reversePayment` instead.
void main() {
  late FakeFirebaseFirestore firestore;
  late AccountRepository accountRepository;
  late LoanRepository loanRepository;
  late LoanAdvancePaymentRepository advanceRepository;
  late TransactionRepository transactionRepository;

  setUp(() {
    firestore = FakeFirebaseFirestore();

    final accountCollection = firestore
        .collection('users')
        .doc(_uid)
        .collection('accounts')
        .withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    accountRepository = AccountRepository(accountCollection);

    final scheduleCollection = firestore
        .collection('users')
        .doc(_uid)
        .collection('paymentSchedules')
        .withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    final loanCollection = firestore
        .collection('users')
        .doc(_uid)
        .collection('loans')
        .withConverter<Loan>(
          fromFirestore: Loan.fromFirestore,
          toFirestore: (l, _) => l.toFirestore(),
        );
    InstallmentRepository installmentRepositoryFor(String scheduleId) {
      final collection = firestore
          .collection('users')
          .doc(_uid)
          .collection('paymentSchedules')
          .doc(scheduleId)
          .collection('installments')
          .withConverter<Installment>(
            fromFirestore: Installment.fromFirestore,
            toFirestore: (i, _) => i.toFirestore(),
          );
      return InstallmentRepository(collection);
    }

    loanRepository = LoanRepository(
      loanCollection,
      PaymentScheduleRepository(scheduleCollection),
      installmentRepositoryFor,
    );
    advanceRepository = LoanAdvancePaymentRepository(firestore: firestore, uid: _uid);

    final txnCollection = firestore
        .collection('users')
        .doc(_uid)
        .collection('transactions')
        .withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    transactionRepository = TransactionRepository(txnCollection, accountRepository);
  });

  Future<List<Installment>> installmentsFor(Loan loan) async {
    final snapshot = await firestore
        .collection('users')
        .doc(_uid)
        .collection('paymentSchedules')
        .doc(loan.scheduleId)
        .collection('installments')
        .where('deletedAt', isNull: true)
        .get();
    return snapshot.docs.map((d) => Installment.fromFirestore(d, null)).toList();
  }

  test(
    'softDeleteTransaction throws LoanPaymentTransactionRestrictedError for a loan-linked '
    'transaction, and does NOT reverse the account balance (no partial effect)',
    () async {
      final account = await accountRepository.createAccount(
        name: 'Wallet',
        type: AccountType.bank,
        openingBalance: 100000,
        colorValue: 0,
      );
      final loan = await loanRepository.createLoan(
        loanAmount: 12000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.installment,
        direction: LoanDirection.taken,
        institutionName: 'Bank',
        category: LoanCategory.institutional,
        interest: const LoanInterest(type: InterestType.reducingBalance, ratePercent: 12, period: InterestPeriod.yearly),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
      );
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      final result = await advanceRepository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: account.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'guard-1',
      );

      final txn = (await transactionRepository.getByKey(result.transactionId))!;

      await expectLater(
        transactionRepository.softDeleteTransaction(txn),
        throwsA(isA<LoanPaymentTransactionRestrictedError>()),
      );

      // No partial effect — balance unchanged, installment still correctly paid.
      final account2 = await accountRepository.getByKey(account.id);
      expect(account2!.currentBalance, 100000 - firstDue);
      final refreshedInstallments = await installmentsFor(loan);
      expect(refreshedInstallments.first.amountPaid, firstDue);
    },
  );

  test('restoreTransaction throws LoanPaymentTransactionRestrictedError for a loan-linked transaction', () async {
    final account = await accountRepository.createAccount(
      name: 'Wallet',
      type: AccountType.bank,
      openingBalance: 100000,
      colorValue: 0,
    );
    final loan = await loanRepository.createLoan(
      loanAmount: 12000,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.installment,
      direction: LoanDirection.taken,
      institutionName: 'Bank',
      category: LoanCategory.institutional,
      interest: const LoanInterest(type: InterestType.reducingBalance, ratePercent: 12, period: InterestPeriod.yearly),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 12,
    );
    final installments = await installmentsFor(loan);
    final firstDue = installments.first.amountDue;

    final result = await advanceRepository.record(
      loan: loan,
      scheduleInstallments: installments,
      accountId: account.id,
      amount: firstDue,
      date: DateTime(2026, 2, 1),
      idempotencyKey: 'guard-2',
    );
    final txn = (await transactionRepository.getByKey(result.transactionId))!;

    await expectLater(
      transactionRepository.restoreTransaction(txn),
      throwsA(isA<LoanPaymentTransactionRestrictedError>()),
    );
  });

  test('the correct path — reversePayment — is unaffected by the guard and works as expected', () async {
    final account = await accountRepository.createAccount(
      name: 'Wallet',
      type: AccountType.bank,
      openingBalance: 100000,
      colorValue: 0,
    );
    final loan = await loanRepository.createLoan(
      loanAmount: 12000,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.installment,
      direction: LoanDirection.taken,
      institutionName: 'Bank',
      category: LoanCategory.institutional,
      interest: const LoanInterest(type: InterestType.reducingBalance, ratePercent: 12, period: InterestPeriod.yearly),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 12,
    );
    final installments = await installmentsFor(loan);
    final firstDue = installments.first.amountDue;

    final result = await advanceRepository.record(
      loan: loan,
      scheduleInstallments: installments,
      accountId: account.id,
      amount: firstDue,
      date: DateTime(2026, 2, 1),
      idempotencyKey: 'guard-3',
    );

    final reversal = await advanceRepository.reversePayment(
      loan: loan,
      transactionId: result.transactionId,
      paymentIds: result.paymentIds,
      installmentIds: result.installmentIds,
      reversalIdempotencyKey: 'guard-3-reversal',
    );
    expect(reversal.alreadyReversed, isFalse);

    final account2 = await accountRepository.getByKey(account.id);
    expect(account2!.currentBalance, 100000);
    final refreshedInstallments = await installmentsFor(loan);
    expect(refreshedInstallments.first.amountPaid, 0);
  });

  test('ordinary (non-loan) transactions are completely unaffected by the guard', () async {
    final account = await accountRepository.createAccount(
      name: 'Wallet',
      type: AccountType.bank,
      openingBalance: 1000,
      colorValue: 0,
    );
    final txn = await transactionRepository.createTransaction(
      type: TransactionType.expense,
      amount: 100,
      dateTime: DateTime(2026, 1, 1),
      accountId: account.id,
      categoryId: 'cat1',
    );
    await transactionRepository.softDeleteTransaction(txn);
    final account2 = await accountRepository.getByKey(account.id);
    expect(account2!.currentBalance, 1000);
  });
}
