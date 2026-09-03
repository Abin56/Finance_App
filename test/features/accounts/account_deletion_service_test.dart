import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_deletion_service.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/bills/data/bill_occurrence_repository.dart';
import 'package:finance_app/features/bills/data/bill_repository.dart';
import 'package:finance_app/features/bills/data/payment_repository.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/payment_record.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/features/expense/data/expense_repository.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the account permanent-delete cascade — the replacement for
/// "permanently delete an account" leaving its transactions/bills/expenses
/// orphaned. Everything runs against a real [FakeFirebaseFirestore] (same
/// convention as `expense_repository_test.dart`/`payment_repository_test.dart`),
/// so these are close to integration tests of the real repository classes,
/// not hand-mocked doubles.
void main() {
  late FakeFirebaseFirestore firestore;
  late AccountRepository accountRepository;
  late TransactionRepository transactionRepository;
  late BillRepository billRepository;
  late ExpenseRepository expenseRepository;
  late PersonRepository personRepository;
  late PaymentScheduleRepository paymentScheduleRepository;
  late AccountDeletionRepositories repos;

  InstallmentRepository installmentRepositoryFor(String scheduleId) {
    final collection = firestore
        .collection('paymentSchedules')
        .doc(scheduleId)
        .collection('installments')
        .withConverter<Installment>(fromFirestore: Installment.fromFirestore, toFirestore: (i, _) => i.toFirestore());
    return InstallmentRepository(collection);
  }

  LedgerRepository ledgerRepositoryFor(String personId) {
    final collection = firestore
        .collection('people')
        .doc(personId)
        .collection('ledger')
        .withConverter<LedgerEntry>(fromFirestore: LedgerEntry.fromFirestore, toFirestore: (e, _) => e.toFirestore());
    return LedgerRepository(collection, personRepository);
  }

  BillOccurrenceRepository occurrenceRepositoryFor(String billId) {
    final collection = firestore
        .collection('bills')
        .doc(billId)
        .collection('occurrences')
        .withConverter<BillOccurrence>(
          fromFirestore: BillOccurrence.fromFirestore,
          toFirestore: (o, _) => o.toFirestore(),
        );
    return BillOccurrenceRepository(
      collection,
      billRepository,
      firestore.collection('bills').doc(billId),
      firestore.collection('bills').doc(billId).collection('payments'),
    );
  }

  PaymentRepository paymentRepositoryFor(String billId) {
    final collection = firestore
        .collection('bills')
        .doc(billId)
        .collection('payments')
        .withConverter<PaymentRecord>(fromFirestore: PaymentRecord.fromFirestore, toFirestore: (p, _) => p.toFirestore());
    return PaymentRepository(collection, occurrenceRepositoryFor(billId));
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();

    accountRepository = AccountRepository(
      firestore.collection('accounts').withConverter<Account>(
            fromFirestore: Account.fromFirestore,
            toFirestore: (a, _) => a.toFirestore(),
          ),
    );
    transactionRepository = TransactionRepository(
      firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          ),
      accountRepository,
    );
    billRepository = BillRepository(
      firestore.collection('bills').withConverter<Bill>(fromFirestore: Bill.fromFirestore, toFirestore: (b, _) => b.toFirestore()),
    );
    personRepository = PersonRepository(
      firestore.collection('people').withConverter<Person>(
            fromFirestore: Person.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          ),
    );
    paymentScheduleRepository = PaymentScheduleRepository(
      firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
            fromFirestore: PaymentSchedule.fromFirestore,
            toFirestore: (s, _) => s.toFirestore(),
          ),
    );
    expenseRepository = ExpenseRepository(
      firestore.collection('expenses').withConverter<Expense>(
            fromFirestore: Expense.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          ),
      transactionRepository,
      paymentScheduleRepository,
      personRepository,
      installmentRepositoryFor,
      ledgerRepositoryFor,
    );

    repos = AccountDeletionRepositories(
      accountRepository: accountRepository,
      transactionRepository: transactionRepository,
      billRepository: billRepository,
      expenseRepository: expenseRepository,
      personRepository: personRepository,
      ledgerRepositoryFor: ledgerRepositoryFor,
      paymentScheduleRepository: paymentScheduleRepository,
      installmentRepositoryFor: installmentRepositoryFor,
      billOccurrenceRepositoryFor: occurrenceRepositoryFor,
      paymentRepositoryFor: paymentRepositoryFor,
    );
  });

  Future<Account> seedAccount({double openingBalance = 1000}) {
    return accountRepository.createAccount(
      name: 'Doomed Account',
      type: AccountType.bank,
      openingBalance: openingBalance,
      colorValue: 0xFF5B5FEF,
    );
  }

  group('previewAccountDeletionImpact', () {
    test('counts transactions, expenses, affected people, and bills', () async {
      final account = await seedAccount();

      await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 200,
        dateTime: DateTime(2026, 1, 5),
        accountId: account.id,
        categoryId: 'cat-misc',
      );

      final person = await personRepository.createPerson(name: 'Bob', avatarColorValue: 0, openingBalance: 0);
      await expenseRepository.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 1, 6),
        categoryId: 'cat-food',
        accountId: account.id,
        splitType: SplitType.custom,
        participantInputs: [ExpenseParticipantInput(personId: person.id, name: 'Bob', value: 300)],
      );

      await billRepository.createBill(
        name: 'Rent',
        amount: 500,
        dueDate: DateTime(2026, 2, 1),
        recurrence: BillRecurrence.monthly,
        accountId: account.id,
      );

      final impact = await previewAccountDeletionImpact(account.id, repos);

      expect(impact.transactionCount, 2); // plain expense + expense's own transaction
      expect(impact.expenseCount, 1);
      expect(impact.affectedPersonCount, 1);
      expect(impact.billCount, 1);
    });
  });

  group('permanentlyDeleteAccountHistory', () {
    test('deletes every transaction on the account', () async {
      final account = await seedAccount();

      await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 250,
        dateTime: DateTime(2026, 1, 5),
        accountId: account.id,
        categoryId: 'cat-misc',
      );

      await permanentlyDeleteAccountHistory(account.id, repos);

      final remainingTransactions = [
        ...await transactionRepository.getAll(),
        ...await transactionRepository.getTrash(),
      ];
      expect(remainingTransactions, isEmpty);
    });

    test('reverses and removes a split expense\'s ledger entries, its schedule/installments, and the expense itself', () async {
      final account = await seedAccount();
      final person = await personRepository.createPerson(name: 'Bob', avatarColorValue: 0, openingBalance: 0);

      final expense = await expenseRepository.createExpense(
        description: 'Dinner',
        totalAmount: 300,
        date: DateTime(2026, 1, 6),
        categoryId: 'cat-food',
        accountId: account.id,
        splitType: SplitType.custom,
        participantInputs: [ExpenseParticipantInput(personId: person.id, name: 'Bob', value: 300)],
      );
      final personAfterExpense = await personRepository.getByKey(person.id);
      expect(personAfterExpense!.currentBalance, 300); // "gave" moved Bob's balance up

      await permanentlyDeleteAccountHistory(account.id, repos);

      final personAfterDelete = await personRepository.getByKey(person.id);
      expect(personAfterDelete!.currentBalance, 0);

      expect(await ledgerRepositoryFor(person.id).getAll(), isEmpty);
      expect(await ledgerRepositoryFor(person.id).getTrash(), isEmpty);
      expect(await installmentRepositoryFor(expense.scheduleId!).getAll(), isEmpty);
      expect(await paymentScheduleRepository.getByKey(expense.scheduleId!), isNull);
      expect(await expenseRepository.getByKey(expense.id), isNull);
      expect(await transactionRepository.getByKey(expense.transactionId), isNull);
    });

    test('deletes a bill paying from the account, including its occurrences and payments', () async {
      final account = await seedAccount();
      final bill = await billRepository.createBill(
        name: 'Rent',
        amount: 500,
        dueDate: DateTime(2026, 2, 1),
        recurrence: BillRecurrence.monthly,
        accountId: account.id,
      );
      final occurrenceRepository = occurrenceRepositoryFor(bill.id);
      await occurrenceRepository.ensureCurrentOccurrence(bill, const []);
      expect(await occurrenceRepository.getAll(), isNotEmpty);

      await permanentlyDeleteAccountHistory(account.id, repos);

      expect(await billRepository.getByKey(bill.id), isNull);
      expect(await occurrenceRepository.getAll(), isEmpty);
      expect(await occurrenceRepository.getTrash(), isEmpty);
    });

    test('leaves an unrelated person and a bill on a different account untouched', () async {
      final account = await seedAccount();
      final otherAccount = await accountRepository.createAccount(
        name: 'Other',
        type: AccountType.cash,
        openingBalance: 100,
        colorValue: 0xFF111111,
      );
      final unrelatedPerson = await personRepository.createPerson(name: 'Priya', avatarColorValue: 1, openingBalance: 50);
      final otherBill = await billRepository.createBill(
        name: 'Internet',
        amount: 100,
        dueDate: DateTime(2026, 2, 1),
        recurrence: BillRecurrence.monthly,
        accountId: otherAccount.id,
      );

      await permanentlyDeleteAccountHistory(account.id, repos);

      final unrelatedPersonAfter = await personRepository.getByKey(unrelatedPerson.id);
      expect(unrelatedPersonAfter!.currentBalance, 50);
      expect(await billRepository.getByKey(otherBill.id), isNotNull);
    });
  });
}
