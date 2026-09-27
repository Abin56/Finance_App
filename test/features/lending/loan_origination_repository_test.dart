// LoanRepository.createAgreementWithOrigination — the atomic, idempotent create
// path of the unified Loans & Installments wizard. Same scenarios as flowfi-web's
// real-emulator suite (tests/integration/loan-origination.test.ts).
//
// fake_cloud_firestore applies a transaction's writes immediately and never
// rolls back, so on its own it cannot show atomicity. [AtomicFakeFirestore]
// restores real Firestore commit semantics for these tests: writes are
// buffered and applied only if the handler completes, and transactions are
// serialized (Firestore guarantees serializable transactions — a conflicting
// concurrent commit is retried against fresh reads, which is what the lock
// models).

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_allocation_type.dart';
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
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/atomic_fake_firestore.dart';

const _uid = 'test-uid';
final _loanDate = DateTime(2026, 1, 10);

void main() {
  late AtomicFakeFirestore firestore;
  late LoanRepository loans;
  late AccountRepository accounts;
  late TransactionRepository transactions;
  late LoanAdvancePaymentRepository payments;

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
    firestore = AtomicFakeFirestore();
    accounts = AccountRepository(
      col('accounts').withConverter<Account>(
        fromFirestore: Account.fromFirestore,
        toFirestore: (a, _) => a.toFirestore(),
      ),
    );
    transactions = TransactionRepository(
      col('transactions').withConverter<Transaction>(
        fromFirestore: Transaction.fromFirestore,
        toFirestore: (t, _) => t.toFirestore(),
      ),
      accounts,
    );
    loans = LoanRepository(
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
  Future<({int loans, int schedules, int transactions})> counts() async => (
    loans: (await col('loans').get()).size,
    schedules: (await col('paymentSchedules').get()).size,
    transactions: (await col('transactions').get()).size,
  );
  Future<List<Installment>> installments(String scheduleId) async =>
      (await installmentsCol(
          scheduleId,
        ).get()).docs.map((d) => d.data()).toList()
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  Future<List<Transaction>> loanTransactions(String loanId) async =>
      (await col('transactions').where('loanId', isEqualTo: loanId).get()).docs
          .map((d) => Transaction.fromFirestore(d, null))
          .toList();

  Future<AgreementOriginationResult> borrow(
    String key, {
    String? accountId,
    LoanRepaymentType repaymentType = LoanRepaymentType.installment,
    DateTime? dueDate,
    double amount = 50000,
    void Function(OriginationStage)? beforeWrite,
  }) => loans.createAgreementWithOrigination(
    idempotencyKey: key,
    name: 'Home renovation',
    category: LoanCategory.institutional,
    institutionName: 'HDFC Bank',
    fundingSource: LoanFundingSource.bank,
    direction: LoanDirection.taken,
    loanAmount: amount,
    loanDate: _loanDate,
    repaymentType: repaymentType,
    dueDate: dueDate,
    installmentFrequency: repaymentType == LoanRepaymentType.installment
        ? ScheduleType.monthly
        : null,
    installmentCount: repaymentType == LoanRepaymentType.installment
        ? 12
        : null,
    movementAccountId: accountId,
    beforeWrite: beforeWrite,
  );

  Future<AgreementOriginationResult> lend(
    String key, {
    String? accountId,
    LoanRepaymentType repaymentType = LoanRepaymentType.installment,
    DateTime? dueDate,
    double amount = 25000,
  }) => loans.createAgreementWithOrigination(
    idempotencyKey: key,
    name: 'Rahul',
    category: LoanCategory.personal,
    personId: 'rahul',
    fundingSource: LoanFundingSource.person,
    direction: LoanDirection.given,
    loanAmount: amount,
    loanDate: _loanDate,
    repaymentType: repaymentType,
    dueDate: dueDate,
    installmentFrequency: repaymentType == LoanRepaymentType.installment
        ? ScheduleType.monthly
        : null,
    installmentCount: repaymentType == LoanRepaymentType.installment ? 5 : null,
    movementAccountId: accountId,
  );

  Future<AgreementOriginationResult> buy(
    String key, {
    String? accountId,
    LoanFundingSource funding = LoanFundingSource.financeCompany,
    double down = 10000,
    String? cardId,
    String? purchaseId,
  }) => loans.createAgreementWithOrigination(
    idempotencyKey: key,
    name: 'Laptop',
    agreementKind: LoanAgreementKind.installmentPurchase,
    category: LoanCategory.institutional,
    institutionName: 'Bajaj Finserv',
    fundingSource: funding,
    direction: LoanDirection.taken,
    purchaseAmount: 60000,
    downPayment: down,
    loanAmount: 60000 - down,
    loanDate: _loanDate,
    repaymentType: LoanRepaymentType.installment,
    installmentFrequency: ScheduleType.monthly,
    installmentCount: 10,
    linkedCreditCardId: cardId,
    purchaseTransactionId: purchaseId,
    movementAccountId: accountId,
  );

  group('Money I Borrowed', () {
    test('1 — no movement: Loan + schedule + installments only', () async {
      final hdfc = await bank();
      final result = await borrow('borrow-none-01');
      expect(result.loan.id, 'orig_borrow-none-01_loan');
      expect(result.transactionId, isNull);
      expect(await installments(result.scheduleId), hasLength(12));
      expect(await counts(), (loans: 1, schedules: 1, transactions: 0));
      expect(await balance(hdfc.id), 100000);
    });

    test('2/5 — record received into HDFC: +50,000, one income '
        'additionalDisbursement, excluded from income totals', () async {
      final hdfc = await bank();
      final result = await borrow('borrow-move-01', accountId: hdfc.id);
      expect(await balance(hdfc.id), 150000);
      final txns = await loanTransactions(result.loan.id);
      expect(txns, hasLength(1));
      expect(txns.single.id, 'orig_borrow-move-01_txn');
      expect(txns.single.type, TransactionType.income);
      expect(txns.single.amount, 50000);
      expect(
        txns.single.paymentAllocationType,
        PaymentAllocationType.additionalDisbursement,
      );
      expect(txns.single.excludeFromCalculations, isFalse);
      expect(txns.single.isNonIncomeExpenseMovement, isTrue);
      final schedule = await installments(result.scheduleId);
      expect(schedule.map((i) => i.id), [
        for (var i = 1; i <= 12; i++) 'orig_borrow-move-01_inst_$i',
      ]);
      expect(
        schedule.fold<double>(0, (total, i) => total + i.amountDue),
        closeTo(50000, 0.01),
      );
    });

    test('6 — one-time: one oneTime installment on the due date', () async {
      final hdfc = await bank();
      final due = DateTime(2026, 6, 30);
      final result = await borrow(
        'borrow-once-01',
        accountId: hdfc.id,
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: due,
        amount: 8000,
      );
      expect(result.loan.repaymentType, LoanRepaymentType.oneTime);
      expect(result.loan.installmentCount, isNull);
      final rows = await installments(result.scheduleId);
      expect(rows, hasLength(1));
      expect(rows.single.dueDate, due);
      expect(rows.single.amountDue, 8000);
      expect(await balance(hdfc.id), 108000);
    });
  });

  group('Money I Lent', () {
    test('3 — no movement', () async {
      final sbi = await bank('SBI');
      final result = await lend('lend-none-01');
      expect(result.loan.personId, 'rahul');
      expect(result.transactionId, isNull);
      expect(await balance(sbi.id), 100000);
    });

    test('4/7 — record sent from SBI: −25,000, one expense, not spending, '
        'no Person document written', () async {
      final sbi = await bank('SBI');
      final result = await lend('lend-move-01', accountId: sbi.id);
      expect(await balance(sbi.id), 75000);
      final txns = await loanTransactions(result.loan.id);
      expect(txns.single.type, TransactionType.expense);
      expect(txns.single.amount, 25000);
      expect(txns.single.isNonIncomeExpenseMovement, isTrue);
      expect((await col('people').get()).size, 0);
    });

    test(
      '8 — one-time lent, repaid and reversed via the existing flow',
      () async {
        final sbi = await bank('SBI');
        final result = await lend(
          'lend-once-01',
          accountId: sbi.id,
          repaymentType: LoanRepaymentType.oneTime,
          dueDate: DateTime(2026, 3, 1),
          amount: 3000,
        );
        expect(await balance(sbi.id), 97000);
        final paid = await payments.record(
          loan: result.loan,
          scheduleInstallments: await installments(result.scheduleId),
          accountId: sbi.id,
          amount: 3000,
          date: DateTime(2026, 3, 1),
          idempotencyKey: 'lend-once-01-repay',
        );
        expect(await balance(sbi.id), 100000);
        await payments.reversePayment(
          loan: result.loan,
          transactionId: paid.transactionId,
          paymentIds: paid.paymentIds,
          installmentIds: paid.installmentIds,
          reversalIdempotencyKey: 'lend-once-01-rev',
        );
        expect(await balance(sbi.id), 97000);
      },
    );
  });

  group('Installment Purchase', () {
    test('9 — zero down payment cannot be recorded; nothing written', () async {
      final hdfc = await bank();
      await expectLater(
        buy('buy-zero-02', down: 0, accountId: hdfc.id),
        throwsA(isA<AppException>()),
      );
      expect(await counts(), (loans: 0, schedules: 0, transactions: 0));
    });

    test(
      '10 — down payment not recorded: financed 50,000, no movement',
      () async {
        final hdfc = await bank();
        final result = await buy('buy-down-none');
        expect(result.loan.loanAmount, 50000);
        expect(result.loan.purchaseAmount, 60000);
        expect(result.loan.downPayment, 10000);
        expect(await balance(hdfc.id), 100000);
      },
    );

    test(
      '11/13 — down payment recorded: −10,000 once, counted as spending',
      () async {
        final hdfc = await bank();
        final result = await buy('buy-down-rec', accountId: hdfc.id);
        expect(await balance(hdfc.id), 90000);
        final txns = await loanTransactions(result.loan.id);
        expect(txns.single.type, TransactionType.expense);
        expect(txns.single.amount, 10000);
        expect(txns.single.paymentAllocationType, isNull);
        expect(txns.single.isNonIncomeExpenseMovement, isFalse);
      },
    );

    test('12 — bank financing', () async {
      final result = await buy('buy-bank-01', funding: LoanFundingSource.bank);
      expect(result.loan.fundingSource, LoanFundingSource.bank);
      expect(result.loan.agreementKind, LoanAgreementKind.installmentPurchase);
    });

    test('14 — tracked card with purchase: no new purchase Transaction, '
        'separate down payment only', () async {
      final hdfc = await bank();
      final card = await accounts.createAccount(
        name: 'Card',
        type: AccountType.card,
        openingBalance: 0,
        colorValue: 0,
      );
      await col('creditCards').doc('card-1').set({'accountId': card.id});
      final purchase = await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 50000,
        dateTime: _loanDate,
        accountId: card.id,
        categoryId: 'shopping',
        description: 'Phone',
      );
      final before = await counts();
      final result = await buy(
        'buy-card-01',
        funding: LoanFundingSource.creditCard,
        cardId: 'card-1',
        purchaseId: purchase.id,
        accountId: hdfc.id,
      );
      expect(result.loan.purchaseTransactionId, purchase.id);
      expect((await counts()).transactions, before.transactions + 1);
      final txns = await loanTransactions(result.loan.id);
      expect(txns.single.accountId, hdfc.id);
      expect(txns.single.amount, 10000);
      expect(await balance(card.id), -50000);
    });

    test('14b — a purchase not on the chosen card is refused', () async {
      final hdfc = await bank();
      await col('creditCards').doc('card-1').set({'accountId': 'card-acct'});
      final lunch = await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: _loanDate,
        accountId: hdfc.id,
        categoryId: 'food',
      );
      await expectLater(
        buy(
          'buy-card-02',
          funding: LoanFundingSource.creditCard,
          cardId: 'card-1',
          purchaseId: lunch.id,
        ),
        throwsA(isA<AppException>()),
      );
      expect((await counts()).loans, 0);
    });

    test('15 — tracked card without purchase (Case B): plan only', () async {
      final result = await buy(
        'buy-card-b',
        funding: LoanFundingSource.creditCard,
        cardId: 'card-1',
      );
      expect(result.loan.linkedCreditCardId, 'card-1');
      expect(result.loan.purchaseTransactionId, isNull);
      expect(result.transactionId, isNull);
    });

    test('16 — external/person financing', () async {
      final result = await loans.createAgreementWithOrigination(
        idempotencyKey: 'buy-person-01',
        name: 'Fridge',
        agreementKind: LoanAgreementKind.installmentPurchase,
        category: LoanCategory.personal,
        personId: 'uncle',
        fundingSource: LoanFundingSource.person,
        direction: LoanDirection.taken,
        purchaseAmount: 20000,
        downPayment: 0,
        loanAmount: 20000,
        loanDate: _loanDate,
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      expect(result.loan.personId, 'uncle');
      expect(result.loan.fundingSource, LoanFundingSource.person);
    });

    test('a card account is refused as the movement account', () async {
      final card = await accounts.createAccount(
        name: 'Card',
        type: AccountType.card,
        openingBalance: 0,
        colorValue: 0,
      );
      await expectLater(
        lend('lend-card-01', accountId: card.id),
        throwsA(isA<AppException>()),
      );
      expect(await counts(), (loans: 0, schedules: 0, transactions: 0));
    });
  });

  group('17/18 — idempotency, retry, concurrency', () {
    test(
      'A — same key twice: one Loan, schedule, Transaction, movement',
      () async {
        final hdfc = await bank();
        final first = await borrow('retry-same-01', accountId: hdfc.id);
        final second = await borrow('retry-same-01', accountId: hdfc.id);
        expect(second.alreadyCreated, isTrue);
        expect(second.loan.id, first.loan.id);
        expect(second.transactionId, first.transactionId);
        expect(await counts(), (loans: 1, schedules: 1, transactions: 1));
        expect(await installments(first.scheduleId), hasLength(12));
        expect(await balance(hdfc.id), 150000);
      },
    );

    test(
      'B — stale retry after the account moved elsewhere: no lost update',
      () async {
        final hdfc = await bank();
        await borrow('retry-stale-01', accountId: hdfc.id);
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 700,
          dateTime: _loanDate,
          accountId: hdfc.id,
          categoryId: 'food',
        );
        final retried = await borrow('retry-stale-01', accountId: hdfc.id);
        expect(retried.alreadyCreated, isTrue);
        expect(await balance(hdfc.id), 150000 - 700);
      },
    );

    test('D — duplicate submissions in flight together: exactly one', () async {
      final hdfc = await bank();
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          borrow('retry-concurrent-01', accountId: hdfc.id),
      ]);
      expect(results.where((r) => !r.alreadyCreated), hasLength(1));
      expect(await counts(), (loans: 1, schedules: 1, transactions: 1));
      expect(await balance(hdfc.id), 150000);
    });

    test('a reused key for a different request is a conflict', () async {
      final hdfc = await bank();
      await borrow('retry-conflict-01');
      await expectLater(
        borrow('retry-conflict-01', accountId: hdfc.id),
        throwsA(isA<OriginationConflictException>()),
      );
      await expectLater(
        lend('retry-conflict-01'),
        throwsA(isA<OriginationConflictException>()),
      );
      expect(await balance(hdfc.id), 100000);
    });
  });

  group('failure injection — nothing partial is committed', () {
    for (final stage in OriginationStage.values) {
      test(
        'failure at ${stage.name}: nothing written; retry succeeds once',
        () async {
          final hdfc = await bank();
          await expectLater(
            borrow(
              'fail-${stage.name}-01',
              accountId: hdfc.id,
              beforeWrite: (at) {
                if (at == stage) throw StateError('injected ${stage.name}');
              },
            ),
            throwsA(isA<StateError>()),
          );
          expect(await counts(), (loans: 0, schedules: 0, transactions: 0));
          expect(
            await installments('orig_fail-${stage.name}-01_sched'),
            isEmpty,
          );
          expect(await balance(hdfc.id), 100000);

          final retried = await borrow(
            'fail-${stage.name}-01',
            accountId: hdfc.id,
          );
          expect(retried.alreadyCreated, isFalse);
          expect(await counts(), (loans: 1, schedules: 1, transactions: 1));
          expect(await balance(hdfc.id), 150000);
        },
      );
    }

    test('a missing account writes nothing', () async {
      await expectLater(
        borrow('fail-acct-01', accountId: 'nope'),
        throwsA(isA<AppException>()),
      );
      expect(await counts(), (loans: 0, schedules: 0, transactions: 0));
    });
  });

  group('19 — reversal / undo', () {
    test('the origination Transaction cannot be generically deleted', () async {
      final hdfc = await bank();
      final result = await borrow('undo-guard-01', accountId: hdfc.id);
      final txn = (await loanTransactions(result.loan.id)).single;
      await expectLater(
        transactions.softDeleteTransaction(txn),
        throwsA(isA<LoanPaymentTransactionRestrictedError>()),
      );
    });

    test(
      'reverseOrigination undoes Transaction + Account + Loan, idempotently',
      () async {
        final hdfc = await bank();
        final result = await borrow('undo-ok-0001', accountId: hdfc.id);
        expect(await loans.reverseOrigination('undo-ok-0001'), isFalse);
        expect(await balance(hdfc.id), 100000);
        expect(
          (await col('loans').doc(result.loan.id).get()).data()!['deletedAt'],
          isNotNull,
        );
        expect(
          (await loanTransactions(result.loan.id)).single.isDeleted,
          isTrue,
        );
        expect(await loans.reverseOrigination('undo-ok-0001'), isTrue);
        expect(await balance(hdfc.id), 100000);
      },
    );

    test('reverseOrigination is blocked once a payment exists', () async {
      final hdfc = await bank();
      final result = await borrow('undo-paid-01', accountId: hdfc.id);
      final rows = await installments(result.scheduleId);
      await payments.record(
        loan: result.loan,
        scheduleInstallments: rows,
        accountId: hdfc.id,
        amount: rows.first.amountDue,
        date: _loanDate,
        idempotencyKey: 'undo-paid-01-p1',
      );
      await expectLater(
        loans.reverseOrigination('undo-paid-01'),
        throwsA(isA<OriginationReversalBlockedException>()),
      );
    });
  });

  group('20 — legacy regression', () {
    test(
      'legacy createLoan still works with random ids and no Transaction',
      () async {
        final loan = await loans.createLoan(
          loanAmount: 12000,
          loanDate: _loanDate,
          repaymentType: LoanRepaymentType.installment,
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 12,
          category: LoanCategory.institutional,
          institutionName: 'Axis',
        );
        expect(loan.id.startsWith('orig_'), isFalse);
        expect(await installments(loan.scheduleId), hasLength(12));
        expect(await counts(), (loans: 1, schedules: 1, transactions: 0));
      },
    );
  });
}
