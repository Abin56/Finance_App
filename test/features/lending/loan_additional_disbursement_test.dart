import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
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
import 'package:finance_app/features/lending/domain/loan_additional_disbursement.dart';
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
    return snapshot.docs.map((d) => Installment.fromFirestore(d, null)).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
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
    LoanDirection direction = LoanDirection.taken,
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

  Future<LoanAdditionalDisbursement?> getDisbursement(
    Loan loan,
    String disbursementId,
  ) async {
    final snap = await firestore
        .collection('users')
        .doc(_uid)
        .collection('loans')
        .doc(loan.id)
        .collection('additionalDisbursements')
        .doc(disbursementId)
        .get();
    final data = snap.data();
    if (data == null) return null;
    return LoanAdditionalDisbursement.fromFirestore(snap, null);
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

  group('1. Given-loan disbursement', () {
    test('more money given increases loanAmount and is an EXPENSE from the account', () async {
      final acct = await account(openingBalance: 100000);
      final loan = await installmentLoan(
        direction: LoanDirection.given,
        loanAmount: 12000,
      );
      final installments = await installmentsFor(loan);

      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'given-1',
      );

      expect(result.alreadyRecorded, isFalse);

      final txn = await getTransaction(result.transactionId);
      expect(txn!.type.name, 'expense');
      expect(txn.amount, 2000);
      expect(txn.loanId, loan.id);
      expect(txn.paymentAllocationType?.name, 'additionalDisbursement');

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 98000);

      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 14000);
    });
  });

  group('2. Taken-loan disbursement', () {
    test('more money borrowed increases loanAmount and is INCOME into the account', () async {
      final acct = await account(openingBalance: 100000);
      final loan = await installmentLoan(
        direction: LoanDirection.taken,
        loanAmount: 12000,
      );
      final installments = await installmentsFor(loan);

      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'taken-1',
      );

      final txn = await getTransaction(result.transactionId);
      expect(txn!.type.name, 'income');

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 102000);

      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 14000);
    });
  });

  group('3. Zero-interest loan', () {
    test('HoldTenurePolicy solves via direct division across the held-constant tenure', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, interest: null);
      final installments = await installmentsFor(loan);

      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 1200,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'zero-1',
      );

      expect(result.reamortization?.runtimeType.toString(), contains('Solved'));
      final solved = result.reamortization as dynamic;
      expect(solved.remainingInstallmentCount, 12); // held constant
      expect(solved.installmentAmount, closeTo(1100, 0.01)); // (12000+1200)/12

      final refreshed = await installmentsFor(loan);
      expect(refreshed.length, 12);
      for (final i in refreshed) {
        expect(i.amountDue, closeTo(1100, 0.01));
      }
    });
  });

  group('4. Normal reducing-balance loan', () {
    test('installment amount increases, tenure held constant, principal grows by exactly the disbursement', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);
      final originalAmount = installments.first.amountDue;

      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 5000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'normal-1',
      );

      expect(result.reamortization?.runtimeType.toString(), contains('Solved'));
      final refreshed = await installmentsFor(loan);
      expect(refreshed.length, 12); // tenure held constant
      expect(refreshed.first.amountDue, greaterThan(originalAmount));

      final event = await getLatestEvent(loan);
      expect(event!.triggerType.name, 'additionalDisbursement');
      expect(event.principalAfter - event.principalBefore, closeTo(5000, 0.01));
      expect(event.installmentCountBefore, event.installmentCountAfter);
    });
  });

  group('5. Disbursement after several EMIs', () {
    test('already-settled installments are left untouched; only the unpaid tail reshapes', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);
      final firstDue = installments[0].amountDue;

      final paymentResult = await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: firstDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'emi-before-disb',
      );
      expect(paymentResult.overallAllocationType.name, 'regularEmi');

      final afterEmi = await installmentsFor(loan);
      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: afterEmi,
        accountId: acct.id,
        amount: 3000,
        date: DateTime(2026, 2, 5),
        idempotencyKey: 'disb-after-emi',
      );

      final refreshed = await installmentsFor(loan);
      final firstInstallment = refreshed.firstWhere((i) => i.sequenceNumber == 1);
      expect(firstInstallment.amountPaid, closeTo(firstDue, 0.01)); // untouched
      expect(refreshed.length, 12);
      expect(result.reamortization?.runtimeType.toString(), contains('Solved'));
    });
  });

  group('6. Disbursement after principal prepayment', () {
    test('composes correctly: prepayment reduces tenure, then disbursement holds THAT tenure and grows principal', () async {
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
        idempotencyKey: 'prepay-before-disb',
      );
      expect(prepayResult.overallAllocationType.name, 'principalPrepayment');
      final afterPrepay = await installmentsFor(loan);
      final tenureAfterPrepay = afterPrepay.length;

      final disbResult = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: afterPrepay,
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 20),
        idempotencyKey: 'disb-after-prepay',
      );

      final afterDisb = await installmentsFor(loan);
      expect(afterDisb.length, tenureAfterPrepay); // holds the ALREADY-reduced tenure
      expect(disbResult.reamortization?.runtimeType.toString(), contains('Solved'));
    });
  });

  group('7. Repeated/idempotent request', () {
    test('retrying with the same idempotencyKey does not double-apply', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);

      final first = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'retry-disb-1',
      );
      expect(first.alreadyRecorded, isFalse);

      final second = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: await installmentsFor(loan),
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'retry-disb-1',
      );
      expect(second.alreadyRecorded, isTrue);

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      // Default `installmentLoan()` is `LoanDirection.taken` -> income.
      expect(refreshedAccount!.currentBalance, 102000); // not double-credited

      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 14000); // not double-added
    });
  });

  group('8. Concurrent/sequential-stale-state request', () {
    test('two calls against the same starting snapshot do not corrupt loanAmount (no lost update)', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000);
      final installments = await installmentsFor(loan);

      // Sequential (not Future.wait) stale-snapshot composition — mirrors
      // `loan_advance_payment_repository_test.dart`'s "7. Concurrent
      // payments" convention: `fake_cloud_firestore` has no true
      // concurrency, so `Future.wait` isn't a reliable way to exercise it.
      // Both calls read the SAME stale `installments`/`loan` snapshot;
      // correctness is that the second call's fresh re-read inside its own
      // `runTransaction` doesn't clobber the first's already-applied
      // effect. Genuine parallelism is proven on Web against the real
      // emulator.
      final snapshotA = installments;
      await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: snapshotA,
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'concurrent-disb-a',
      );

      final snapshotB = installments; // still the ORIGINAL stale list
      await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: snapshotB,
        accountId: acct.id,
        amount: 3000,
        date: DateTime(2026, 1, 11),
        idempotencyKey: 'concurrent-disb-b',
      );

      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 17000); // both applied, no lost update
    });
  });

  group('9. Stale caller Loan', () {
    test('financial state comes from fresh reads, not the stale in-memory Loan', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);

      // Simulate a concurrent loanAmount edit behind the stale `loan` object's back.
      final rawLoanDoc = firestore.collection('users').doc(_uid).collection('loans').doc(loan.id);
      final currentData = (await rawLoanDoc.get()).data()!;
      currentData['loanAmount'] = 20000;
      await rawLoanDoc.set(currentData);

      final result = await repository.recordAdditionalDisbursement(
        loan: loan, // still holds loanAmount: 12000 in memory (stale)
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 5000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'stale-disb-1',
      );

      expect(result.alreadyRecorded, isFalse);

      // FRESH Firestore loanAmount (20000) + 5000 = 25000, NOT stale 12000 + 5000 = 17000.
      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 25000);
    });
  });

  group('10. Reversal', () {
    test('reverses loanAmount, Transaction, account balance, and restores the pre-disbursement schedule', () async {
      final acct = await account(openingBalance: 100000);
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);
      final originalTailIds = installments.map((i) => i.id).toSet();

      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 5000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'reversal-disb-1',
      );
      expect(result.reamortization?.runtimeType.toString(), contains('Solved'));

      final afterDisb = await installmentsFor(loan);
      final regeneratedIds = afterDisb.map((i) => i.id).toSet();
      expect(regeneratedIds.intersection(originalTailIds), isEmpty);

      final reversal = await repository.reverseAdditionalDisbursement(
        loan: loan,
        transactionId: result.transactionId,
        disbursementId: result.disbursementId,
        reversalIdempotencyKey: 'reversal-disb-key-1',
      );

      expect(reversal.alreadyReversed, isFalse);
      expect(reversal.scheduleRestored, isTrue);

      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 12000); // exactly reverted

      final refreshedAccount = await accountRepository.getByKey(acct.id);
      expect(refreshedAccount!.currentBalance, 100000); // exactly reverted

      final afterReversal = await installmentsFor(loan);
      final afterReversalIds = afterReversal.map((i) => i.id).toSet();
      expect(afterReversalIds, originalTailIds); // exact original tail restored

      final txn = await getTransaction(result.transactionId);
      expect(txn!.isDeleted, isTrue);

      final disbursement = await getDisbursement(loan, result.disbursementId);
      expect(disbursement!.isDeleted, isTrue);
    });

    test('reversing twice is idempotent — no double-move of loanAmount or balance', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000);
      final installments = await installmentsFor(loan);

      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'idempotent-disb-1',
      );

      final first = await repository.reverseAdditionalDisbursement(
        loan: loan,
        transactionId: result.transactionId,
        disbursementId: result.disbursementId,
        reversalIdempotencyKey: 'idem-rev-a',
      );
      expect(first.alreadyReversed, isFalse);

      final second = await repository.reverseAdditionalDisbursement(
        loan: loan,
        transactionId: result.transactionId,
        disbursementId: result.disbursementId,
        reversalIdempotencyKey: 'idem-rev-b',
      );
      expect(second.alreadyReversed, isTrue);

      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 12000);
    });
  });

  group('11. Blocked reversal after dependent payment', () {
    test('reversing a disbursement is blocked once a payment lands on its regenerated tail', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);

      final disbResult = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 5000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'blocked-disb-1',
      );

      final afterDisb = await installmentsFor(loan);
      await repository.record(
        loan: loan,
        scheduleInstallments: afterDisb,
        accountId: acct.id,
        amount: afterDisb.first.amountDue,
        date: DateTime(2026, 2, 1),
        idempotencyKey: 'followup-after-disb',
      );

      await expectLater(
        repository.reverseAdditionalDisbursement(
          loan: loan,
          transactionId: disbResult.transactionId,
          disbursementId: disbResult.disbursementId,
          reversalIdempotencyKey: 'blocked-rev-1',
        ),
        throwsA(isA<PaymentReversalBlockedException>()),
      );
    });

    test('reversing a disbursement is blocked once another disbursement follows it', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);

      final firstDisb = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 3000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'chained-disb-a',
      );

      final afterFirst = await installmentsFor(loan);
      await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: afterFirst,
        accountId: acct.id,
        amount: 2000,
        date: DateTime(2026, 1, 15),
        idempotencyKey: 'chained-disb-b',
      );

      await expectLater(
        repository.reverseAdditionalDisbursement(
          loan: loan,
          transactionId: firstDisb.transactionId,
          disbursementId: firstDisb.disbursementId,
          reversalIdempotencyKey: 'blocked-rev-chained',
        ),
        throwsA(isA<PaymentReversalBlockedException>()),
      );
    });
  });

  group('12. Legacy Firestore document', () {
    test('a legacy re-amortization event with no reversal-tracking fields is not safely reversible', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 12000, installmentCount: 12);
      final installments = await installmentsFor(loan);

      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 5000,
        date: DateTime(2026, 1, 10),
        idempotencyKey: 'legacy-disb-1',
      );

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
        repository.reverseAdditionalDisbursement(
          loan: loan,
          transactionId: result.transactionId,
          disbursementId: result.disbursementId,
          reversalIdempotencyKey: 'legacy-rev-1',
        ),
        throwsA(isA<PaymentReversalBlockedException>()),
      );
    });
  });

  group('13. Unsolvable HoldTenurePolicy case', () {
    test('a loan with zero remaining untouched installments records the disbursement but skips re-amortization', () async {
      final acct = await account();
      final loan = await installmentLoan(loanAmount: 1000, installmentCount: 1);
      final installments = await installmentsFor(loan);

      await repository.record(
        loan: loan,
        scheduleInstallments: installments,
        accountId: acct.id,
        amount: 1000,
        date: DateTime(2026, 1, 5),
        idempotencyKey: 'full-payoff',
      );

      final afterPayoff = await installmentsFor(loan);
      final result = await repository.recordAdditionalDisbursement(
        loan: loan,
        scheduleInstallments: afterPayoff,
        accountId: acct.id,
        amount: 500,
        date: DateTime(2026, 1, 6),
        idempotencyKey: 'disb-nothing-to-reamortize',
      );

      // Disbursement still correctly recorded — just no schedule to reshape.
      expect(result.alreadyRecorded, isFalse);
      expect(result.reamortization, isNull);

      final refreshedLoan = await loanRepository.getByKey(loan.id);
      expect(refreshedLoan!.loanAmount, 1500);
    });
  });

  group('14. Validation', () {
    test('rejects a disbursement on a one-time loan', () async {
      final acct = await account();
      final loan = await loanRepository.createLoan(
        loanAmount: 5000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        category: LoanCategory.institutional,
        institutionName: 'Bank',
        dueDate: DateTime(2026, 2, 1),
      );

      await expectLater(
        repository.recordAdditionalDisbursement(
          loan: loan,
          scheduleInstallments: const [],
          accountId: acct.id,
          amount: 100,
          date: DateTime(2026, 1, 15),
          idempotencyKey: 'onetime-disb',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a non-positive amount', () async {
      final acct = await account();
      final loan = await installmentLoan();
      final installments = await installmentsFor(loan);

      await expectLater(
        repository.recordAdditionalDisbursement(
          loan: loan,
          scheduleInstallments: installments,
          accountId: acct.id,
          amount: 0,
          date: DateTime(2026, 1, 10),
          idempotencyKey: 'zero-amount-disb',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
