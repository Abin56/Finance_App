import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person_timeline_builder.dart';
import 'package:finance_app/features/people/domain/person_timeline_entry.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

Loan _loan({
  required String id,
  required double loanAmount,
  required DateTime loanDate,
  bool isClosed = false,
  LoanDirection direction = LoanDirection.given,
}) {
  return Loan(
    id: id,
    personId: 'p1',
    loanAmount: loanAmount,
    loanDate: loanDate,
    repaymentType: LoanRepaymentType.oneTime,
    dueDate: loanDate.add(const Duration(days: 30)),
    scheduleId: 'sched-$id',
    createdAt: loanDate,
    isClosed: isClosed,
    direction: direction,
  );
}

Installment _installment({
  required String scheduleId,
  double amountDue = 100,
  double amountPaid = 0,
  DateTime? dueDate,
  bool isSkipped = false,
}) {
  return Installment(
    id: 'inst-$scheduleId',
    scheduleId: scheduleId,
    ownerType: OwnerType.loan,
    ownerId: 'loan',
    sequenceNumber: 1,
    dueDate: dueDate ?? DateTime(2026, 3, 1),
    amountDue: amountDue,
    amountPaid: amountPaid,
    isSkipped: isSkipped,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Builds an [Installment] whose computed `.status` matches [status] —
/// `overdue`/`upcoming` depend on `DateTime.now()`, so this pins [dueDate]
/// far enough in the past/future to be stable regardless of when the test
/// suite runs.
Installment _installmentWithStatus(InstallmentStatus status, {String scheduleId = 'sched1', double amountDue = 800}) {
  switch (status) {
    case InstallmentStatus.paid:
      return _installment(scheduleId: scheduleId, amountDue: amountDue, amountPaid: amountDue);
    case InstallmentStatus.partiallyPaid:
      return _installment(scheduleId: scheduleId, amountDue: amountDue, amountPaid: amountDue / 2);
    case InstallmentStatus.skipped:
      return _installment(scheduleId: scheduleId, amountDue: amountDue, isSkipped: true);
    case InstallmentStatus.overdue:
      return _installment(scheduleId: scheduleId, amountDue: amountDue, dueDate: DateTime(2000, 1, 1));
    case InstallmentStatus.upcoming:
      return _installment(scheduleId: scheduleId, amountDue: amountDue, dueDate: DateTime(2100, 1, 1));
  }
}

InstallmentPayment _payment({
  required String id,
  required String scheduleId,
  required double amount,
  required DateTime date,
}) {
  return InstallmentPayment(
    id: id,
    installmentId: 'inst-$scheduleId',
    scheduleId: scheduleId,
    ownerType: OwnerType.loan,
    ownerId: 'loan',
    amount: amount,
    date: date,
    createdAt: date,
  );
}

void main() {
  group('PersonTimelineBuilder.build merge ordering', () {
    test('merges ledger entries and loan events into one chronological list', () {
      final ledgerEntries = [
        LedgerEntry(
          id: 'l1',
          personId: 'p1',
          type: LedgerEntryType.gave,
          amount: 50,
          date: DateTime(2026, 1, 5),
          createdAt: DateTime(2026, 1, 5),
        ),
        LedgerEntry(
          id: 'l2',
          personId: 'p1',
          type: LedgerEntryType.receivedBack,
          amount: 20,
          date: DateTime(2026, 1, 15),
          createdAt: DateTime(2026, 1, 15),
        ),
      ];

      final loan = _loan(id: 'loan1', loanAmount: 200, loanDate: DateTime(2026, 1, 10));
      final installment = _installment(scheduleId: loan.scheduleId, amountDue: 200, amountPaid: 50);
      final payment = _payment(id: 'pay1', scheduleId: loan.scheduleId, amount: 50, date: DateTime(2026, 1, 20));

      final result = PersonTimelineBuilder.build(
        ledgerEntries: ledgerEntries,
        loans: [LoanTimelineData(loan: loan, installments: [installment], payments: [payment])],
      );

      expect(result.map((e) => e.id).toList(), ['l1', 'loan-loan1', 'l2', 'loan-payment-pay1']);
    });

    test('excludes soft-deleted ledger entries and loans by default', () {
      final deletedLedgerEntry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 50,
        date: DateTime(2026, 1, 5),
        createdAt: DateTime(2026, 1, 5),
      )..deletedAt = DateTime(2026, 1, 6);

      final deletedLoan = _loan(id: 'loan1', loanAmount: 200, loanDate: DateTime(2026, 1, 10))
        ..deletedAt = DateTime(2026, 1, 11);

      final result = PersonTimelineBuilder.build(
        ledgerEntries: [deletedLedgerEntry],
        loans: [LoanTimelineData(loan: deletedLoan, installments: const [], payments: const [])],
      );

      expect(result, isEmpty);
    });

    test('includeDeleted: true surfaces soft-deleted entries', () {
      final deletedLedgerEntry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 50,
        date: DateTime(2026, 1, 5),
        createdAt: DateTime(2026, 1, 5),
      )..deletedAt = DateTime(2026, 1, 6);

      final result = PersonTimelineBuilder.build(
        ledgerEntries: [deletedLedgerEntry],
        loans: const [],
        includeDeleted: true,
      );

      expect(result, hasLength(1));
      expect(result.single.isDeleted, isTrue);
    });
  });

  group('PersonTimelineBuilder.runningBalances', () {
    test('matches a hand-computed running balance across mixed entry types', () {
      final ledgerEntries = [
        LedgerEntry(
          id: 'l1',
          personId: 'p1',
          type: LedgerEntryType.gave,
          amount: 100,
          date: DateTime(2026, 1, 1),
          createdAt: DateTime(2026, 1, 1),
        ),
        LedgerEntry(
          id: 'l2',
          personId: 'p1',
          type: LedgerEntryType.receivedBack,
          amount: 30,
          date: DateTime(2026, 1, 10),
          createdAt: DateTime(2026, 1, 10),
        ),
      ];

      final loan = _loan(id: 'loan1', loanAmount: 200, loanDate: DateTime(2026, 1, 5));
      final payment = _payment(id: 'pay1', scheduleId: loan.scheduleId, amount: 75, date: DateTime(2026, 1, 15));

      final entries = PersonTimelineBuilder.build(
        ledgerEntries: ledgerEntries,
        loans: [LoanTimelineData(loan: loan, installments: const [], payments: [payment])],
      );

      final balances = PersonTimelineBuilder.runningBalances(openingBalance: 0, entriesOldestFirst: entries);

      // l1 (+100) -> loan1 (+200) -> l2 (-30) -> payment (-75)
      expect(balances['l1'], 100);
      expect(balances['loan-loan1'], 300);
      expect(balances['l2'], 270);
      expect(balances['loan-payment-pay1'], 195);
    });
  });

  group('PersonTimelineBuilder category tagging', () {
    test('adjustment ledger entries are categorized as other', () {
      final entry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.adjustment,
        amount: 10,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final result = PersonTimelineBuilder.build(ledgerEntries: [entry], loans: const []);
      expect(result.single.category, PersonTimelineCategory.other);
    });

    test('plain gave/borrowed/receivedBack/repaid entries are categorized as lending', () {
      final entry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 10,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final result = PersonTimelineBuilder.build(ledgerEntries: [entry], loans: const []);
      expect(result.single.category, PersonTimelineCategory.lending);
    });

    test('a split-note entry with a single participant is categorized as assignedExpense', () {
      final entry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 10,
        date: DateTime(2026, 1, 1),
        note: 'Split: Dinner',
        transactionRef: 'txn1',
        createdAt: DateTime(2026, 1, 1),
      );

      final result = PersonTimelineBuilder.build(
        ledgerEntries: [entry],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
      );
      expect(result.single.category, PersonTimelineCategory.assignedExpense);
    });

    test('a split-note entry with multiple participants is categorized as splitExpense', () {
      final entry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 10,
        date: DateTime(2026, 1, 1),
        note: 'Split: Dinner',
        transactionRef: 'txn1',
        createdAt: DateTime(2026, 1, 1),
      );

      final result = PersonTimelineBuilder.build(
        ledgerEntries: [entry],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 3},
      );
      expect(result.single.category, PersonTimelineCategory.splitExpense);
    });

    test('loan creation and loan payments are categorized as lending', () {
      final loan = _loan(id: 'loan1', loanAmount: 200, loanDate: DateTime(2026, 1, 1));
      final payment = _payment(id: 'pay1', scheduleId: loan.scheduleId, amount: 50, date: DateTime(2026, 1, 5));

      final result = PersonTimelineBuilder.build(
        ledgerEntries: const [],
        loans: [LoanTimelineData(loan: loan, installments: const [], payments: [payment])],
      );

      expect(result.every((e) => e.category == PersonTimelineCategory.lending), isTrue);
    });

    test('a given loan posts a positive signed amount and a payment reduces it', () {
      final loan = _loan(id: 'loan1', loanAmount: 200, loanDate: DateTime(2026, 1, 1));
      final payment = _payment(id: 'pay1', scheduleId: loan.scheduleId, amount: 50, date: DateTime(2026, 1, 5));

      final result = PersonTimelineBuilder.build(
        ledgerEntries: const [],
        loans: [LoanTimelineData(loan: loan, installments: const [], payments: [payment])],
      );

      final loanEntry = result.singleWhere((e) => e.id == 'loan-loan1');
      final paymentEntry = result.singleWhere((e) => e.id == 'loan-payment-pay1');
      expect(loanEntry.signedAmount, 200);
      expect(paymentEntry.signedAmount, -50);
      // Net effect after the payment: 150 still owed to the account owner.
      expect(loanEntry.signedAmount + paymentEntry.signedAmount, 150);
    });

    test('a taken loan posts a negative signed amount and a payment reduces the debt (moves it toward zero)', () {
      final loan = _loan(
        id: 'loan2',
        loanAmount: 200,
        loanDate: DateTime(2026, 1, 1),
        direction: LoanDirection.taken,
      );
      final payment = _payment(id: 'pay2', scheduleId: loan.scheduleId, amount: 50, date: DateTime(2026, 1, 5));

      final result = PersonTimelineBuilder.build(
        ledgerEntries: const [],
        loans: [LoanTimelineData(loan: loan, installments: const [], payments: [payment])],
      );

      final loanEntry = result.singleWhere((e) => e.id == 'loan-loan2');
      final paymentEntry = result.singleWhere((e) => e.id == 'loan-payment-pay2');
      expect(loanEntry.signedAmount, -200);
      expect(paymentEntry.signedAmount, 50);
      // Net effect after the payment: still owe 150 to the person.
      expect(loanEntry.signedAmount + paymentEntry.signedAmount, -150);
    });
  });

  group('PersonTimelineBuilder split expense status', () {
    LedgerEntry giveEntry({String transactionRef = 'txn1'}) => LedgerEntry(
          id: 'l1',
          personId: 'p1',
          type: LedgerEntryType.gave,
          amount: 800,
          date: DateTime(2026, 1, 1),
          note: 'Split: Dinner',
          transactionRef: transactionRef,
          createdAt: DateTime(2026, 1, 1),
        );

    test('a split "gave" entry shows Pending when its installment is upcoming', () {
      final result = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry()],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 2},
        installmentByTransactionRef: {'txn1': _installmentWithStatus(InstallmentStatus.upcoming)},
      );

      expect(result.single.status, PersonTimelineStatus.pending);
    });

    test('a split "gave" entry shows Partial when its installment is partially paid', () {
      final result = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry()],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 2},
        installmentByTransactionRef: {'txn1': _installmentWithStatus(InstallmentStatus.partiallyPaid)},
      );

      expect(result.single.status, PersonTimelineStatus.partial);
    });

    test('a split "gave" entry shows Completed when its installment is fully paid', () {
      final result = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry()],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 2},
        installmentByTransactionRef: {'txn1': _installmentWithStatus(InstallmentStatus.paid)},
      );

      expect(result.single.status, PersonTimelineStatus.completed);
    });

    test('a split "gave" entry shows Overdue when its installment is overdue', () {
      final result = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry()],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 2},
        installmentByTransactionRef: {'txn1': _installmentWithStatus(InstallmentStatus.overdue)},
      );

      expect(result.single.status, PersonTimelineStatus.overdue);
    });

    test('a split "gave" entry carries totalAmount/paidAmount from its installment', () {
      final installment = _installment(scheduleId: 'sched1', amountDue: 800, amountPaid: 300);
      final result = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry()],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 2},
        installmentByTransactionRef: {'txn1': installment},
      );

      expect(result.single.totalAmount, 800);
      expect(result.single.paidAmount, 300);
    });

    test('a non-expense entry never carries totalAmount/paidAmount even if an installment is present', () {
      final entry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 10,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final result = PersonTimelineBuilder.build(
        ledgerEntries: [entry],
        loans: const [],
        installmentByTransactionRef: {'txn1': _installment(scheduleId: 'sched1', amountDue: 800, amountPaid: 300)},
      );

      expect(result.single.totalAmount, isNull);
      expect(result.single.paidAmount, isNull);
    });

    test('a split settlement ("receivedBack") entry always shows Completed', () {
      final settlementEntry = LedgerEntry(
        id: 'l2',
        personId: 'p1',
        type: LedgerEntryType.receivedBack,
        amount: 800,
        date: DateTime(2026, 1, 10),
        note: 'Split settlement: Dinner',
        transactionRef: 'txn1',
        createdAt: DateTime(2026, 1, 10),
      );

      final result = PersonTimelineBuilder.build(
        ledgerEntries: [settlementEntry],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 2},
        installmentByTransactionRef: {'txn1': _installmentWithStatus(InstallmentStatus.paid)},
      );

      expect(result.single.status, PersonTimelineStatus.completed);
    });

    test('a plain (non-expense) ledger entry never gets a status', () {
      final entry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 10,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final result = PersonTimelineBuilder.build(ledgerEntries: [entry], loans: const []);
      expect(result.single.status, isNull);
    });
  });

  group('PersonTimelineBuilder — referencedTransactions', () {
    Transaction referenceTransaction({String id = 't1', bool deleted = false}) {
      final transaction = Transaction(
        id: id,
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        description: 'Lunch for Rahul',
        linkedPersonId: 'p1',
        createdAt: DateTime(2026, 1, 1),
      );
      if (deleted) transaction.markDeleted();
      return transaction;
    }

    test('a reference-only transaction produces a zero-amount, no-status, "reference" entry', () {
      final result = PersonTimelineBuilder.build(
        ledgerEntries: const [],
        loans: const [],
        referencedTransactions: [referenceTransaction()],
      );

      expect(result, hasLength(1));
      final entry = result.single;
      expect(entry.id, 't1');
      expect(entry.signedAmount, 0);
      expect(entry.displayAmount, 500);
      expect(entry.category, PersonTimelineCategory.reference);
      expect(entry.status, isNull);
      expect(entry.title, 'Lunch for Rahul');
    });

    test('a soft-deleted referenced transaction is excluded by default, included with includeDeleted', () {
      final deleted = referenceTransaction(deleted: true);

      final visible = PersonTimelineBuilder.build(
        ledgerEntries: const [],
        loans: const [],
        referencedTransactions: [deleted],
      );
      expect(visible, isEmpty);

      final withDeleted = PersonTimelineBuilder.build(
        ledgerEntries: const [],
        loans: const [],
        referencedTransactions: [deleted],
        includeDeleted: true,
      );
      expect(withDeleted, hasLength(1));
      expect(withDeleted.single.isDeleted, isTrue);
    });

    test('a reference entry never contributes to the pending balance total, unlike a real gave entry', () {
      final gaveEntry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 100,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final result = PersonTimelineBuilder.build(
        ledgerEntries: [gaveEntry],
        loans: const [],
        referencedTransactions: [referenceTransaction(id: 't2')],
      );

      final totalSignedAmount = result.fold(0.0, (total, e) => total + e.signedAmount);
      // Only the real "gave" entry (+100) affects the balance; the
      // reference-only transaction contributes exactly 0.
      expect(totalSignedAmount, 100);
    });
  });
}
