import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/models/receipt_purpose.dart';
import 'package:finance_app/core/payment_schedule/data/installment_payment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/services/receipt_classification_router.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/emi/data/emi_repository.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/expense/data/expense_repository.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/lending/data/loan_repository.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/savings/data/savings_repository.dart';
import 'package:finance_app/features/savings/domain/savings_goal.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReceiptClassificationRouter router;
  late PersonRepository personRepository;
  late AccountRepository accountRepository;
  late PaymentScheduleRepository scheduleRepository;
  late SavingsRepository savingsRepository;
  late String accountId;
  const categoryId = 'cat-income';

  InstallmentRepository installmentRepositoryFor(String scheduleId) {
    final collection = firestore
        .collection('paymentSchedules')
        .doc(scheduleId)
        .collection('installments')
        .withConverter<Installment>(
          fromFirestore: Installment.fromFirestore,
          toFirestore: (i, _) => i.toFirestore(),
        );
    return InstallmentRepository(collection);
  }

  InstallmentPaymentRepository installmentPaymentRepositoryFor(String scheduleId, String installmentId) {
    final collection = firestore
        .collection('paymentSchedules')
        .doc(scheduleId)
        .collection('installments')
        .doc(installmentId)
        .collection('payments')
        .withConverter<InstallmentPayment>(
          fromFirestore: InstallmentPayment.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    return InstallmentPaymentRepository(collection, installmentRepositoryFor(scheduleId));
  }

  LedgerRepository ledgerRepositoryFor(String personId) {
    final collection = firestore
        .collection('people')
        .doc(personId)
        .collection('ledger')
        .withConverter<LedgerEntry>(
          fromFirestore: LedgerEntry.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        );
    return LedgerRepository(collection, personRepository);
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();

    final personCollection = firestore.collection('people').withConverter<Person>(
          fromFirestore: Person.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    personRepository = PersonRepository(personCollection);

    final accountCollection = firestore.collection('accounts').withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    accountRepository = AccountRepository(accountCollection);

    final transactionCollection = firestore.collection('transactions').withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    final transactionRepository = TransactionRepository(transactionCollection, accountRepository);

    final scheduleCollection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    scheduleRepository = PaymentScheduleRepository(scheduleCollection);

    final savingsCollection = firestore.collection('savingsGoals').withConverter<SavingsGoal>(
          fromFirestore: SavingsGoal.fromFirestore,
          toFirestore: (g, _) => g.toFirestore(),
        );
    savingsRepository = SavingsRepository(savingsCollection);

    router = ReceiptClassificationRouter(
      transactionRepository: transactionRepository,
      ledgerRepositoryFor: ledgerRepositoryFor,
    );

    final account = await accountRepository.createAccount(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: 0,
      colorValue: 0xFF5B5FEF,
    );
    accountId = account.id;
  });

  Future<Transaction?> transactionByAmount(double amount) async {
    final snapshot = await firestore.collection('transactions').get();
    for (final doc in snapshot.docs) {
      if ((doc.data()['amount'] as num).toDouble() == amount) {
        return Transaction.fromFirestore(doc, null);
      }
    }
    return null;
  }

  group('ReceiptClassificationRouter.classify — validation', () {
    test('rejects amount <= 0', () async {
      await expectLater(
        router.classify(
          purpose: ReceiptPurpose.gift,
          amount: 0,
          date: DateTime(2026, 1, 1),
          accountId: accountId,
          categoryId: categoryId,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('friendReturnedMoney without a person target throws', () async {
      await expectLater(
        router.classify(
          purpose: ReceiptPurpose.friendReturnedMoney,
          amount: 100,
          date: DateTime(2026, 1, 1),
          accountId: accountId,
          categoryId: categoryId,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('savingsDeposit without a savings target throws', () async {
      await expectLater(
        router.classify(
          purpose: ReceiptPurpose.savingsDeposit,
          amount: 100,
          date: DateTime(2026, 1, 1),
          accountId: accountId,
          categoryId: categoryId,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('emiPayment without an EMI/installment target throws', () async {
      await expectLater(
        router.classify(
          purpose: ReceiptPurpose.emiPayment,
          amount: 100,
          date: DateTime(2026, 1, 1),
          accountId: accountId,
          categoryId: categoryId,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('loanRepayment without a loan/installment target throws', () async {
      await expectLater(
        router.classify(
          purpose: ReceiptPurpose.loanRepayment,
          amount: 100,
          date: DateTime(2026, 1, 1),
          accountId: accountId,
          categoryId: categoryId,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('ReceiptClassificationRouter.classify — every purpose posts a Transaction', () {
    for (final purpose in [
      ReceiptPurpose.walletDeposit,
      ReceiptPurpose.personalLoanReceived,
      ReceiptPurpose.gift,
      ReceiptPurpose.salary,
      ReceiptPurpose.refund,
      ReceiptPurpose.cashback,
      ReceiptPurpose.investmentReturn,
      ReceiptPurpose.interestReceived,
      ReceiptPurpose.tip,
      ReceiptPurpose.other,
    ]) {
      test('${purpose.name} creates a Transaction for the amount, no other side effects', () async {
        final account = await accountRepository.getByKey(accountId);
        final before = account!.currentBalance;

        final transaction = await router.classify(
          purpose: purpose,
          amount: 250,
          date: DateTime(2026, 1, 1),
          accountId: accountId,
          categoryId: categoryId,
        );

        expect(transaction.amount, 250);
        final refreshedAccount = await accountRepository.getByKey(accountId);
        expect(refreshedAccount!.currentBalance, before + 250);
      });
    }
  });

  group('ReceiptClassificationRouter.classify — friendReturnedMoney', () {
    test('posts a LedgerEntry reducing the person\'s pending balance', () async {
      final alice = await personRepository.createPerson(
        name: 'Alice',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 100,
      );

      final transaction = await router.classify(
        purpose: ReceiptPurpose.friendReturnedMoney,
        amount: 40,
        date: DateTime(2026, 1, 1),
        accountId: accountId,
        categoryId: categoryId,
        target: ReceiptClassificationTarget(person: alice),
      );

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, 60);

      final ledgerSnapshot = await firestore.collection('people').doc(alice.id).collection('ledger').get();
      expect(ledgerSnapshot.docs, hasLength(1));
      expect((ledgerSnapshot.docs.single.data()['transactionRef']), transaction.id);
    });
  });

  group('ReceiptClassificationRouter.classify — savingsDeposit', () {
    test('contributes to the SavingsGoal and posts a Transaction', () async {
      final goal = await savingsRepository.createGoal(name: 'Laptop', targetAmount: 1000);

      await router.classify(
        purpose: ReceiptPurpose.savingsDeposit,
        amount: 300,
        date: DateTime(2026, 1, 1),
        accountId: accountId,
        categoryId: categoryId,
        target: ReceiptClassificationTarget(savingsGoal: goal, savingsRepository: savingsRepository),
      );

      final refreshedGoal = await savingsRepository.getByKey(goal.id);
      expect(refreshedGoal!.currentAmount, 300);

      final transaction = await transactionByAmount(300);
      expect(transaction, isNotNull);
    });
  });

  group('ReceiptClassificationRouter.classify — emiPayment / advanceEmiPayment', () {
    late EmiRepository emiRepository;
    late Emi emi;
    late Installment installment;

    setUp(() async {
      final emiCollection = firestore.collection('emis').withConverter<Emi>(
            fromFirestore: Emi.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );
      emiRepository = EmiRepository(emiCollection, scheduleRepository, installmentRepositoryFor);

      emi = await emiRepository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1200,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
      );

      final installments = await installmentRepositoryFor(emi.scheduleId).getAll();
      installment = installments.first;
    });

    test('emiPayment records an InstallmentPayment against the current installment', () async {
      await router.classify(
        purpose: ReceiptPurpose.emiPayment,
        amount: 100,
        date: DateTime(2026, 1, 1),
        accountId: accountId,
        categoryId: categoryId,
        target: ReceiptClassificationTarget(
          emi: emi,
          installment: installment,
          installmentPaymentRepository: installmentPaymentRepositoryFor(emi.scheduleId, installment.id),
        ),
      );

      final refreshed = await installmentRepositoryFor(emi.scheduleId).getByKey(installment.id);
      expect(refreshed!.amountPaid, 100);
    });

    test('advanceEmiPayment records a payment against a future installment with no special-casing', () async {
      final installments = await installmentRepositoryFor(emi.scheduleId).getAll();
      final future = installments.firstWhere((i) => i.sequenceNumber == 3);

      await router.classify(
        purpose: ReceiptPurpose.advanceEmiPayment,
        amount: 100,
        date: DateTime(2026, 1, 1),
        accountId: accountId,
        categoryId: categoryId,
        target: ReceiptClassificationTarget(
          emi: emi,
          installment: future,
          installmentPaymentRepository: installmentPaymentRepositoryFor(emi.scheduleId, future.id),
        ),
      );

      final refreshed = await installmentRepositoryFor(emi.scheduleId).getByKey(future.id);
      expect(refreshed!.amountPaid, 100);
    });
  });

  group('ReceiptClassificationRouter.classify — loanRepayment', () {
    test('records an InstallmentPayment and posts a LedgerEntry for the loan\'s person', () async {
      final alice = await personRepository.createPerson(
        name: 'Alice',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
      );

      final loanCollection = firestore.collection('loans').withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          );
      final loanRepository = LoanRepository(loanCollection, scheduleRepository, installmentRepositoryFor);

      final loan = await loanRepository.createLoan(
        personId: alice.id,
        loanAmount: 500,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
      );

      final installments = await installmentRepositoryFor(loan.scheduleId).getAll();
      final installment = installments.single;
      expect(installment.ownerType, OwnerType.loan);

      await router.classify(
        purpose: ReceiptPurpose.loanRepayment,
        amount: 500,
        date: DateTime(2026, 1, 15),
        accountId: accountId,
        categoryId: categoryId,
        target: ReceiptClassificationTarget(
          loan: loan,
          person: alice,
          installment: installment,
          installmentPaymentRepository: installmentPaymentRepositoryFor(loan.scheduleId, installment.id),
        ),
      );

      final refreshedInstallment = await installmentRepositoryFor(loan.scheduleId).getByKey(installment.id);
      expect(refreshedInstallment!.remainingAmount, 0);

      final ledgerSnapshot = await firestore.collection('people').doc(alice.id).collection('ledger').get();
      expect(ledgerSnapshot.docs, hasLength(1));
    });
  });

  group('ReceiptClassificationRouter.classify — splitExpenseSettlement', () {
    test('settles a participant: records an InstallmentPayment and reverses their pending ledger balance', () async {
      final rahul = await personRepository.createPerson(
        name: 'Rahul',
        avatarColorValue: 0xFF5B5FEF,
        openingBalance: 0,
      );

      final expenseCollection = firestore.collection('expenses').withConverter<Expense>(
            fromFirestore: Expense.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );
      final expenseRepository = ExpenseRepository(
        expenseCollection,
        TransactionRepository(
          firestore.collection('transactions').withConverter<Transaction>(
                fromFirestore: Transaction.fromFirestore,
                toFirestore: (t, _) => t.toFirestore(),
              ),
          accountRepository,
        ),
        scheduleRepository,
        personRepository,
        installmentRepositoryFor,
        ledgerRepositoryFor,
      );

      final expense = await expenseRepository.createExpense(
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: [
          ExpenseParticipantInput(personId: rahul.id, name: 'Rahul'),
          const ExpenseParticipantInput(name: 'You'),
        ],
      );

      final rahulAfterExpense = await personRepository.getByKey(rahul.id);
      expect(rahulAfterExpense!.currentBalance, 400);

      final participant = expense.participants.firstWhere((p) => p.personId == rahul.id);
      final installments = await installmentRepositoryFor(expense.scheduleId!).getAll();
      final installment = installments.firstWhere((i) => i.id == participant.installmentId);

      await router.classify(
        purpose: ReceiptPurpose.splitExpenseSettlement,
        amount: 400,
        date: DateTime(2026, 1, 10),
        accountId: accountId,
        categoryId: categoryId,
        target: ReceiptClassificationTarget(
          expense: expense,
          expenseParticipant: participant,
          installment: installment,
          installmentPaymentRepository: installmentPaymentRepositoryFor(expense.scheduleId!, installment.id),
          expenseRepository: expenseRepository,
        ),
      );

      final refreshedInstallment = await installmentRepositoryFor(expense.scheduleId!).getByKey(installment.id);
      expect(refreshedInstallment!.remainingAmount, 0);

      final rahulAfterSettlement = await personRepository.getByKey(rahul.id);
      expect(rahulAfterSettlement!.currentBalance, 0);
    });

    test('without a full target throws', () async {
      await expectLater(
        router.classify(
          purpose: ReceiptPurpose.splitExpenseSettlement,
          amount: 100,
          date: DateTime(2026, 1, 1),
          accountId: accountId,
          categoryId: categoryId,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
