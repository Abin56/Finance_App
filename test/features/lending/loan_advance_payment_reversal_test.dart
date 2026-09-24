import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
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
import 'package:finance_app/features/lending/domain/loan_reamortization_event.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
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
      direction: LoanDirection.taken,
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

  Future<Transaction?> getTransaction(String transactionId) async {
    final snap = await firestore
        .collection('users')
        .doc(_uid)
        .collection('transactions')
        .doc(transactionId)
        .get();
    final data = snap.data();
    if (data == null) return null;
    return Transaction.fromFirestore(snap, null);
  }

  Future<InstallmentPayment?> getPayment(
    Loan loan,
    String installmentId,
    String paymentId,
  ) async {
    final snap = await firestore
        .collection('users')
        .doc(_uid)
        .collection('paymentSchedules')
        .doc(loan.scheduleId)
        .collection('installments')
        .doc(installmentId)
        .collection('payments')
        .doc(paymentId)
        .get();
    final data = snap.data();
    if (data == null) return null;
    return InstallmentPayment.fromFirestore(snap, null);
  }

  Future<LoanReamortizationEvent?> getLatestEvent(Loan loan) async {
    final snap = await firestore
        .collection('users')
        .doc(_uid)
        .collection('loans')
        .doc(loan.id)
        .collection('reamortizationEvents')
        .get();
    if (snap.docs.isEmpty) return null;
    return LoanReamortizationEvent.fromFirestore(snap.docs.first, null);
  }

  group('1. Regular EMI payment reversal', () {
    test('restores installment amountPaid, deletes payment, deletes Transaction, restores account balance', () async {
      final acct = await account(openingBalance: 100000);
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1), // on/after due date -> regularEmi
        idempotencyKey: 'regular-1',
      );

      final reversal = await repository.reversePayment(
        loan: loan,
        transactionId: result.transactionId,
        paymentIds: result.paymentIds,
        installmentIds: result.installmentIds,
        reversalIdempotencyKey: 'reversal-1',
      );

      expect(reversal.alreadyReversed, isFalse);

      final refreshedInstallments = await installmentsFor(loan);
      expect(refreshedInstallments.first.amountPaid, 0);

      final txn = await getTransaction(result.transactionId);
      expect(txn!.isDeleted, isTrue);

      final payment = await getPayment(loan, result.installmentIds.first, result.paymentIds.first);
      expect(payment!.isDeleted, isTrue);

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000);
    });
  });

  group('2. Partial installment payment reversal', () {
    test('reversing a partial payment restores exactly the partial amount, not the full amountDue', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue / 3,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'partial-1',
      );

      final afterPayment = await installmentsFor(loan);
      expect(afterPayment.first.amountPaid, closeTo(firstDue / 3, 0.01));

      await repository.reversePayment(
        loan: loan,
        transactionId: result.transactionId,
        paymentIds: result.paymentIds,
        installmentIds: result.installmentIds,
        reversalIdempotencyKey: 'reversal-partial',
      );

      final afterReversal = await installmentsFor(loan);
      expect(afterReversal.first.amountPaid, 0);

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000);
    });
  });

  group('3. Advance EMI payment reversal', () {
    test('reverses an early (advance) payment the same way as a regular one', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2025, 12, 20), // before due date -> advanceEmi
        idempotencyKey: 'advance-1',
      );
      expect(result.overallAllocationType.name, 'advanceEmi');

      await repository.reversePayment(
        loan: loan,
        transactionId: result.transactionId,
        paymentIds: result.paymentIds,
        installmentIds: result.installmentIds,
        reversalIdempotencyKey: 'reversal-advance',
      );

      final refreshed = await installmentsFor(loan);
      expect(refreshed.first.amountPaid, 0);
      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000);
    });
  });

  group('4. One logical payment spanning multiple installments', () {
    test('reversal undoes ALL portions together, not just one', () async {
      final acct = await account();
      final loan = await installmentLoan(installmentCount: 12);
      final installments = await installmentsFor(loan);
      final firstDue = installments[0].amountDue;
      final secondDue = installments[1].amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue + secondDue,
        date: DateTime(2026, 1, 15),
        idempotencyKey: 'multi-1',
        includeUpcomingInstallments: true,
      );
      expect(result.paymentIds.length, 2);

      await repository.reversePayment(
        loan: loan,
        transactionId: result.transactionId,
        paymentIds: result.paymentIds,
        installmentIds: result.installmentIds,
        reversalIdempotencyKey: 'reversal-multi',
      );

      final refreshed = await installmentsFor(loan);
      expect(refreshed.firstWhere((i) => i.sequenceNumber == 1).amountPaid, 0);
      expect(refreshed.firstWhere((i) => i.sequenceNumber == 2).amountPaid, 0);

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000);
    });
  });

  group('5. Principal-prepayment reversal — schedule restoration', () {
    test(
      'restores the original tail, retires the regenerated tail, reverts loanAmount-derived '
      'state, and marks the event reversed — never leaves both tails active',
      () async {
        final acct = await account();
        final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
        final installments = await installmentsFor(loan);
        final firstDue = installments[0].amountDue;
        final originalTailIds = installments.skip(1).map((i) => i.id).toSet();

        final result = await repository.record(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: firstDue + 5000,
          date: DateTime(2026, 1, 15),
          idempotencyKey: 'prepay-rev-1',
        );
        expect(result.overallAllocationType.name, 'principalPrepayment');
        expect(result.reamortization.runtimeType.toString(), contains('Solved'));

        final afterPrepay = await installmentsFor(loan);
        final regeneratedTailIds = afterPrepay
            .where((i) => i.sequenceNumber > 1)
            .map((i) => i.id)
            .toSet();
        // Confirm the tail was actually regenerated (new ids, not the originals).
        expect(regeneratedTailIds.intersection(originalTailIds), isEmpty);

        final reversal = await repository.reversePayment(
          loan: loan,
          transactionId: result.transactionId,
          paymentIds: result.paymentIds,
          installmentIds: result.installmentIds,
          overflowPaymentId: result.overflowPaymentId,
          overflowInstallmentId: result.overflowInstallmentId,
          reversalIdempotencyKey: 'reversal-prepay-1',
        );

        expect(reversal.scheduleRestored, isTrue);

        final afterReversal = await installmentsFor(loan);
        final afterReversalIds = afterReversal.map((i) => i.id).toSet();
        // Original tail restored, regenerated tail retired — no mix, no duplication.
        expect(afterReversalIds.intersection(originalTailIds), originalTailIds);
        expect(afterReversalIds.intersection(regeneratedTailIds), isEmpty);
        expect(afterReversal.length, 12);

        final refreshedLoan = await loanRepository.getByKey(loan.id);
        expect(refreshedLoan!.installmentCount, 12);

        final event = await getLatestEvent(loan);
        expect(event!.reversed, isTrue);
        expect(event.reversedAt, isNotNull);
        expect(event.reversalId, 'reversal-prepay-1');

        final refreshedAccount = await accountRepository.getByKey(acct.id);
        expect(refreshedAccount!.currentBalance, 100000);
      },
    );
  });

  group('6. Retry / idempotent reversal', () {
    test('reversing the same transaction twice does not double-move the account balance', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'retry-rev-1',
      );

      final first = await repository.reversePayment(
        loan: loan,
        transactionId: result.transactionId,
        paymentIds: result.paymentIds,
        installmentIds: result.installmentIds,
        reversalIdempotencyKey: 'reversal-retry-a',
      );
      expect(first.alreadyReversed, isFalse);

      final second = await repository.reversePayment(
        loan: loan,
        transactionId: result.transactionId,
        paymentIds: result.paymentIds,
        installmentIds: result.installmentIds,
        reversalIdempotencyKey: 'reversal-retry-b', // even a DIFFERENT key must be a no-op
      );
      expect(second.alreadyReversed, isTrue);

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000); // not 100000 + firstDue
    });
  });

  group('7. Concurrent reversal attempts', () {
    test('two sequential-stale-snapshot reversal calls do not double-restore the balance', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);
      final firstDue = installments.first.amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'concurrent-rev-1',
      );

      // Same shape as the documented fake_cloud_firestore concurrency-test
      // convention used elsewhere in this suite: both calls race against the
      // same starting state; correctness is that the SECOND one detects the
      // Transaction is already gone and no-ops, not that true parallelism is
      // exercised (that's proven on Web against the real emulator).
      await Future.wait([
        repository.reversePayment(
          loan: loan,
          transactionId: result.transactionId,
          paymentIds: result.paymentIds,
          installmentIds: result.installmentIds,
          reversalIdempotencyKey: 'reversal-concurrent-a',
        ),
        repository.reversePayment(
          loan: loan,
          transactionId: result.transactionId,
          paymentIds: result.paymentIds,
          installmentIds: result.installmentIds,
          reversalIdempotencyKey: 'reversal-concurrent-b',
        ),
      ]);

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000);
    });
  });

  group('8. Reversal with stale caller-supplied Loan state', () {
    test('a stale in-memory Loan object does not corrupt the reversal — financial state comes from fresh reads', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);
      final firstDue = installments[0].amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue + 5000,
        date: DateTime(2026, 1, 15),
        idempotencyKey: 'stale-rev-1',
      );

      // Simulate a concurrent loanAmount edit behind the stale `loan` object's back.
      final rawLoanDoc = firestore.collection('users').doc(_uid).collection('loans').doc(loan.id);
      final currentData = (await rawLoanDoc.get()).data()!;
      currentData['loanAmount'] = 20000;
      await rawLoanDoc.set(currentData);

      final reversal = await repository.reversePayment(
        loan: loan, // still holds the ORIGINAL loanAmount: 12000 in memory
        transactionId: result.transactionId,
        paymentIds: result.paymentIds,
        installmentIds: result.installmentIds,
        overflowPaymentId: result.overflowPaymentId,
        overflowInstallmentId: result.overflowInstallmentId,
        reversalIdempotencyKey: 'reversal-stale-1',
      );

      expect(reversal.scheduleRestored, isTrue);

      // The write-back must not regress the concurrently-updated loanAmount.
      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 20000);
    });
  });

  group('9. Legacy re-amortization event without new reversal metadata', () {
    test('a legacy event with no retired/generated installment ids is not safely reversible', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);
      final firstDue = installments[0].amountDue;

      final result = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue + 5000,
        date: DateTime(2026, 1, 15),
        idempotencyKey: 'legacy-1',
      );

      // Simulate a legacy event by wiping the new tracking fields directly in Firestore.
      final eventsSnap = await firestore
          .collection('users')
          .doc(_uid)
          .collection('loans')
          .doc(loan.id)
          .collection('reamortizationEvents')
          .get();
      final eventDoc = eventsSnap.docs.first;
      final eventData = eventDoc.data();
      eventData['retiredInstallmentIds'] = <String>[];
      eventData['generatedInstallmentIds'] = <String>[];
      await eventDoc.reference.set(eventData);

      await expectLater(
        repository.reversePayment(
          loan: loan,
          transactionId: result.transactionId,
          paymentIds: result.paymentIds,
          installmentIds: result.installmentIds,
          overflowPaymentId: result.overflowPaymentId,
          overflowInstallmentId: result.overflowInstallmentId,
          reversalIdempotencyKey: 'reversal-legacy-1',
        ),
        throwsA(isA<PaymentReversalBlockedException>()),
      );

      // Confirm nothing was mutated — the block happens before any write.
      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000 - (firstDue + 5000));
    });
  });

  group('10. Reversal blocked by later dependent activity', () {
    test('reversing payment A after a later payment B on the same loan is blocked', () async {
      final acct = await account();
      final loan = await installmentLoan(installmentCount: 12);
      final installments = await installmentsFor(loan);
      final firstDue = installments[0].amountDue;

      final resultA = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'chrono-a',
      );

      final afterA = await installmentsFor(loan);
      await repository.record(
        loan: loan,
        scheduleInstallments: afterA,
        accountId: acct.id,
        amount: afterA[1].amountDue,
        date: DateTime(2026, 3, 1),
        idempotencyKey: 'chrono-b',
      );

      await expectLater(
        repository.reversePayment(
          loan: loan,
          transactionId: resultA.transactionId,
          paymentIds: resultA.paymentIds,
          installmentIds: resultA.installmentIds,
          reversalIdempotencyKey: 'reversal-chrono-a',
        ),
        throwsA(isA<PaymentReversalBlockedException>()),
      );
    });

    test('reversing the LATEST payment (B) when an earlier one (A) exists is allowed', () async {
      final acct = await account();
      final loan = await installmentLoan(installmentCount: 12);
      final installments = await installmentsFor(loan);
      final firstDue = installments[0].amountDue;

      await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'chrono2-a',
      );

      final afterA = await installmentsFor(loan);
      final resultB = await repository.record(
        loan: loan,
        scheduleInstallments: afterA,
        accountId: acct.id,
        amount: afterA[1].amountDue,
        date: DateTime(2026, 3, 1),
        idempotencyKey: 'chrono2-b',
      );

      final reversal = await repository.reversePayment(
        loan: loan,
        transactionId: resultB.transactionId,
        paymentIds: resultB.paymentIds,
        installmentIds: resultB.installmentIds,
        reversalIdempotencyKey: 'reversal-chrono2-b',
      );
      expect(reversal.alreadyReversed, isFalse);
    });

    test(
      'reversing a principal prepayment is blocked once a payment lands on its regenerated tail',
      () async {
        final acct = await account();
        final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
        final installments = await installmentsFor(loan);
        final firstDue = installments[0].amountDue;

        final prepayResult = await repository.record(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: firstDue + 5000,
          date: DateTime(2026, 1, 15),
          idempotencyKey: 'chrono3-prepay',
        );

        final afterPrepay = await installmentsFor(loan);
        final regeneratedFirst = afterPrepay.firstWhere((i) => i.sequenceNumber == 2);
        await repository.record(
          loan: loan,
          scheduleInstallments: afterPrepay,
          accountId: acct.id,
          amount: regeneratedFirst.amountDue,
          date: DateTime(2026, 2, 1),
          idempotencyKey: 'chrono3-followup',
        );

        await expectLater(
          repository.reversePayment(
            loan: loan,
            transactionId: prepayResult.transactionId,
            paymentIds: prepayResult.paymentIds,
            installmentIds: prepayResult.installmentIds,
            overflowPaymentId: prepayResult.overflowPaymentId,
            overflowInstallmentId: prepayResult.overflowInstallmentId,
            reversalIdempotencyKey: 'reversal-chrono3',
          ),
          throwsA(isA<PaymentReversalBlockedException>()),
        );
      },
    );
  });
}
