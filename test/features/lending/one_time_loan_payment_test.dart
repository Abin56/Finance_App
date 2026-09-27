import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/lending/data/loan_advance_payment_repository.dart';
import 'package:finance_app/features/lending/data/loan_repository.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 / D — one-time Loan payments. `LoanDetailScreen`'s "Pay" and
/// "Settle" buttons (`RecordLoanPaymentSheet` /
/// `RecordLoanLumpSumSettlementSheet`) call exactly
/// `LoanAdvancePaymentRepository.record(loan, scheduleInstallments: <the
/// loan's live installments>, ...)`. For a one-time loan that call used to
/// throw, so a one-time loan could never be paid from the app.
const _uid = 'test-uid';

void main() {
  late FakeFirebaseFirestore firestore;
  late LoanAdvancePaymentRepository repository;
  late LoanRepository loanRepository;
  late AccountRepository accountRepository;

  CollectionReference<Map<String, dynamic>> col(String name) =>
      firestore.collection('users').doc(_uid).collection(name);

  CollectionReference<Installment> installmentsCol(String scheduleId) =>
      col('paymentSchedules')
          .doc(scheduleId)
          .collection('installments')
          .withConverter<Installment>(
            fromFirestore: Installment.fromFirestore,
            toFirestore: (i, _) => i.toFirestore(),
          );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    accountRepository = AccountRepository(
      col('accounts').withConverter<Account>(
        fromFirestore: Account.fromFirestore,
        toFirestore: (a, _) => a.toFirestore(),
      ),
    );
    loanRepository = LoanRepository(
      col('loans').withConverter<Loan>(
        fromFirestore: Loan.fromFirestore,
        toFirestore: (l, _) => l.toFirestore(),
      ),
      PaymentScheduleRepository(
        col('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        ),
      ),
      (scheduleId) => InstallmentRepository(installmentsCol(scheduleId)),
    );
    repository = LoanAdvancePaymentRepository(firestore: firestore, uid: _uid);
  });

  Future<List<Installment>> liveInstallments(Loan loan) async {
    final snap = await installmentsCol(
      loan.scheduleId,
    ).where('deletedAt', isNull: true).get();
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<List<Transaction>> transactionsFor(Loan loan) async {
    final snap = await col(
      'transactions',
    ).where('loanId', isEqualTo: loan.id).get();
    return snap.docs.map((d) => Transaction.fromFirestore(d, null)).toList();
  }

  Future<Loan> oneTimeLoan(LoanDirection direction) =>
      loanRepository.createLoan(
        loanAmount: 20000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        direction: direction,
        institutionName: 'Rahul',
        category: LoanCategory.institutional,
        dueDate: DateTime(2026, 6, 1),
      );

  Future<Account> wallet() => accountRepository.createAccount(
    name: 'Wallet',
    type: AccountType.bank,
    openingBalance: 50000,
    colorValue: 0xFF000000,
  );

  test(
    'borrowed one-time loan: partial payments move the account, write one Transaction each, and reduce what is owed',
    () async {
      final acct = await wallet();
      final loan = await oneTimeLoan(LoanDirection.taken);
      var installments = await liveInstallments(loan);
      expect(
        installments,
        hasLength(1),
        reason:
            'a one-time loan has exactly one installment — no fake schedule',
      );

      await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 5000,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'ot-1',
      );
      installments = await liveInstallments(loan);
      await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 3000,
        date: DateTime(2026, 3, 1),
        idempotencyKey: 'ot-2',
      );

      installments = await liveInstallments(loan);
      expect(installments, hasLength(1));
      expect(installments.single.amountPaid, 8000);
      expect(installments.single.remainingAmount, 12000);
      expect(
        (await accountRepository.getByKey(acct.id))!.currentBalance,
        50000 - 8000,
      );
      final txns = await transactionsFor(loan);
      expect(txns, hasLength(2));
      expect(txns.every((t) => t.type == TransactionType.expense), isTrue);
    },
  );

  test(
    'lent one-time loan: a repayment received credits the account (income)',
    () async {
      final acct = await wallet();
      final loan = await oneTimeLoan(LoanDirection.given);
      await repository.record(
        loan: loan,
        scheduleInstallments: await liveInstallments(loan),
        accountId: acct.id,
        amount: 20000,
        date: DateTime(2026, 6, 1),
        idempotencyKey: 'ot-lent',
      );
      expect(
        (await accountRepository.getByKey(acct.id))!.currentBalance,
        70000,
      );
      expect((await liveInstallments(loan)).single.remainingAmount, 0);
      expect((await transactionsFor(loan)).single.type, TransactionType.income);
    },
  );

  test(
    'retry with the same idempotency key does not move money twice',
    () async {
      final acct = await wallet();
      final loan = await oneTimeLoan(LoanDirection.taken);
      final installments = await liveInstallments(loan);
      for (var i = 0; i < 2; i++) {
        await repository.record(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: 4000,
          date: DateTime(2026, 2, 1),
          idempotencyKey: 'ot-retry',
        );
      }
      expect(
        (await accountRepository.getByKey(acct.id))!.currentBalance,
        46000,
      );
      expect(await transactionsFor(loan), hasLength(1));
    },
  );

  test(
    'paying more than is owed on a one-time loan is refused — there is no schedule to re-plan',
    () async {
      final acct = await wallet();
      final loan = await oneTimeLoan(LoanDirection.taken);
      await expectLater(
        repository.record(
          loan: loan,
          scheduleInstallments: await liveInstallments(loan),
          accountId: acct.id,
          amount: 25000,
          date: DateTime(2026, 2, 1),
          idempotencyKey: 'ot-over',
        ),
        throwsA(isA<AppException>()),
      );
      expect(
        (await accountRepository.getByKey(acct.id))!.currentBalance,
        50000,
      );
      expect(await transactionsFor(loan), isEmpty);
    },
  );

  test('reversal restores the account and what is owed', () async {
    final acct = await wallet();
    final loan = await oneTimeLoan(LoanDirection.taken);
    final result = await repository.record(
      loan: loan,
      scheduleInstallments: await liveInstallments(loan),
      accountId: acct.id,
      amount: 6000,
      date: DateTime(2026, 2, 1),
      idempotencyKey: 'ot-rev',
    );
    await repository.reversePayment(
      loan: loan,
      transactionId: result.transactionId,
      paymentIds: result.paymentIds,
      installmentIds: result.installmentIds,
      reversalIdempotencyKey: 'ot-rev-undo',
    );
    expect((await accountRepository.getByKey(acct.id))!.currentBalance, 50000);
    expect((await liveInstallments(loan)).single.amountPaid, 0);
  });
}
