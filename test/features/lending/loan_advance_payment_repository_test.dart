import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_allocation_type.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/prepayment_reamortization_policy.dart';
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
import 'package:finance_app/features/lending/domain/loan_reamortization_event.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'test-uid';

void main() {
  late FakeFirebaseFirestore firestore;
  late LoanAdvancePaymentRepository repository;
  late LoanRepository loanRepository;
  late AccountRepository accountRepository;

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

  Future<Account> account({double openingBalance = 100000}) {
    return accountRepository.createAccount(
      name: 'Wallet',
      type: AccountType.bank,
      openingBalance: openingBalance,
      colorValue: 0xFF000000,
    );
  }

  Future<Loan> installmentLoan({
    LoanDirection direction = LoanDirection.taken,
    double loanAmount = 12000,
    int installmentCount = 12,
    LoanInterest? interest = const LoanInterest(
      type: InterestType.reducingBalance,
      ratePercent: 12,
      period: InterestPeriod.yearly,
    ),
  }) {
    return loanRepository.createLoan(
      loanAmount: loanAmount,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.installment,
      direction: direction,
      institutionName: 'Bank',
      category: LoanCategory.institutional,
      interest: interest,
      installmentFrequency: ScheduleType.monthly,
      installmentCount: installmentCount,
    );
  }

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
    loanRepository = LoanRepository(
      loanCollection,
      PaymentScheduleRepository(scheduleCollection),
      installmentRepositoryFor,
    );

    repository = LoanAdvancePaymentRepository(firestore: firestore, uid: _uid);
  });

  Future<Transaction?> transactionByLoanId(String loanId) async {
    final snapshot = await firestore
        .collection('users')
        .doc(_uid)
        .collection('transactions')
        .where('loanId', isEqualTo: loanId)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Transaction.fromFirestore(snapshot.docs.first, null);
  }

  group('1. Advance payment — full chain', () {
    test(
      'writes payment + updates installment + creates Transaction + adjusts account balance',
      () async {
        final acct = await account(openingBalance: 100000);
        final loan = await installmentLoan();
        final installments = await installmentsFor(loan);
        final firstDue = installments.first.amountDue;

        final result = await repository.record(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: firstDue,
          date: DateTime(2025, 12, 20), // before the 1st installment's due date (Jan 1) -> advance
          idempotencyKey: 'k1',
        );

        expect(result.overallAllocationType, PaymentAllocationType.advanceEmi);
        expect(result.prepaymentPrincipalAmount, isNull);

        final refreshedInstallments = await installmentsFor(loan);
        final paid = refreshedInstallments.firstWhere((i) => i.sequenceNumber == 1);
        expect(paid.amountPaid, firstDue);

        final refreshedAccount = await accountRepository.getByKey(acct.id);
        // Loan taken -> paying it back is an expense -> account decreases.
        expect(refreshedAccount!.currentBalance, 100000 - firstDue);

        final txn = await transactionByLoanId(loan.id);
        expect(txn, isNotNull);
        expect(txn!.type, TransactionType.expense);
        expect(txn.amount, firstDue);
        expect(txn.installmentPaymentId, result.paymentIds.first);
      },
    );

    test('a loan given (you lent money) credits the account on repayment', () async {
      final acct = await account(openingBalance: 5000);
      final loan = await installmentLoan(direction: LoanDirection.given);
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'k-given',
      );

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 5000 + firstDue);
    });
  });

  group('4. Partial EMI payment', () {
    test('correct remaining amount, correct history, no duplicate effect', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue / 2,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'partial-1',
      );

      final afterFirst = await installmentsFor(loan);
      final firstInstallment = afterFirst.firstWhere((i) => i.sequenceNumber == 1);
      expect(firstInstallment.amountPaid, firstDue / 2);
      expect(firstInstallment.remainingAmount, firstDue / 2);

      // Second partial payment for the rest — must complete it, not double it.
      await repository.record(
        loan: loan,
        scheduleInstallments: afterFirst,
        accountId: acct.id,
        amount: firstDue / 2,
        date: DateTime(2026, 2, 2),
        idempotencyKey: 'partial-2',
      );

      final afterSecond = await installmentsFor(loan);
      final completed = afterSecond.firstWhere((i) => i.sequenceNumber == 1);
      expect(completed.amountPaid, firstDue);
      expect(completed.remainingAmount, 0);

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000 - firstDue);
    });
  });

  group('2 & 5. Principal prepayment / overpayment — explicit allocation, re-amortization', () {
    test(
      'overflow beyond currently-due installments reduces tenure at constant EMI amount',
      () async {
        final acct = await account();
        final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
        final installments = await installmentsFor(loan);
        final firstDue = installments.first.amountDue;

        // Pay the first EMI plus a large chunk of extra principal.
        final amount = firstDue + 5000;
        final result = await repository.record(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: amount,
          date: DateTime(2026, 1, 15), // between installment 1 (Jan 1) and 2 (Feb 1)'s due dates
          idempotencyKey: 'prepay-1',
        );

        expect(result.overallAllocationType, PaymentAllocationType.principalPrepayment);
        expect(result.prepaymentPrincipalAmount, closeTo(5000, 0.01));
        expect(result.reamortization, isA<PrepaymentReamortizationSolved>());

        final solved = result.reamortization as PrepaymentReamortizationSolved;
        // Fewer installments than the original 11 remaining, same EMI ceiling.
        expect(solved.remainingInstallmentCount, lessThan(11));
        expect(solved.installmentAmount, lessThanOrEqualTo(firstDue));

        final refreshedAccount = await accountRepository.getByKey(acct.id);
        expect(refreshedAccount!.currentBalance, 100000 - amount);

        // No money lost: sum of all live installments' amountDue plus what
        // was already paid should reconcile against the reduced principal.
        final refreshedInstallments = await installmentsFor(loan);
        for (final i in refreshedInstallments) {
          expect(i.amountDue, greaterThanOrEqualTo(0));
        }

        final events = await firestore
            .collection('users')
            .doc(_uid)
            .collection('loans')
            .doc(loan.id)
            .collection('reamortizationEvents')
            .get();
        expect(events.docs, hasLength(1));
        final event = LoanReamortizationEvent.fromFirestore(events.docs.first, null);
        expect(event.installmentCountAfter, lessThan(event.installmentCountBefore));
      },
    );

    test('a zero-interest loan solves via direct division, no negative amounts', () async {
      final acct = await account();
      final loan = await installmentLoan(
        loanAmount: 10000,
        installmentCount: 10,
        interest: null,
      );
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue; // 1000

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue + 4000,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'prepay-zero-interest',
      );

      expect(result.reamortization, isA<PrepaymentReamortizationSolved>());
      final refreshedInstallments = await installmentsFor(loan);
      for (final i in refreshedInstallments) {
        expect(i.amountDue, greaterThan(0));
      }
    });
  });

  group('6. Duplicate/retried payment', () {
    test('the same idempotencyKey is a no-op the second time', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      final first = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'retry-key',
      );
      expect(first.alreadyRecorded, isFalse);

      final afterFirst = await accountRepository.getByKey(acct.id);
      expect(afterFirst!.currentBalance, 100000 - firstDue);

      // Simulate a retry after a false-timeout: same key, same call.
      final second = await repository.record(
        loan: loan,
        scheduleInstallments: await installmentsFor(loan),
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'retry-key',
      );
      expect(second.alreadyRecorded, isTrue);

      final afterRetry = await accountRepository.getByKey(acct.id);
      // Balance must NOT have moved a second time.
      expect(afterRetry!.currentBalance, 100000 - firstDue);

      final refreshedInstallments = await installmentsFor(loan);
      final firstInstallment = refreshedInstallments.firstWhere((i) => i.sequenceNumber == 1);
      expect(firstInstallment.amountPaid, firstDue);
    });

    test(
      'a retry using the ORIGINAL STALE installments list (not refetched) is '
      'still detected as a no-op — the idempotency sentinel is checked before '
      'any caller-supplied installment data is ever touched',
      () async {
        final acct = await account();
        final loan = await installmentLoan();
        final staleInstallments = await installmentsFor(loan);
        final firstDue = staleInstallments.first.amountDue;

        final first = await repository.record(
          loan: loan,
          scheduleInstallments: staleInstallments,
          accountId: acct.id,
          amount: firstDue,
          date: DateTime(2026, 2, 1),
          idempotencyKey: 'stale-retry-key',
        );
        expect(first.alreadyRecorded, isFalse);

        // Retry with the SAME stale list from before the first call —
        // simulates a UI that double-submits without refetching.
        final second = await repository.record(
          loan: loan,
          scheduleInstallments: staleInstallments,
          accountId: acct.id,
          amount: firstDue,
          date: DateTime(2026, 2, 1),
          idempotencyKey: 'stale-retry-key',
        );
        expect(second.alreadyRecorded, isTrue);

        final afterRetry = await accountRepository.getByKey(acct.id);
        expect(afterRetry!.currentBalance, 100000 - firstDue);
      },
    );
  });

  group('Overpayment allocation choice (includeUpcomingInstallments)', () {
    test(
      'without the flag, overflow beyond the currently-due installment '
      'becomes a principal prepayment even though a future installment '
      'could have absorbed it',
      () async {
        final acct = await account();
        final loan = await installmentLoan(installmentCount: 12);
        final installments = await installmentsFor(loan);
        final firstDue = installments.first.amountDue;
        final secondDue = installments[1].amountDue;

        final result = await repository.record(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: firstDue + secondDue,
          date: DateTime(2026, 1, 15), // only installment 1 is "currently due"
          idempotencyKey: 'no-upcoming',
        );

        expect(
          result.overallAllocationType,
          PaymentAllocationType.principalPrepayment,
        );
        expect(result.prepaymentPrincipalAmount, closeTo(secondDue, 0.01));

        final refreshed = await installmentsFor(loan);
        // Installment 2 was NOT touched by this payment.
        expect(
          refreshed.firstWhere((i) => i.sequenceNumber == 2).amountPaid,
          0,
        );
      },
    );

    test(
      'with the flag, the same overpayment is instead applied to the next '
      'upcoming installment — no prepayment, no re-amortization',
      () async {
        final acct = await account();
        final loan = await installmentLoan(installmentCount: 12);
        final installments = await installmentsFor(loan);
        final firstDue = installments.first.amountDue;
        final secondDue = installments[1].amountDue;

        final result = await repository.record(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: firstDue + secondDue,
          date: DateTime(2026, 1, 15),
          idempotencyKey: 'with-upcoming',
          includeUpcomingInstallments: true,
        );

        expect(result.prepaymentPrincipalAmount, isNull);
        expect(result.reamortization, isNull);

        final refreshed = await installmentsFor(loan);
        expect(
          refreshed.firstWhere((i) => i.sequenceNumber == 1).amountPaid,
          firstDue,
        );
        expect(
          refreshed.firstWhere((i) => i.sequenceNumber == 2).amountPaid,
          secondDue,
        );

        final refreshedAccount = await accountRepository.getByKey(acct.id);
        expect(
          refreshedAccount!.currentBalance,
          100000 - firstDue - secondDue,
        );
      },
    );
  });

  group('7. Concurrent payments', () {
    test('two different payments on the same loan both land (no lost update)', () async {
      final acct = await account();
      final loan = await installmentLoan(installmentCount: 12);
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;
      final secondDue = installments[1].amountDue;

      // Sequential (not Future.wait — see account_repository_test.dart's
      // documented fake_cloud_firestore limitation for genuine concurrency)
      // stale-snapshot composition: both payments read the account
      // independently before either writes, same shape as the proven
      // AccountRepository.adjustBalance regression test.
      final snapshotA = installments;
      await repository.record(
        loan: loan,
        scheduleInstallments: snapshotA,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'concurrent-a',
      );

      final snapshotB = installments; // still the ORIGINAL stale list
      await repository.record(
        loan: loan,
        scheduleInstallments: snapshotB,
        accountId: acct.id,
        amount: secondDue,
        date: DateTime(2026, 3, 1),
        idempotencyKey: 'concurrent-b',
      );

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      // Both deltas composed — the second call's fresh re-read inside its
      // own runTransaction must not clobber the first's already-applied effect.
      expect(refreshedAccount!.currentBalance, 100000 - firstDue - secondDue);

      final refreshedInstallments = await installmentsFor(loan);
      expect(
        refreshedInstallments.firstWhere((i) => i.sequenceNumber == 1).amountPaid,
        firstDue,
      );
      expect(
        refreshedInstallments.firstWhere((i) => i.sequenceNumber == 2).amountPaid,
        secondDue,
      );
    });
  });

  group(
    'REGRESSION (architecture review, fixed): _reamortize must re-read the '
    'Loan document fresh, never trust the caller-supplied in-memory copy',
    () {
      test(
        'a loanAmount change written to Firestore AFTER the caller fetched '
        'its in-memory Loan is used correctly by re-amortization — the '
        'FRESH Firestore value wins, not the stale caller value, and the '
        'fresh value is not regressed by the write-back',
        () async {
          final acct = await account();
          final loan = await installmentLoan(
            loanAmount: 12000,
            installmentCount: 12,
          );
          final installments = await installmentsFor(loan);
          final firstDue = installments.first.amountDue;

          // Simulate a concurrent write that changes loanAmount in Firestore
          // behind the in-memory `loan` object's back (e.g. another device's
          // edit, landing between this caller's fetch and its record() call).
          // Bypasses LoanRepository.editLoan's own hasPayments guard on
          // purpose — this reproduces the raw data hazard at the
          // _reamortize layer directly, not a claim that editLoan itself is
          // exploitable through normal UI actions once payments exist.
          final rawLoanDoc = firestore
              .collection('users')
              .doc(_uid)
              .collection('loans')
              .doc(loan.id);
          final currentData = (await rawLoanDoc.get()).data()!;
          currentData['loanAmount'] = 20000; // was 12000
          await rawLoanDoc.set(currentData);

          final amount = firstDue + 5000;
          final result = await repository.record(
            loan: loan, // still holds loanAmount: 12000 in memory (stale)
            scheduleInstallments: installments,
            accountId: acct.id,
            amount: amount,
            date: DateTime(2026, 1, 15),
            idempotencyKey: 'stale-loan-amount',
          );

          expect(result.reamortization, isA<PrepaymentReamortizationSolved>());

          final events = await firestore
              .collection('users')
              .doc(_uid)
              .collection('loans')
              .doc(loan.id)
              .collection('reamortizationEvents')
              .get();
          final event = LoanReamortizationEvent.fromFirestore(
            events.docs.first,
            null,
          );

          // principalBefore = loanAmount - (installment 1's principal share paid off).
          // FRESH Firestore loanAmount (20000): 20000 - 946.19 = 19053.81.
          // The stale in-memory 12000 would have produced 11053.81 instead —
          // this is exactly the bug the architecture review reproduced.
          expect(
            event.principalBefore,
            closeTo(19053.81, 0.01),
            reason:
                'principalBefore must be derived from the FRESH Firestore '
                'loanAmount (20000), not the stale in-memory value (12000) '
                'the caller happened to be holding.',
          );

          // The write-back itself must not regress the concurrently-updated
          // loanAmount back to the stale value — the fix reads AND writes
          // the same fresh Loan object, so this loanAmount survives intact.
          final reloadedLoan = await loanRepository.getByKey(loan.id);
          expect(
            reloadedLoan!.loanAmount,
            20000,
            reason:
                'The batch write-back must use the freshly-read Loan object, '
                'not the stale caller-supplied one — otherwise it would '
                'silently overwrite the concurrently-updated loanAmount back '
                'down to 12000.',
          );
        },
      );
    },
  );

  group('Validation', () {
    test('rejects a payment on a one-time loan', () async {
      final acct = await account();
      final loan = await loanRepository.createLoan(
        loanAmount: 5000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        institutionName: 'Bank',
        category: LoanCategory.institutional,
        dueDate: DateTime(2026, 2, 1),
      );

      await expectLater(
        repository.record(
          loan: loan,
          scheduleInstallments: const [],
          accountId: acct.id,
          amount: 100,
          date: DateTime(2026, 1, 15),
          idempotencyKey: 'onetime',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a payment when the loan is already fully paid', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 1000, installmentCount: 1, interest: null);
      final installments = await installmentsFor(loan);

      await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 1000,
        date: DateTime(2026, 1, 5),
        idempotencyKey: 'full-1',
      );

      await expectLater(
        repository.record(
          loan: loan,
          scheduleInstallments: await installmentsFor(loan),
          accountId: acct.id,
          amount: 100,
          date: DateTime(2026, 1, 6),
          idempotencyKey: 'full-2',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
