import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/data/installment_payment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/expense/data/expense_repository.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ExpenseRepository repository;
  late PersonRepository personRepository;
  late AccountRepository accountRepository;
  late String accountId;
  late String categoryId;

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

  Future<List<Installment>> installmentsFor(String scheduleId) async {
    final snapshot = await firestore.collection('paymentSchedules').doc(scheduleId).collection('installments').get();
    return snapshot.docs.map((d) => Installment.fromFirestore(d, null)).toList();
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
    final scheduleRepository = PaymentScheduleRepository(scheduleCollection);

    final expenseCollection = firestore.collection('expenses').withConverter<Expense>(
          fromFirestore: Expense.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        );

    repository = ExpenseRepository(
      expenseCollection,
      transactionRepository,
      scheduleRepository,
      personRepository,
      installmentRepositoryFor,
      ledgerRepositoryFor,
    );

    final account = await accountRepository.createAccount(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: 10000,
      colorValue: 0xFF5B5FEF,
    );
    accountId = account.id;
    categoryId = 'cat-food';
  });

  group('ExpenseRepository.resolveShares — equal split', () {
    test('splits evenly with the odd cent remainder on the last participant', () {
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.equal,
        total: 10,
        inputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
          ExpenseParticipantInput(name: 'C'),
        ],
      );

      expect(shares.map((s) => s.share), [3.33, 3.33, 3.34]);
      expect(shares.fold(0.0, (sum, s) => sum + s.share), closeTo(10, 0.001));
    });

    test('splits evenly with no remainder', () {
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.equal,
        total: 100,
        inputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
        ],
      );

      expect(shares.map((s) => s.share), [50, 50]);
    });

    test('supports 5+ participants', () {
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.equal,
        total: 100,
        inputs: List.generate(5, (i) => ExpenseParticipantInput(name: 'P$i')),
      );

      expect(shares, hasLength(5));
      expect(shares.fold(0.0, (sum, s) => sum + s.share), closeTo(100, 0.001));
    });
  });

  group('ExpenseRepository.resolveShares — custom split', () {
    test('accepts an exact match', () {
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.custom,
        total: 100,
        inputs: const [
          ExpenseParticipantInput(name: 'A', value: 60),
          ExpenseParticipantInput(name: 'B', value: 40),
        ],
      );

      expect(shares.map((s) => s.share), [60, 40]);
    });

    test('throws with the exact remaining amount on mismatch', () {
      expect(
        () => ExpenseRepository.resolveShares(
          type: SplitType.custom,
          total: 100,
          inputs: const [
            ExpenseParticipantInput(name: 'A', value: 60),
            ExpenseParticipantInput(name: 'B', value: 30),
          ],
        ),
        throwsA(
          isA<AppException>().having((e) => e.message, 'message', contains('Amount left to assign: 10')),
        ),
      );
    });

    test('supports 5+ participants', () {
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.custom,
        total: 100,
        inputs: const [
          ExpenseParticipantInput(name: 'A', value: 20),
          ExpenseParticipantInput(name: 'B', value: 20),
          ExpenseParticipantInput(name: 'C', value: 20),
          ExpenseParticipantInput(name: 'D', value: 20),
          ExpenseParticipantInput(name: 'E', value: 20),
        ],
      );

      expect(shares, hasLength(5));
    });
  });

  group('ExpenseRepository.resolveShares — percentage split', () {
    test('accepts an exact 100%', () {
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.percentage,
        total: 200,
        inputs: const [
          ExpenseParticipantInput(name: 'A', value: 25),
          ExpenseParticipantInput(name: 'B', value: 75),
        ],
      );

      expect(shares.map((s) => s.share), [50, 150]);
    });

    test('throws with the exact remaining percentage on mismatch', () {
      expect(
        () => ExpenseRepository.resolveShares(
          type: SplitType.percentage,
          total: 200,
          inputs: const [
            ExpenseParticipantInput(name: 'A', value: 25),
            ExpenseParticipantInput(name: 'B', value: 50),
          ],
        ),
        throwsA(
          isA<AppException>().having((e) => e.message, 'message', contains('Percentage left to assign: 25')),
        ),
      );
    });
  });

  group('ExpenseRepository.resolveShares — duplicate participants', () {
    test('rejects the same tracked person added twice', () {
      expect(
        () => ExpenseRepository.resolveShares(
          type: SplitType.equal,
          total: 100,
          inputs: const [
            ExpenseParticipantInput(personId: 'p1', name: 'Alice'),
            ExpenseParticipantInput(personId: 'p1', name: 'Alice'),
          ],
        ),
        throwsA(isA<AppException>().having((e) => e.message, 'message', contains('already in this split'))),
      );
    });

    test('rejects the same free-text name added twice (case-insensitive)', () {
      expect(
        () => ExpenseRepository.resolveShares(
          type: SplitType.equal,
          total: 100,
          inputs: const [
            ExpenseParticipantInput(name: 'Sam'),
            ExpenseParticipantInput(name: 'sam'),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('allows a tracked person and a free-text participant sharing a name', () {
      // Only free-text names collide with each other; a tracked person is
      // matched by id, so this is not a duplicate.
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.equal,
        total: 100,
        inputs: const [
          ExpenseParticipantInput(personId: 'p1', name: 'Sam'),
          ExpenseParticipantInput(name: 'Sam'),
        ],
      );
      expect(shares, hasLength(2));
    });
  });

  group('ExpenseRepository.createExpense', () {
    test('rejects blank description', () async {
      await expectLater(
        repository.createExpense(
          description: '  ',
          totalAmount: 100,
          date: DateTime(2026, 1, 1),
          categoryId: categoryId,
          accountId: accountId,
          splitType: SplitType.none,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects totalAmount <= 0', () async {
      await expectLater(
        repository.createExpense(
          description: 'Dinner',
          totalAmount: 0,
          date: DateTime(2026, 1, 1),
          categoryId: categoryId,
          accountId: accountId,
          splitType: SplitType.none,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('creates a Transaction for the total amount', () async {
      final expense = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.none,
        // resolveShares requires at least one input regardless of split
        // type; SplitType.none simply discards it and returns no
        // participants (see the isEmpty guard ahead of the switch).
        participantInputs: const [ExpenseParticipantInput(name: 'Me')],
      );

      final txSnapshot = await firestore.collection('transactions').doc(expense.transactionId).get();
      expect(txSnapshot.exists, true);
      expect((txSnapshot.data()!['amount'] as num).toDouble(), 100);
    });

    test('unsplit expense (SplitType.none) has no participants and no schedule', () async {
      final expense = await repository.createExpense(
        description: 'Solo lunch',
        totalAmount: 50,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.none,
        participantInputs: const [ExpenseParticipantInput(name: 'Me')],
      );

      expect(expense.participants, isEmpty);
      expect(expense.scheduleId, isNull);
      expect(expense.isSplit, false);
    });

    test('split expense creates a PaymentSchedule + one Installment per participant', () async {
      final expense = await repository.createExpense(
        description: 'Groceries',
        totalAmount: 90,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
          ExpenseParticipantInput(name: 'C'),
        ],
      );

      expect(expense.scheduleId, isNotNull);
      final installments = await installmentsFor(expense.scheduleId!);
      expect(installments, hasLength(3));
      expect(installments.map((i) => i.amountDue), everyElement(30));

      expect(expense.participants, hasLength(3));
      expect(expense.participants.every((p) => p.installmentId != null), true);
    });

    test('posts a LedgerEntry per person-linked participant and updates their currentBalance', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final bob = await personRepository.createPerson(name: 'Bob', avatarColorValue: 0xFF00C2A8, openingBalance: 0);

      await repository.createExpense(
        description: 'Trip',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.custom,
        participantInputs: [
          ExpenseParticipantInput(personId: alice.id, name: 'Alice', value: 60),
          ExpenseParticipantInput(personId: bob.id, name: 'Bob', value: 40),
        ],
      );

      final refreshedAlice = await personRepository.getByKey(alice.id);
      final refreshedBob = await personRepository.getByKey(bob.id);
      expect(refreshedAlice!.currentBalance, 60);
      expect(refreshedBob!.currentBalance, 40);
    });

    test('does not post a LedgerEntry for participants without a personId', () async {
      final expense = await repository.createExpense(
        description: 'Trip',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Guest 1'),
          ExpenseParticipantInput(name: 'Guest 2'),
        ],
      );

      expect(expense.participants.every((p) => p.personId == null), true);
      final people = await personRepository.getAll();
      expect(people, isEmpty);
    });

    test('supports 5+ participants end-to-end', () async {
      final expense = await repository.createExpense(
        description: 'Group trip',
        totalAmount: 500,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: List.generate(5, (i) => ExpenseParticipantInput(name: 'Person $i')),
      );

      expect(expense.participants, hasLength(5));
      final installments = await installmentsFor(expense.scheduleId!);
      expect(installments, hasLength(5));
    });
  });

  group('ExpenseRepository.editExpense', () {
    test('editing only description/notes on a split expense leaves shares/installments untouched', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.custom,
        participantInputs: [ExpenseParticipantInput(personId: alice.id, name: 'Alice', value: 100)],
      );
      final installmentsBefore = await installmentsFor(expense.scheduleId!);

      await repository.editExpense(
        expense: expense,
        currentInstallments: installmentsBefore,
        description: 'Dinner with Alice',
        notes: 'Updated note',
      );

      final expenseSnapshot = await firestore.collection('expenses').doc(expense.id).get();
      expect(expenseSnapshot.data()!['description'], 'Dinner with Alice');
      expect(expenseSnapshot.data()!['notes'], 'Updated note');
      expect((expenseSnapshot.data()!['totalAmount'] as num).toDouble(), 100);

      final installmentsAfter = await installmentsFor(expense.scheduleId!);
      expect(installmentsAfter.single.amountDue, installmentsBefore.single.amountDue);

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, 100);
    });

    test('changing totalAmount on a split expense syncs Installment.amountDue and the linked Transaction.amount', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final bob = await personRepository.createPerson(name: 'Bob', avatarColorValue: 0xFF00C2A8, openingBalance: 0);

      final expense = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: [
          ExpenseParticipantInput(personId: alice.id, name: 'Alice'),
          ExpenseParticipantInput(personId: bob.id, name: 'Bob'),
        ],
      );

      final installmentsBefore = await installmentsFor(expense.scheduleId!);
      expect(installmentsBefore.map((i) => i.amountDue), everyElement(50));

      await repository.editExpense(
        expense: expense,
        currentInstallments: installmentsBefore,
        totalAmount: 200,
        splitType: SplitType.equal,
        participantInputs: [
          ExpenseParticipantInput(personId: alice.id, name: 'Alice'),
          ExpenseParticipantInput(personId: bob.id, name: 'Bob'),
        ],
      );

      // The Expense document itself reflects the new total.
      final expenseSnapshot = await firestore.collection('expenses').doc(expense.id).get();
      expect((expenseSnapshot.data()!['totalAmount'] as num).toDouble(), 200);

      // Every participant's tracking Installment is resynced, not just the
      // Expense document — this is the exact bug report: editing an amount
      // only "saving the current page" and not reflecting globally meant
      // this resync was missing/unreachable from the UI.
      final installmentsAfter = await installmentsFor(expense.scheduleId!);
      expect(installmentsAfter.map((i) => i.amountDue), everyElement(100));

      // The linked account-balance Transaction is resynced too, so History/
      // Reports/Dashboard (which read Transaction.amount) agree with the
      // new total instead of showing the stale original amount.
      final txSnapshot = await firestore.collection('transactions').doc(expense.transactionId).get();
      expect((txSnapshot.data()!['amount'] as num).toDouble(), 200);

      // Each person's pending balance grows by their share delta (50 -> 100).
      final refreshedAlice = await personRepository.getByKey(alice.id);
      final refreshedBob = await personRepository.getByKey(bob.id);
      expect(refreshedAlice!.currentBalance, 100);
      expect(refreshedBob!.currentBalance, 100);
    });

    test(
        'changing totalAmount corrects the original ledger entry in place instead of leaving it stale '
        'next to a separate adjustment entry', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.assignToPerson(
        description: 'Concert tickets',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
      );

      final installmentsBefore = await installmentsFor(expense.scheduleId!);
      await repository.editExpense(
        expense: expense,
        currentInstallments: installmentsBefore,
        totalAmount: 150,
        splitType: SplitType.custom,
        participantInputs: [
          ExpenseParticipantInput(personId: alice.id, name: 'Alice', value: 150),
        ],
      );

      // Exactly one ledger entry still exists for this expense — the
      // original "gave" entry itself now reflects the corrected amount,
      // rather than staying at 100 alongside a second "Correct Balance"
      // entry for the 50 delta. This is the person-statement history line
      // the user tapped to make the edit; it must show the new amount.
      final ledger = ledgerRepositoryFor(alice.id);
      final entries = await ledger.getAll();
      expect(entries, hasLength(1));
      expect(entries.single.type, LedgerEntryType.gave);
      expect(entries.single.amount, 150);

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, 150);
    });

    test('rejects reducing a participant\'s share below what they already paid', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.custom,
        participantInputs: [ExpenseParticipantInput(personId: alice.id, name: 'Alice', value: 100)],
      );

      final installments = await installmentsFor(expense.scheduleId!);
      final installmentPaymentRepository = InstallmentPaymentRepository(
        firestore
            .collection('paymentSchedules')
            .doc(expense.scheduleId!)
            .collection('installments')
            .doc(installments.single.id)
            .collection('payments')
            .withConverter<InstallmentPayment>(
              fromFirestore: InstallmentPayment.fromFirestore,
              toFirestore: (p, _) => p.toFirestore(),
            ),
        installmentRepositoryFor(expense.scheduleId!),
      );
      await installmentPaymentRepository.recordPayment(installments.single, amount: 80, date: DateTime(2026, 1, 2));

      final currentInstallments = await installmentsFor(expense.scheduleId!);
      expect(
        () => repository.editExpense(
          expense: expense,
          currentInstallments: currentInstallments,
          totalAmount: 50,
          splitType: SplitType.custom,
          participantInputs: [ExpenseParticipantInput(personId: alice.id, name: 'Alice', value: 50)],
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('ExpenseRepository.assignToPerson', () {
    test('produces a single-participant expense equivalent to a 100%-custom-split', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.assignToPerson(
        description: 'Concert tickets',
        totalAmount: 150,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
      );

      expect(expense.splitType, SplitType.custom);
      expect(expense.participants, hasLength(1));
      expect(expense.participants.single.personId, alice.id);
      expect(expense.participants.single.share, 150);

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, 150);
    });
  });

  group('ExpenseRepository — due dates', () {
    test('defaults the installment due date to a week after the expense date when not given', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.assignToPerson(
        description: 'Concert tickets',
        totalAmount: 150,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
      );

      final installments = await installmentsFor(expense.scheduleId!);
      expect(installments.single.dueDate, DateTime(2026, 1, 8));
    });

    test('honors an explicit due date when given', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.assignToPerson(
        description: 'Concert tickets',
        totalAmount: 150,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
        dueDate: DateTime(2026, 2, 1),
      );

      final installments = await installmentsFor(expense.scheduleId!);
      expect(installments.single.dueDate, DateTime(2026, 2, 1));
    });

    test('editExpense updates every current installment\'s due date', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.assignToPerson(
        description: 'Concert tickets',
        totalAmount: 150,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
      );

      final installmentsBefore = await installmentsFor(expense.scheduleId!);
      await repository.editExpense(
        expense: expense,
        currentInstallments: installmentsBefore,
        dueDate: DateTime(2026, 3, 1),
      );

      final installmentsAfter = await installmentsFor(expense.scheduleId!);
      expect(installmentsAfter.single.dueDate, DateTime(2026, 3, 1));
    });
  });

  group('ExpenseRepository.deleteExpense', () {
    test('cascades: reverses the account and person balances, soft-deletes every related record', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final accountBefore = await accountRepository.getByKey(accountId);

      final expense = await repository.assignToPerson(
        description: 'Concert tickets',
        totalAmount: 150,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
      );

      await repository.deleteExpense(expense);

      final accountAfter = await accountRepository.getByKey(accountId);
      expect(accountAfter!.currentBalance, accountBefore!.currentBalance);

      final transaction = await firestore.collection('transactions').doc(expense.transactionId).get();
      expect(transaction.data()!['deletedAt'], isNotNull);

      final expenseDoc = await firestore.collection('expenses').doc(expense.id).get();
      expect(expenseDoc.data()!['deletedAt'], isNotNull);

      final installmentDocs = await firestore
          .collection('paymentSchedules')
          .doc(expense.scheduleId)
          .collection('installments')
          .get();
      expect(installmentDocs.docs, isNotEmpty);
      for (final doc in installmentDocs.docs) {
        expect(doc.data()['deletedAt'], isNotNull);
      }

      final scheduleDoc = await firestore.collection('paymentSchedules').doc(expense.scheduleId).get();
      expect(scheduleDoc.data()!['deletedAt'], isNotNull);

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, 0);

      final ledgerDocs = await firestore.collection('people').doc(alice.id).collection('ledger').get();
      expect(ledgerDocs.docs, isNotEmpty);
      for (final doc in ledgerDocs.docs) {
        expect(doc.data()['deletedAt'], isNotNull);
      }
    });
  });

  group('ExpenseRepository.resplitExpense', () {
    test('turns a single-person assignment into an equal multi-way split, rebalancing every person', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final bob = await personRepository.createPerson(name: 'Bob', avatarColorValue: 0xFF00C2A8, openingBalance: 0);

      final expense = await repository.assignToPerson(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
      );
      expect((await personRepository.getByKey(alice.id))!.currentBalance, 100);

      await repository.resplitExpense(
        expense: expense,
        splitType: SplitType.equal,
        participantInputs: [
          const ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(personId: alice.id, name: 'Alice'),
          ExpenseParticipantInput(personId: bob.id, name: 'Bob'),
        ],
      );

      // Me + Alice + Bob split 100 three ways; Alice's balance drops from
      // 100 (full assignment) to her new ~33.33 share, Bob picks up his.
      // Bob is last in the input list, so he absorbs the rounding remainder
      // (33.34); Me and Alice each get 33.33.
      final refreshedAlice = await personRepository.getByKey(alice.id);
      final refreshedBob = await personRepository.getByKey(bob.id);
      expect(refreshedAlice!.currentBalance, closeTo(33.33, 0.001));
      expect(refreshedBob!.currentBalance, closeTo(33.34, 0.001));

      // The linked account Transaction is untouched — no second spend.
      final txSnapshot = await firestore.collection('transactions').doc(expense.transactionId).get();
      expect((txSnapshot.data()!['amount'] as num).toDouble(), 100);
    });

    test('rejects re-splitting once a payment has been collected', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.assignToPerson(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        personId: alice.id,
        personName: 'Alice',
      );

      final installments = await installmentsFor(expense.scheduleId!);
      final installmentPaymentRepository = InstallmentPaymentRepository(
        firestore
            .collection('paymentSchedules')
            .doc(expense.scheduleId!)
            .collection('installments')
            .doc(installments.single.id)
            .collection('payments')
            .withConverter<InstallmentPayment>(
              fromFirestore: InstallmentPayment.fromFirestore,
              toFirestore: (p, _) => p.toFirestore(),
            ),
        installmentRepositoryFor(expense.scheduleId!),
      );
      await installmentPaymentRepository.recordPayment(installments.single, amount: 40, date: DateTime(2026, 1, 2));

      await expectLater(
        repository.resplitExpense(
          expense: expense,
          splitType: SplitType.equal,
          participantInputs: [
            const ExpenseParticipantInput(name: 'Me', isMe: true),
            ExpenseParticipantInput(personId: alice.id, name: 'Alice'),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('ExpenseRepository.settleParticipant', () {
    test('records a payment and reverses the participant\'s pending balance', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.custom,
        participantInputs: [ExpenseParticipantInput(personId: alice.id, name: 'Alice', value: 100)],
      );

      final participant = expense.participants.single;
      final installments = await installmentsFor(expense.scheduleId!);
      final installment = installments.single;

      final paymentCollection = firestore
          .collection('paymentSchedules')
          .doc(expense.scheduleId)
          .collection('installments')
          .doc(installment.id)
          .collection('payments')
          .withConverter<InstallmentPayment>(
            fromFirestore: InstallmentPayment.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          );
      final installmentPaymentRepository = InstallmentPaymentRepository(
        paymentCollection,
        installmentRepositoryFor(expense.scheduleId!),
      );

      await repository.settleParticipant(
        expense: expense,
        participant: participant,
        installment: installment,
        installmentPaymentRepository: installmentPaymentRepository,
        amount: 100,
        date: DateTime(2026, 1, 5),
      );

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, 0);

      final refreshedInstallments = await installmentsFor(expense.scheduleId!);
      expect(refreshedInstallments.single.remainingAmount, 0);
    });

    test('rejects an installment that does not belong to the participant', () async {
      final expense = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
        ],
      );

      final installments = await installmentsFor(expense.scheduleId!);
      final mismatchedInstallment = installments.firstWhere((i) => i.id != expense.participants.first.installmentId);

      final paymentCollection = firestore
          .collection('paymentSchedules')
          .doc(expense.scheduleId)
          .collection('installments')
          .doc(mismatchedInstallment.id)
          .collection('payments')
          .withConverter<InstallmentPayment>(
            fromFirestore: InstallmentPayment.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          );
      final installmentPaymentRepository = InstallmentPaymentRepository(
        paymentCollection,
        installmentRepositoryFor(expense.scheduleId!),
      );

      await expectLater(
        repository.settleParticipant(
          expense: expense,
          participant: expense.participants.first,
          installment: mismatchedInstallment,
          installmentPaymentRepository: installmentPaymentRepository,
          amount: 50,
          date: DateTime(2026, 1, 5),
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('ExpenseRepository — the "Me" participant', () {
    test('resolveShares threads isMe from input to output', () {
      final shares = ExpenseRepository.resolveShares(
        type: SplitType.equal,
        total: 90,
        inputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'Rahul'),
          ExpenseParticipantInput(name: 'John'),
        ],
      );

      expect(shares.where((s) => s.isMe).single.name, 'Me');
      expect(shares.where((s) => !s.isMe), hasLength(2));
    });

    test('createExpense excludes Me from installments and ledger entries', () async {
      final rahul = await personRepository.createPerson(name: 'Rahul', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 900,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: [
          const ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(personId: rahul.id, name: 'Rahul'),
          const ExpenseParticipantInput(name: 'John'),
        ],
      );

      expect(expense.participants, hasLength(3));
      final me = expense.participants.singleWhere((p) => p.isMe);
      expect(me.installmentId, isNull);
      expect(me.share, 300);
      expect(expense.myShare, 300);
      expect(expense.othersShare, 600);

      // Only the 2 non-Me participants get installments.
      final installments = await installmentsFor(expense.scheduleId!);
      expect(installments, hasLength(2));

      // Only Rahul (person-linked, non-Me) gets a ledger entry.
      final refreshedRahul = await personRepository.getByKey(rahul.id);
      expect(refreshedRahul!.currentBalance, 300);
    });

    test('convertToSplit excludes Me from installments the same way', () async {
      final expense = await repository.convertToSplit(
        transactionId: 'existing-txn-me',
        description: 'Groceries',
        totalAmount: 300,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        notes: '',
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'Me', isMe: true),
          ExpenseParticipantInput(name: 'A'),
        ],
      );

      expect(expense.myShare, 150);
      final installments = await installmentsFor(expense.scheduleId!);
      expect(installments, hasLength(1));
    });

    test('rejects a split with only "Me" and no one else', () async {
      await expectLater(
        repository.createExpense(
          description: 'Solo',
          totalAmount: 100,
          date: DateTime(2026, 1, 1),
          categoryId: categoryId,
          accountId: accountId,
          splitType: SplitType.equal,
          participantInputs: const [ExpenseParticipantInput(name: 'Me', isMe: true)],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('Milestone 14 Task 1 — unchecking "Include myself" omits Me entirely, not just a 0 share', () async {
      // The form's "Include myself in this expense" checkbox unchecked
      // means the participant list simply never includes a Me input at
      // all — distinct from convertToAssigned's "Me participates with a
      // 0 share" case. Examples: paying a restaurant bill for friends
      // only, or medicine for a parent — Me never appears in the split.
      final mother = await personRepository.createPerson(name: 'Mother', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.createExpense(
        description: 'Medicine for Mother',
        totalAmount: 500,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.custom,
        participantInputs: [
          ExpenseParticipantInput(personId: mother.id, name: 'Mother', value: 500),
        ],
      );

      expect(expense.meParticipant, isNull);
      expect(expense.participants, hasLength(1));
      expect(expense.myShare, 0);
      expect(expense.othersShare, 500);

      final refreshedMother = await personRepository.getByKey(mother.id);
      expect(refreshedMother!.currentBalance, 500);
    });

    test('Expense.myShare is 0 for a legacy split expense with no Me participant', () async {
      final expense = await repository.createExpense(
        description: 'Old style split',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
        ],
      );

      expect(expense.myShare, 0);
      expect(expense.othersShare, 100);
    });
  });

  group('ExpenseRepository.convertToAssigned', () {
    test('full amount: assigns 100% to the person, Me\'s share is 0, no duplicate Transaction', () async {
      final rahul = await personRepository.createPerson(name: 'Rahul', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final transactionsBefore = await firestore.collection('transactions').get();
      expect(transactionsBefore.docs, isEmpty);

      final expense = await repository.convertToAssigned(
        transactionId: 'existing-txn-assign',
        description: 'Dinner',
        totalAmount: 1200,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        notes: '',
        personId: rahul.id,
        personName: 'Rahul',
      );

      expect(expense.transactionId, 'existing-txn-assign');
      expect(expense.myShare, 0);
      expect(expense.othersShare, 1200);

      final transactionsAfter = await firestore.collection('transactions').get();
      expect(transactionsAfter.docs, isEmpty);

      final refreshedRahul = await personRepository.getByKey(rahul.id);
      expect(refreshedRahul!.currentBalance, 1200);
    });

    test('partial amount: splits between Me and the person by the given share', () async {
      final rahul = await personRepository.createPerson(name: 'Rahul', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final expense = await repository.convertToAssigned(
        transactionId: 'existing-txn-partial',
        description: 'Dinner',
        totalAmount: 1200,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        notes: '',
        personId: rahul.id,
        personName: 'Rahul',
        partialAmount: 800,
      );

      expect(expense.myShare, 400);
      expect(expense.othersShare, 800);

      final refreshedRahul = await personRepository.getByKey(rahul.id);
      expect(refreshedRahul!.currentBalance, 800);
    });

    test('with an existingExpense: converts it in place', () async {
      final rahul = await personRepository.createPerson(name: 'Rahul', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final plainExpense = await repository.createExpense(
        description: 'Groceries',
        totalAmount: 300,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.none,
        participantInputs: const [ExpenseParticipantInput(name: 'Me')],
      );

      final converted = await repository.convertToAssigned(
        existingExpense: plainExpense,
        transactionId: plainExpense.transactionId,
        description: plainExpense.description,
        totalAmount: plainExpense.totalAmount,
        date: plainExpense.date,
        categoryId: plainExpense.categoryId,
        accountId: plainExpense.accountId,
        notes: plainExpense.notes,
        personId: rahul.id,
        personName: 'Rahul',
      );

      expect(converted.id, plainExpense.id);
      expect(converted.transactionId, plainExpense.transactionId);
      expect(converted.myShare, 0);
      expect(converted.othersShare, 300);
    });

    test('rejects converting an already-split expense', () async {
      final alreadySplit = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
        ],
      );

      await expectLater(
        repository.convertToAssigned(
          existingExpense: alreadySplit,
          transactionId: alreadySplit.transactionId,
          description: alreadySplit.description,
          totalAmount: alreadySplit.totalAmount,
          date: alreadySplit.date,
          categoryId: alreadySplit.categoryId,
          accountId: alreadySplit.accountId,
          notes: alreadySplit.notes,
          personId: 'someone',
          personName: 'Someone',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('ExpenseRepository.convertToSplit', () {
    test('with no existingExpense: creates a new split Expense reusing the given transactionId', () async {
      final rahul = await personRepository.createPerson(name: 'Rahul', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);

      final transactionsBefore = await firestore.collection('transactions').get();
      expect(transactionsBefore.docs, isEmpty);

      final expense = await repository.convertToSplit(
        transactionId: 'existing-txn-1',
        description: 'Dinner',
        totalAmount: 800,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        notes: '',
        splitType: SplitType.equal,
        participantInputs: [
          ExpenseParticipantInput(personId: rahul.id, name: 'Rahul'),
          const ExpenseParticipantInput(name: 'You'),
        ],
      );

      expect(expense.transactionId, 'existing-txn-1');
      expect(expense.isSplit, isTrue);
      expect(expense.participants, hasLength(2));

      // No new Transaction document was created — convertToSplit never
      // touches TransactionRepository.
      final transactionsAfter = await firestore.collection('transactions').get();
      expect(transactionsAfter.docs, isEmpty);

      final rahulAfter = await personRepository.getByKey(rahul.id);
      expect(rahulAfter!.currentBalance, 400);
    });

    test('with an existingExpense: converts it in place, keeping its id and transactionId', () async {
      // Simulate a plain (SplitType.none) Expense document already existing —
      // e.g. one created before this conversion feature existed.
      final plainExpense = await repository.createExpense(
        description: 'Groceries',
        totalAmount: 300,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.none,
        participantInputs: const [ExpenseParticipantInput(name: 'Me')],
      );
      expect(plainExpense.isSplit, isFalse);

      final converted = await repository.convertToSplit(
        existingExpense: plainExpense,
        transactionId: plainExpense.transactionId,
        description: plainExpense.description,
        totalAmount: plainExpense.totalAmount,
        date: plainExpense.date,
        categoryId: plainExpense.categoryId,
        accountId: plainExpense.accountId,
        notes: plainExpense.notes,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
        ],
      );

      expect(converted.id, plainExpense.id);
      expect(converted.transactionId, plainExpense.transactionId);
      expect(converted.isSplit, isTrue);

      final refetched = await repository.getByKey(plainExpense.id);
      expect(refetched!.isSplit, isTrue);
      expect(refetched.participants, hasLength(2));
    });

    test('rejects converting an expense that is already split', () async {
      final alreadySplit = await repository.createExpense(
        description: 'Dinner',
        totalAmount: 100,
        date: DateTime(2026, 1, 1),
        categoryId: categoryId,
        accountId: accountId,
        splitType: SplitType.equal,
        participantInputs: const [
          ExpenseParticipantInput(name: 'A'),
          ExpenseParticipantInput(name: 'B'),
        ],
      );

      await expectLater(
        repository.convertToSplit(
          existingExpense: alreadySplit,
          transactionId: alreadySplit.transactionId,
          description: alreadySplit.description,
          totalAmount: alreadySplit.totalAmount,
          date: alreadySplit.date,
          categoryId: alreadySplit.categoryId,
          accountId: alreadySplit.accountId,
          notes: alreadySplit.notes,
          splitType: SplitType.equal,
          participantInputs: const [
            ExpenseParticipantInput(name: 'C'),
            ExpenseParticipantInput(name: 'D'),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects an empty participant list', () async {
      await expectLater(
        repository.convertToSplit(
          transactionId: 'txn-2',
          description: 'Snacks',
          totalAmount: 50,
          date: DateTime(2026, 1, 1),
          categoryId: categoryId,
          accountId: accountId,
          notes: '',
          splitType: SplitType.equal,
          participantInputs: const [],
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
