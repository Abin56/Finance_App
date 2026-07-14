import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/payment_record.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/credit_cards/domain/statement_payment.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/expense_participant.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/domain/history_builder.dart';
import 'package:finance_app/features/transactions/domain/history_entry.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

Installment _installment({
  required String id,
  required String scheduleId,
  required double amountDue,
  double amountPaid = 0,
  DateTime? dueDate,
}) {
  return Installment(
    id: id,
    scheduleId: scheduleId,
    ownerType: OwnerType.splitExpense,
    ownerId: 'exp1',
    sequenceNumber: 1,
    // Defaults to comfortably in the future (relative to whenever this test
    // runs) so tests that aren't about overdue-ness don't accidentally
    // trip `Installment.status == overdue` just because the fixture's date
    // has receded into the past — pass an explicit past `dueDate` when a
    // test actually wants to exercise overdue.
    dueDate: dueDate ?? DateTime.now().add(const Duration(days: 365)),
    amountDue: amountDue,
    amountPaid: amountPaid,
    createdAt: DateTime(2026, 1, 1),
  );
}

Transaction _transaction({
  required String id,
  TransactionType type = TransactionType.expense,
  double amount = 100,
  DateTime? dateTime,
  String? receiptPurpose,
}) {
  return Transaction(
    id: id,
    type: type,
    amount: amount,
    dateTime: dateTime ?? DateTime(2026, 1, 1),
    accountId: 'acc1',
    categoryId: 'cat1',
    createdAt: dateTime ?? DateTime(2026, 1, 1),
    receiptPurpose: receiptPurpose,
  );
}

void main() {
  group('HistoryBuilder.build — plain transactions', () {
    test('a plain expense transaction is categorized as transaction', () {
      final txn = _transaction(id: 't1');

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result.single.category, HistoryCategory.transaction);
      expect(result.single.isCredit, isFalse);
    });

    test('a plain income transaction is a credit', () {
      final txn = _transaction(id: 't1', type: TransactionType.income, amount: 500);

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result.single.isCredit, isTrue);
      expect(result.single.amount, 500);
    });

    test('a transaction with a receiptPurpose is categorized as moneyReceived', () {
      final txn = _transaction(
        id: 't1',
        type: TransactionType.income,
        receiptPurpose: 'friendReturnedMoney',
      );

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result.single.category, HistoryCategory.moneyReceived);
    });

    test('excludes soft-deleted transactions by default', () {
      final txn = _transaction(id: 't1')..markDeleted();

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result, isEmpty);
    });
  });

  group('HistoryBuilder.build — split expenses', () {
    test('a transaction linked to a split Expense is categorized as splitExpense, not transaction', () {
      final txn = _transaction(id: 't1', amount: 800);
      final expense = Expense(
        id: 'exp1',
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Rahul', share: 400, personId: 'p1', installmentId: 'inst1'),
          ExpenseParticipant(name: 'You', share: 400),
        ],
        scheduleId: 'sched1',
        createdAt: DateTime(2026, 1, 1),
      );

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result.single.category, HistoryCategory.splitExpense);
    });

    test('splitExpenseDetail carries participant count and money-to-collect amount', () {
      final txn = _transaction(id: 't1', amount: 800);
      final expense = Expense(
        id: 'exp1',
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Rahul', share: 400, personId: 'p1', installmentId: 'inst1'),
          ExpenseParticipant(name: 'You', share: 400, installmentId: 'inst2'),
        ],
        scheduleId: 'sched1',
        createdAt: DateTime(2026, 1, 1),
      );
      final installments = [
        _installment(id: 'inst1', scheduleId: 'sched1', amountDue: 400, amountPaid: 0),
        _installment(id: 'inst2', scheduleId: 'sched1', amountDue: 400, amountPaid: 0),
      ];

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
        installmentsByScheduleId: {'sched1': installments},
      );

      final detail = result.single.splitExpenseDetail!;
      expect(detail.participantCount, 2);
      expect(detail.amountToCollect, 800);
      expect(detail.status, SplitExpenseHistoryStatus.pending);
    });

    test('splitExpenseDetail status is partial when some but not all is collected', () {
      final txn = _transaction(id: 't1', amount: 800);
      final expense = Expense(
        id: 'exp1',
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Rahul', share: 400, personId: 'p1', installmentId: 'inst1'),
          ExpenseParticipant(name: 'You', share: 400, installmentId: 'inst2'),
        ],
        scheduleId: 'sched1',
        createdAt: DateTime(2026, 1, 1),
      );
      final installments = [
        _installment(id: 'inst1', scheduleId: 'sched1', amountDue: 400, amountPaid: 400),
        _installment(id: 'inst2', scheduleId: 'sched1', amountDue: 400, amountPaid: 0),
      ];

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
        installmentsByScheduleId: {'sched1': installments},
      );

      final detail = result.single.splitExpenseDetail!;
      expect(detail.amountToCollect, 400);
      expect(detail.status, SplitExpenseHistoryStatus.partial);
    });

    test('splitExpenseDetail status is overdue when an unpaid installment is past its due date', () {
      final txn = _transaction(id: 't1', amount: 800);
      final expense = Expense(
        id: 'exp1',
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Rahul', share: 400, personId: 'p1', installmentId: 'inst1'),
          ExpenseParticipant(name: 'You', share: 400, installmentId: 'inst2'),
        ],
        scheduleId: 'sched1',
        createdAt: DateTime(2026, 1, 1),
      );
      final installments = [
        _installment(
          id: 'inst1',
          scheduleId: 'sched1',
          amountDue: 400,
          amountPaid: 0,
          dueDate: DateTime.now().subtract(const Duration(days: 5)),
        ),
        _installment(id: 'inst2', scheduleId: 'sched1', amountDue: 400, amountPaid: 0),
      ];

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
        installmentsByScheduleId: {'sched1': installments},
      );

      final detail = result.single.splitExpenseDetail!;
      expect(detail.status, SplitExpenseHistoryStatus.overdue);
    });

    test('splitExpenseDetail status is completed once everything is collected', () {
      final txn = _transaction(id: 't1', amount: 800);
      final expense = Expense(
        id: 'exp1',
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Rahul', share: 400, personId: 'p1', installmentId: 'inst1'),
          ExpenseParticipant(name: 'You', share: 400, installmentId: 'inst2'),
        ],
        scheduleId: 'sched1',
        createdAt: DateTime(2026, 1, 1),
      );
      final installments = [
        _installment(id: 'inst1', scheduleId: 'sched1', amountDue: 400, amountPaid: 400),
        _installment(id: 'inst2', scheduleId: 'sched1', amountDue: 400, amountPaid: 400),
      ];

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
        installmentsByScheduleId: {'sched1': installments},
      );

      final detail = result.single.splitExpenseDetail!;
      expect(detail.amountToCollect, 0);
      expect(detail.status, SplitExpenseHistoryStatus.completed);
    });

    test('a plain transaction has no splitExpenseDetail', () {
      final txn = _transaction(id: 't1');

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result.single.splitExpenseDetail, isNull);
    });

    test('splitExpenseDetail.myShare reflects the "Me" participant\'s own share', () {
      final txn = _transaction(id: 't1', amount: 900);
      final expense = Expense(
        id: 'exp1',
        description: 'Dinner',
        totalAmount: 900,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Me', share: 300, isMe: true),
          ExpenseParticipant(name: 'Rahul', share: 300, personId: 'p1', installmentId: 'inst1'),
          ExpenseParticipant(name: 'John', share: 300, installmentId: 'inst2'),
        ],
        scheduleId: 'sched1',
        createdAt: DateTime(2026, 1, 1),
      );
      final installments = [
        _installment(id: 'inst1', scheduleId: 'sched1', amountDue: 300, amountPaid: 300),
        _installment(id: 'inst2', scheduleId: 'sched1', amountDue: 300, amountPaid: 0),
      ];

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
        installmentsByScheduleId: {'sched1': installments},
      );

      final detail = result.single.splitExpenseDetail!;
      expect(detail.myShare, 300);
      expect(detail.collected, 300);
      expect(detail.amountToCollect, 300);
    });

    test('splitExpenseDetail.myShare is 0 for a legacy split expense with no "Me" participant', () {
      final txn = _transaction(id: 't1', amount: 800);
      final expense = Expense(
        id: 'exp1',
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Rahul', share: 400, personId: 'p1', installmentId: 'inst1'),
          ExpenseParticipant(name: 'John', share: 400, installmentId: 'inst2'),
        ],
        scheduleId: 'sched1',
        createdAt: DateTime(2026, 1, 1),
      );
      final installments = [
        _installment(id: 'inst1', scheduleId: 'sched1', amountDue: 400, amountPaid: 0),
        _installment(id: 'inst2', scheduleId: 'sched1', amountDue: 400, amountPaid: 0),
      ];

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
        installmentsByScheduleId: {'sched1': installments},
      );

      expect(result.single.splitExpenseDetail!.myShare, 0);
    });

    test('an unsplit Expense (splitType.none) does not recategorize its transaction', () {
      final txn = _transaction(id: 't1', amount: 300);
      final expense = Expense(
        id: 'exp1',
        description: 'Groceries',
        totalAmount: 300,
        date: DateTime(2026, 1, 1),
        categoryId: 'cat1',
        accountId: 'acc1',
        transactionId: 't1',
        splitType: SplitType.none,
        participants: const [],
        createdAt: DateTime(2026, 1, 1),
      );

      final result = HistoryBuilder.build(
        transactions: [txn],
        expenses: [expense],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result.single.category, HistoryCategory.transaction);
    });
  });

  group('HistoryBuilder.build — loan/bill/EMI payments', () {
    test('a loan payment is categorized as loan and is a credit', () {
      final loan = Loan(
        id: 'l1',
        personId: 'p1',
        loanAmount: 500,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'sched-l1',
        createdAt: DateTime(2026, 1, 1),
      );
      final payment = InstallmentPayment(
        id: 'ip1',
        installmentId: 'inst1',
        scheduleId: 'sched-l1',
        ownerType: OwnerType.loan,
        ownerId: 'l1',
        amount: 100,
        date: DateTime(2026, 1, 15),
        createdAt: DateTime(2026, 1, 15),
      );

      final result = HistoryBuilder.build(
        transactions: const [],
        expenses: const [],
        loans: [LoanHistoryData(loan: loan, payments: [payment])],
        bills: const [],
        emis: const [],
      );

      expect(result.single.category, HistoryCategory.loan);
      expect(result.single.isCredit, isTrue);
      expect(result.single.amount, 100);
    });

    test('a bill payment is categorized as bill and is a debit', () {
      final bill = Bill(
        id: 'b1',
        name: 'Electricity',
        amount: 200,
        dueDate: DateTime(2026, 1, 5),
        recurrence: BillRecurrence.monthly,
        createdAt: DateTime(2026, 1, 1),
      );
      final payment = PaymentRecord(
        id: 'pr1',
        billId: 'b1',
        amount: 200,
        date: DateTime(2026, 1, 4),
        createdAt: DateTime(2026, 1, 4),
      );

      final result = HistoryBuilder.build(
        transactions: const [],
        expenses: const [],
        loans: const [],
        bills: [BillHistoryData(bill: bill, payments: [payment])],
        emis: const [],
      );

      expect(result.single.category, HistoryCategory.bill);
      expect(result.single.isCredit, isFalse);
    });

    test('an EMI payment is categorized as emi and is a debit', () {
      final emi = Emi(
        id: 'e1',
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
        endDate: DateTime(2026, 4, 1),
        scheduleId: 'sched-e1',
        createdAt: DateTime(2026, 1, 1),
      );
      final payment = InstallmentPayment(
        id: 'ip2',
        installmentId: 'inst2',
        scheduleId: 'sched-e1',
        ownerType: OwnerType.emi,
        ownerId: 'e1',
        amount: 250,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final result = HistoryBuilder.build(
        transactions: const [],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: [EmiHistoryData(emi: emi, payments: [payment])],
      );

      expect(result.single.category, HistoryCategory.emi);
      expect(result.single.isCredit, isFalse);
      expect(result.single.amount, 250);
    });
  });

  group('HistoryBuilder.build — credit card statements', () {
    test('a materialized Statement produces a statementGenerated entry', () {
      final statement = Statement(
        id: 's1',
        cardId: 'card1',
        periodStart: DateTime(2026, 6, 18),
        periodEnd: DateTime(2026, 7, 17),
        generatedDate: DateTime(2026, 7, 17),
        dueDate: DateTime(2026, 8, 5),
        totalAmount: 2400,
        createdAt: DateTime(2026, 7, 17),
      );

      final result = HistoryBuilder.build(
        transactions: const [],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
        creditCards: [
          CreditCardHistoryData(cardName: 'HDFC Card', statements: [statement], paymentsByStatementId: const {}),
        ],
      );

      expect(result.single.category, HistoryCategory.statementGenerated);
      expect(result.single.amount, 2400);
      expect(result.single.date, DateTime(2026, 7, 17));
    });

    test('a StatementPayment produces a statementPaid entry alongside the generated one', () {
      final statement = Statement(
        id: 's1',
        cardId: 'card1',
        periodStart: DateTime(2026, 6, 18),
        periodEnd: DateTime(2026, 7, 17),
        generatedDate: DateTime(2026, 7, 17),
        dueDate: DateTime(2026, 8, 5),
        totalAmount: 2400,
        amountPaid: 2400,
        createdAt: DateTime(2026, 7, 17),
      );
      final payment = StatementPayment(
        id: 'p1',
        statementId: 's1',
        amount: 2400,
        date: DateTime(2026, 7, 25),
        sourceAccountId: 'acc-bank',
        transactionId: 'txn-payment',
        createdAt: DateTime(2026, 7, 25),
      );

      final result = HistoryBuilder.build(
        transactions: const [],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
        creditCards: [
          CreditCardHistoryData(
            cardName: 'HDFC Card',
            statements: [statement],
            paymentsByStatementId: {'s1': [payment]},
          ),
        ],
      );

      expect(result, hasLength(2));
      expect(result.map((e) => e.category), containsAll([HistoryCategory.statementGenerated, HistoryCategory.statementPaid]));
      final paidEntry = result.firstWhere((e) => e.category == HistoryCategory.statementPaid);
      expect(paidEntry.amount, 2400);
      expect(paidEntry.date, DateTime(2026, 7, 25));
    });
  });

  group('HistoryBuilder.build — ordering', () {
    test('sorts newest first across mixed sources', () {
      final older = _transaction(id: 't1', dateTime: DateTime(2026, 1, 1));
      final newer = _transaction(id: 't2', dateTime: DateTime(2026, 1, 10));

      final result = HistoryBuilder.build(
        transactions: [older, newer],
        expenses: const [],
        loans: const [],
        bills: const [],
        emis: const [],
      );

      expect(result.map((e) => e.id).toList(), ['txn-t2', 'txn-t1']);
    });
  });
}
