// Origination reversal + Loan delete safety. Same scenarios as flowfi-web's
// real-emulator suite (tests/integration/loan-origination-reversal.test.ts).
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:finance_app/core/data/firestore_crud_repository.dart';
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
import 'package:finance_app/features/lending/domain/loan_origination.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/atomic_fake_firestore.dart';

const _uid = 'test-uid';
final _loanDate = DateTime(2026, 1, 10);

void main() {
  late AtomicFakeFirestore firestore;
  late LoanRepository loans;
  late AccountRepository accounts;
  late LoanAdvancePaymentRepository payments;

  CollectionReference<Map<String, dynamic>> col(String name) =>
      firestore.collection('users').doc(_uid).collection(name);
  CollectionReference<Loan> loansCol() => col('loans').withConverter<Loan>(
    fromFirestore: Loan.fromFirestore,
    toFirestore: (l, _) => l.toFirestore(),
  );
  CollectionReference<Installment> installmentsCol(String scheduleId) =>
      col('paymentSchedules')
          .doc(scheduleId)
          .collection('installments')
          .withConverter<Installment>(
            fromFirestore: Installment.fromFirestore,
            toFirestore: (i, _) => i.toFirestore(),
          );

  setUp(() {
    firestore = AtomicFakeFirestore();
    accounts = AccountRepository(
      col('accounts').withConverter<Account>(
        fromFirestore: Account.fromFirestore,
        toFirestore: (a, _) => a.toFirestore(),
      ),
    );
    loans = LoanRepository(
      loansCol(),
      PaymentScheduleRepository(
        col('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        ),
      ),
      (scheduleId) => InstallmentRepository(installmentsCol(scheduleId)),
    );
    payments = LoanAdvancePaymentRepository(firestore: firestore, uid: _uid);
  });

  Future<Account> bank([String name = 'HDFC']) => accounts.createAccount(
    name: name,
    type: AccountType.bank,
    openingBalance: 100000,
    colorValue: 0,
  );
  Future<double> balance(String id) async =>
      (await accounts.getByKey(id))!.currentBalance;
  Future<Loan?> loanDoc(String id) async =>
      (await loansCol().doc(id).get()).data();
  Future<List<Installment>> allInstallments(String scheduleId) async =>
      (await installmentsCol(
          scheduleId,
        ).get()).docs.map((d) => d.data()).toList()
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  Future<List<Installment>> live(String scheduleId) async =>
      (await allInstallments(scheduleId)).where((i) => !i.isDeleted).toList();
  Future<List<Transaction>> loanTxns(String loanId) async =>
      (await col('transactions').where('loanId', isEqualTo: loanId).get()).docs
          .map((d) => Transaction.fromFirestore(d, null))
          .toList();

  /// Net Worth exactly as the app computes it: accounts ± principal of
  /// non-trashed, open Loans.
  Future<double> netWorth() async {
    final accountTotal = (await accounts.getAll()).fold<double>(
      0,
      (total, a) => total + a.currentBalance,
    );
    final open = (await loans.getAll()).where((l) => !l.isClosed);
    final lent = open
        .where((l) => l.direction == LoanDirection.given)
        .fold<double>(0, (total, l) => total + l.loanAmount);
    final borrowed = open
        .where((l) => l.direction == LoanDirection.taken)
        .fold<double>(0, (total, l) => total + l.loanAmount);
    return accountTotal + lent - borrowed;
  }

  Future<AgreementOriginationResult> borrow(String key, String? accountId) =>
      loans.createAgreementWithOrigination(
        idempotencyKey: key,
        name: 'Renovation',
        category: LoanCategory.institutional,
        institutionName: 'HDFC Bank',
        fundingSource: LoanFundingSource.bank,
        direction: LoanDirection.taken,
        loanAmount: 50000,
        loanDate: _loanDate,
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        interest: const LoanInterest(
          type: InterestType.reducingBalance,
          ratePercent: 12,
          period: InterestPeriod.yearly,
        ),
        movementAccountId: accountId,
      );
  Future<AgreementOriginationResult> lend(String key, String? accountId) =>
      loans.createAgreementWithOrigination(
        idempotencyKey: key,
        name: 'Rahul',
        category: LoanCategory.personal,
        personId: 'rahul',
        fundingSource: LoanFundingSource.person,
        direction: LoanDirection.given,
        loanAmount: 25000,
        loanDate: _loanDate,
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 5,
        movementAccountId: accountId,
      );
  Future<AgreementOriginationResult> buy(String key, String? accountId) =>
      loans.createAgreementWithOrigination(
        idempotencyKey: key,
        name: 'Laptop',
        agreementKind: LoanAgreementKind.installmentPurchase,
        category: LoanCategory.institutional,
        institutionName: 'Bajaj',
        fundingSource: LoanFundingSource.financeCompany,
        direction: LoanDirection.taken,
        purchaseAmount: 60000,
        downPayment: 10000,
        loanAmount: 50000,
        loanDate: _loanDate,
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 10,
        movementAccountId: accountId,
      );

  /// What the Loan UIs called before this change: the inherited soft delete.
  Future<void> genericSoftDelete(Loan loan) =>
      FirestoreCrudRepository<Loan>(loansCol()).softDelete(loan);

  Future<void> expectBlocked(
    String key,
    OriginationReversalBlockReason reason,
  ) async {
    await expectLater(
      loans.reverseOrigination(key),
      throwsA(
        isA<OriginationReversalBlockedException>().having(
          (e) => e.reason,
          'reason',
          reason,
        ),
      ),
    );
  }

  group('reproduction — the pre-fix generic trash path corrupts', () {
    test(
      'borrowed: Loan trashed, cash and Transaction stay, Net Worth +50,000',
      () async {
        final hdfc = await bank();
        final before = await netWorth();
        final result = await borrow('repro-borrow-1', hdfc.id);
        await genericSoftDelete(result.loan);
        expect((await loanDoc(result.loan.id))!.isDeleted, isTrue);
        expect(await balance(hdfc.id), 150000);
        expect((await loanTxns(result.loan.id)).single.isDeleted, isFalse);
        expect(await live(result.scheduleId), hasLength(12));
        expect(await netWorth(), before + 50000);
      },
    );

    test('lent: Net Worth −25,000 after trash', () async {
      final sbi = await bank('SBI');
      final before = await netWorth();
      final result = await lend('repro-lend-1', sbi.id);
      await genericSoftDelete(result.loan);
      expect(await balance(sbi.id), 75000);
      expect(await netWorth(), before - 25000);
    });

    test(
      'down payment: the financed liability vanishes, the spend stays',
      () async {
        final hdfc = await bank();
        final before = await netWorth();
        final result = await buy('repro-down-1', hdfc.id);
        expect(await netWorth(), before - 60000);
        await genericSoftDelete(result.loan);
        expect(await balance(hdfc.id), 90000);
        expect(await netWorth(), before - 10000);
      },
    );
  });

  group('trash / permanent delete safety', () {
    test(
      '9 — trashing a Loan with active origination money is refused',
      () async {
        final hdfc = await bank();
        final result = await borrow('trash-block-1', hdfc.id);
        await expectLater(
          loans.softDelete(result.loan),
          throwsA(isA<OriginationDeleteBlockedException>()),
        );
        expect((await loanDoc(result.loan.id))!.isDeleted, isFalse);
        expect(await balance(hdfc.id), 150000);
      },
    );

    test('9b — no-movement and legacy Loans trash/restore as before', () async {
      final result = await borrow('trash-nomove-1', null);
      await loans.softDelete(result.loan);
      await loans.restore((await loanDoc(result.loan.id))!);
      expect((await loanDoc(result.loan.id))!.isDeleted, isFalse);
      final legacy = await loans.createLoan(
        loanAmount: 1000,
        loanDate: _loanDate,
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 2,
        category: LoanCategory.institutional,
        institutionName: 'Axis',
      );
      await loans.softDelete(legacy);
      expect((await loanDoc(legacy.id))!.isDeleted, isTrue);
    });

    test(
      '10 — permanent delete refuses active money; reversal recovers it',
      () async {
        final hdfc = await bank();
        final result = await borrow('perm-block-1', hdfc.id);
        await genericSoftDelete(result.loan);
        await expectLater(
          loans.permanentlyDeleteLoan((await loanDoc(result.loan.id))!),
          throwsA(isA<OriginationDeleteBlockedException>()),
        );
        expect(await loanDoc(result.loan.id), isNotNull);
        expect(await loans.reverseOrigination('perm-block-1'), isFalse);
        expect(await balance(hdfc.id), 100000);
      },
    );

    test('10b — after reversal, permanent delete removes Loan + schedule; '
        'reversed Transaction kept as audit', () async {
      final hdfc = await bank();
      final result = await borrow('perm-ok-1', hdfc.id);
      await loans.reverseOrigination('perm-ok-1');
      await loans.permanentlyDeleteLoan((await loanDoc(result.loan.id))!);
      expect(await loanDoc(result.loan.id), isNull);
      expect(await allInstallments(result.scheduleId), isEmpty);
      expect((await loanTxns(result.loan.id)).single.isDeleted, isTrue);
      expect(await balance(hdfc.id), 100000);
    });

    test('a reversed Loan cannot be restored from Trash', () async {
      final hdfc = await bank();
      final result = await borrow('restore-block-1', hdfc.id);
      await loans.reverseOrigination('restore-block-1');
      await expectLater(
        loans.restore((await loanDoc(result.loan.id))!),
        throwsA(isA<OriginationDeleteBlockedException>()),
      );
    });
  });

  group('reverse origination', () {
    test(
      '1/11/12/13 — borrowed: HDFC back to exactly 1,00,000; Transaction '
      'reversed once; Loan trashed; schedule kept; Net Worth restored',
      () async {
        final hdfc = await bank();
        final before = await netWorth();
        final result = await borrow('rev-borrow-1', hdfc.id);
        expect(await loans.reverseOrigination('rev-borrow-1'), isFalse);
        expect(await balance(hdfc.id), 100000);
        final txns = await loanTxns(result.loan.id);
        expect(txns, hasLength(1));
        expect(txns.single.isDeleted, isTrue);
        expect((await loanDoc(result.loan.id))!.isDeleted, isTrue);
        expect(await allInstallments(result.scheduleId), hasLength(12));
        expect(await netWorth(), before);
        final audit = (await accounts.getByKey(hdfc.id))!.editHistory
            .where((e) => e.field == 'currentBalance')
            .map((e) => e.newValue);
        expect(audit, ['150000.0', '100000.0']);
      },
    );

    test('2 — lent: SBI back to exactly 1,00,000', () async {
      final sbi = await bank('SBI');
      final result = await lend('rev-lend-1', sbi.id);
      await loans.reverseOrigination('rev-lend-1');
      expect(await balance(sbi.id), 100000);
      expect((await loanTxns(result.loan.id)).single.isDeleted, isTrue);
    });

    test('3 — down payment: 10,000 restored; plan trashed', () async {
      final hdfc = await bank();
      final result = await buy('rev-down-1', hdfc.id);
      await loans.reverseOrigination('rev-down-1');
      expect(await balance(hdfc.id), 100000);
      expect((await loanDoc(result.loan.id))!.isDeleted, isTrue);
    });

    test(
      '4 — twice, and a stale repeat after other activity: moves back once',
      () async {
        final hdfc = await bank();
        await borrow('rev-retry-1', hdfc.id);
        await loans.reverseOrigination('rev-retry-1');
        await accounts.adjustBalance((await accounts.getByKey(hdfc.id))!, -700);
        expect(await loans.reverseOrigination('rev-retry-1'), isTrue);
        expect(await balance(hdfc.id), 100000 - 700);
      },
    );

    test(
      '5 — duplicate reversals in flight together: exactly one applies',
      () async {
        final hdfc = await bank();
        await borrow('rev-conc-1', hdfc.id);
        final results = await Future.wait([
          for (var i = 0; i < 5; i++) loans.reverseOrigination('rev-conc-1'),
        ]);
        expect(
          results.where((alreadyReversed) => !alreadyReversed),
          hasLength(1),
        );
        expect(await balance(hdfc.id), 100000);
      },
    );

    test(
      'a failure inside the reversal commit writes nothing; retry applies once',
      () async {
        final hdfc = await bank();
        final result = await borrow('rev-fail-1', hdfc.id);
        await expectLater(
          loans.reverseOrigination(
            'rev-fail-1',
            beforeWrite: () => throw StateError('injected'),
          ),
          throwsA(isA<StateError>()),
        );
        expect(await balance(hdfc.id), 150000);
        expect((await loanDoc(result.loan.id))!.isDeleted, isFalse);
        await loans.reverseOrigination('rev-fail-1');
        expect(await balance(hdfc.id), 100000);
      },
    );
  });

  group('dependency guards', () {
    test('6 — after a regular payment', () async {
      final hdfc = await bank();
      final result = await borrow('dep-pay-1', hdfc.id);
      final rows = await live(result.scheduleId);
      await payments.record(
        loan: result.loan,
        scheduleInstallments: rows,
        accountId: hdfc.id,
        amount: rows.first.amountDue,
        date: _loanDate,
        idempotencyKey: 'dep-pay-1-p',
      );
      await expectBlocked('dep-pay-1', OriginationReversalBlockReason.payment);
    });

    test('6b — after a partial payment', () async {
      final hdfc = await bank();
      final result = await borrow('dep-part-1', hdfc.id);
      await payments.record(
        loan: result.loan,
        scheduleInstallments: await live(result.scheduleId),
        accountId: hdfc.id,
        amount: 100,
        date: _loanDate,
        idempotencyKey: 'dep-part-1-p',
      );
      await expectBlocked('dep-part-1', OriginationReversalBlockReason.payment);
    });

    test('6c — even after that payment was itself reversed', () async {
      final hdfc = await bank();
      final result = await borrow('dep-revd-1', hdfc.id);
      final rows = await live(result.scheduleId);
      final paid = await payments.record(
        loan: result.loan,
        scheduleInstallments: rows,
        accountId: hdfc.id,
        amount: rows.first.amountDue,
        date: _loanDate,
        idempotencyKey: 'dep-revd-1-p',
      );
      await payments.reversePayment(
        loan: result.loan,
        transactionId: paid.transactionId,
        paymentIds: paid.paymentIds,
        installmentIds: paid.installmentIds,
        reversalIdempotencyKey: 'dep-revd-1-r',
      );
      await expectBlocked('dep-revd-1', OriginationReversalBlockReason.payment);
    });

    test('7 — after a principal prepayment', () async {
      final hdfc = await bank();
      final result = await borrow('dep-prep-1', hdfc.id);
      final rows = await live(result.scheduleId);
      await payments.record(
        loan: result.loan,
        scheduleInstallments: rows,
        accountId: hdfc.id,
        amount: rows.first.amountDue + 5000,
        date: _loanDate,
        idempotencyKey: 'dep-prep-1-p',
      );
      await expectBlocked('dep-prep-1', OriginationReversalBlockReason.payment);
    });

    test('8 — after an additional disbursement', () async {
      final hdfc = await bank();
      final result = await borrow('dep-disb-1', hdfc.id);
      await payments.recordAdditionalDisbursement(
        loan: result.loan,
        scheduleInstallments: await live(result.scheduleId),
        accountId: hdfc.id,
        amount: 2000,
        date: _loanDate,
        idempotencyKey: 'dep-disb-1-d',
      );
      await expectBlocked(
        'dep-disb-1',
        OriginationReversalBlockReason.disbursement,
      );
    });

    test('after Edit Loan Terms', () async {
      final hdfc = await bank();
      final result = await borrow('dep-terms-1', hdfc.id);
      await loans.editLoanTerms(
        result.loan,
        currentInstallments: await live(result.scheduleId),
        interest: result.loan.interest,
        installmentFrequency: ScheduleType.monthly,
        newInstallmentCount: 10,
      );
      await expectBlocked(
        'dep-terms-1',
        OriginationReversalBlockReason.scheduleChanged,
      );
    });

    test('after a skipped installment', () async {
      final hdfc = await bank();
      final result = await borrow('dep-skip-1', hdfc.id);
      final first = (await live(result.scheduleId)).first;
      await InstallmentRepository(
        installmentsCol(result.scheduleId),
      ).skipInstallment(first);
      await expectBlocked(
        'dep-skip-1',
        OriginationReversalBlockReason.scheduleChanged,
      );
    });

    test('after the Loan was closed', () async {
      final hdfc = await bank();
      final result = await borrow('dep-close-1', hdfc.id);
      await loans.closeLoan(result.loan);
      await expectBlocked('dep-close-1', OriginationReversalBlockReason.closed);
    });

    test('a rename does not block', () async {
      final hdfc = await bank();
      final result = await borrow('dep-name-1', hdfc.id);
      await loans.editLoan(result.loan, hasPayments: false, name: 'Kitchen');
      await loans.reverseOrigination('dep-name-1');
      expect(await balance(hdfc.id), 100000);
    });
  });

  test('activeOriginationMovement feeds the confirmation copy', () async {
    final hdfc = await bank();
    final result = await borrow('copy-1-abcd', hdfc.id);
    final movement = await loans.activeOriginationMovement(result.loan);
    expect(
      originationReversalMessage((
        kind: movement!.kind,
        amount: movement.amount,
        accountName: 'HDFC',
      )),
      'This will remove the original ₹50,000 received into HDFC and reverse '
      'the loan creation.',
    );
    await loans.reverseOrigination('copy-1-abcd');
    expect(await loans.activeOriginationMovement(result.loan), isNull);
  });
}
