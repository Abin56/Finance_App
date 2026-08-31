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
import 'package:finance_app/features/bills/domain/payment_record.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/credit_cards/data/credit_card_deletion_service.dart';
import 'package:finance_app/features/credit_cards/data/credit_card_repository.dart';
import 'package:finance_app/features/credit_cards/data/shared_credit_limit_repository.dart';
import 'package:finance_app/features/credit_cards/data/statement_repository.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/shared_credit_limit.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/emi/data/emi_repository.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/expense/data/expense_repository.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the credit-card-specific extras `permanentlyDeleteCreditCardAndHistory`
/// cascades beyond what the plain account cascade already handles (covered
/// in `account_deletion_service_test.dart`): linked EMIs, statements + their
/// payments, and an orphaned shared credit limit.
void main() {
  late FakeFirebaseFirestore firestore;
  late AccountRepository accountRepository;
  late CreditCardRepository creditCardRepository;
  late SharedCreditLimitRepository sharedCreditLimitRepository;
  late EmiRepository emiRepository;
  late CreditCardDeletionRepositories repos;

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
    return LedgerRepository(collection, PersonRepository(firestore.collection('people').withConverter<Person>(
          fromFirestore: Person.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        )));
  }

  BillOccurrenceRepository occurrenceRepositoryFor(String billId, BillRepository billRepository) {
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

  StatementRepository statementRepositoryFor(String cardId) {
    final collection = firestore
        .collection('creditCards')
        .doc(cardId)
        .collection('statements')
        .withConverter<Statement>(fromFirestore: Statement.fromFirestore, toFirestore: (s, _) => s.toFirestore());
    return StatementRepository(collection);
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();

    accountRepository = AccountRepository(
      firestore.collection('accounts').withConverter<Account>(
            fromFirestore: Account.fromFirestore,
            toFirestore: (a, _) => a.toFirestore(),
          ),
    );
    final transactionRepository = TransactionRepository(
      firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          ),
      accountRepository,
    );
    final billRepository = BillRepository(
      firestore.collection('bills').withConverter<Bill>(fromFirestore: Bill.fromFirestore, toFirestore: (b, _) => b.toFirestore()),
    );
    final personRepository = PersonRepository(
      firestore.collection('people').withConverter<Person>(
            fromFirestore: Person.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          ),
    );
    final paymentScheduleRepository = PaymentScheduleRepository(
      firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
            fromFirestore: PaymentSchedule.fromFirestore,
            toFirestore: (s, _) => s.toFirestore(),
          ),
    );
    final expenseRepository = ExpenseRepository(
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

    sharedCreditLimitRepository = SharedCreditLimitRepository(
      firestore.collection('sharedCreditLimits').withConverter<SharedCreditLimit>(
            fromFirestore: SharedCreditLimit.fromFirestore,
            toFirestore: (s, _) => s.toFirestore(),
          ),
    );
    creditCardRepository = CreditCardRepository(
      firestore.collection('creditCards').withConverter<CreditCardProfile>(
            fromFirestore: CreditCardProfile.fromFirestore,
            toFirestore: (c, _) => c.toFirestore(),
          ),
      sharedCreditLimitRepository: sharedCreditLimitRepository,
    );
    emiRepository = EmiRepository(
      firestore.collection('emis').withConverter<Emi>(
            fromFirestore: Emi.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          ),
      paymentScheduleRepository,
      installmentRepositoryFor,
    );

    final accountDeletionRepositories = AccountDeletionRepositories(
      accountRepository: accountRepository,
      transactionRepository: transactionRepository,
      billRepository: billRepository,
      expenseRepository: expenseRepository,
      personRepository: personRepository,
      ledgerRepositoryFor: ledgerRepositoryFor,
      paymentScheduleRepository: paymentScheduleRepository,
      installmentRepositoryFor: installmentRepositoryFor,
      billOccurrenceRepositoryFor: (billId) => occurrenceRepositoryFor(billId, billRepository),
      paymentRepositoryFor: (billId) {
        final collection = firestore
            .collection('bills')
            .doc(billId)
            .collection('payments')
            .withConverter<PaymentRecord>(
              fromFirestore: PaymentRecord.fromFirestore,
              toFirestore: (p, _) => p.toFirestore(),
            );
        return PaymentRepository(collection, occurrenceRepositoryFor(billId, billRepository));
      },
    );

    repos = CreditCardDeletionRepositories(
      accountDeletionRepositories: accountDeletionRepositories,
      creditCardRepository: creditCardRepository,
      sharedCreditLimitRepository: sharedCreditLimitRepository,
      emiRepository: emiRepository,
      statementRepositoryFor: statementRepositoryFor,
    );
  });

  Future<CreditCardProfile> seedCard({String? sharedLimitId}) async {
    final account = await accountRepository.createAccount(
      name: 'Card Account',
      type: AccountType.card,
      openingBalance: 0,
      colorValue: 0xFF5B5FEF,
    );
    return creditCardRepository.createCard(
      accountId: account.id,
      statementDay: 15,
      paymentDueDay: 5,
      creditLimit: sharedLimitId == null ? 50000 : 0,
      sharedLimitId: sharedLimitId,
    );
  }

  group('previewCreditCardDeletionImpact', () {
    test('reports linked EMI/statement counts and flags an orphaned shared limit', () async {
      final sharedLimit = await sharedCreditLimitRepository.createSharedLimit(name: 'Facility', creditLimit: 100000);
      final card = await seedCard(sharedLimitId: sharedLimit.id);

      await emiRepository.createEmi(
        name: 'Phone EMI',
        principalAmount: 20000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        linkedCreditCardId: card.id,
      );

      final statementRepository = statementRepositoryFor(card.id);
      await statementRepository.add(
        'stmt-1',
        Statement(
          id: 'stmt-1',
          cardId: card.id,
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          generatedDate: DateTime(2026, 1, 31),
          dueDate: DateTime(2026, 2, 5),
          totalAmount: 1000,
          createdAt: DateTime(2026, 1, 31),
        ),
      );

      final impact = await previewCreditCardDeletionImpact(card, repos);

      expect(impact.emiCount, 1);
      expect(impact.statementCount, 1);
      expect(impact.sharedLimitWillBeRemoved, isTrue);
    });

    test('does not flag the shared limit when a sibling card still uses it', () async {
      final sharedLimit = await sharedCreditLimitRepository.createSharedLimit(name: 'Facility', creditLimit: 100000);
      final card = await seedCard(sharedLimitId: sharedLimit.id);
      final siblingAccount = await accountRepository.createAccount(
        name: 'Sibling Card Account',
        type: AccountType.card,
        openingBalance: 0,
        colorValue: 0xFF222222,
      );
      await creditCardRepository.createCard(
        accountId: siblingAccount.id,
        statementDay: 15,
        paymentDueDay: 5,
        creditLimit: 0,
        sharedLimitId: sharedLimit.id,
      );

      final impact = await previewCreditCardDeletionImpact(card, repos);

      expect(impact.sharedLimitWillBeRemoved, isFalse);
    });
  });

  group('permanentlyDeleteCreditCardAndHistory', () {
    test('cascades the linked EMI, statement + its payments, an orphaned shared limit, and both root docs', () async {
      final sharedLimit = await sharedCreditLimitRepository.createSharedLimit(name: 'Facility', creditLimit: 100000);
      final card = await seedCard(sharedLimitId: sharedLimit.id);

      final emi = await emiRepository.createEmi(
        name: 'Phone EMI',
        principalAmount: 20000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        linkedCreditCardId: card.id,
      );

      final statementRepository = statementRepositoryFor(card.id);
      await statementRepository.add(
        'stmt-1',
        Statement(
          id: 'stmt-1',
          cardId: card.id,
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          generatedDate: DateTime(2026, 1, 31),
          dueDate: DateTime(2026, 2, 5),
          totalAmount: 1000,
          createdAt: DateTime(2026, 1, 31),
        ),
      );
      await firestore.collection('creditCards').doc(card.id).collection('statements').doc('stmt-1').collection('statementPayments').add({
        'amount': 500,
      });

      await permanentlyDeleteCreditCardAndHistory(card, repos);

      expect(await emiRepository.getByKey(emi.id), isNull);
      expect(await installmentRepositoryFor(emi.scheduleId).getAll(), isEmpty);
      expect(await statementRepository.getByKey('stmt-1'), isNull);
      final remainingPayments = await firestore
          .collection('creditCards')
          .doc(card.id)
          .collection('statements')
          .doc('stmt-1')
          .collection('statementPayments')
          .get();
      expect(remainingPayments.docs, isEmpty);
      expect(await sharedCreditLimitRepository.getByKey(sharedLimit.id), isNull);
      expect(await creditCardRepository.getByKey(card.id), isNull);
      expect(await accountRepository.getByKey(card.accountId), isNull);
    });

    test('leaves the shared limit alone when a sibling card still uses it', () async {
      final sharedLimit = await sharedCreditLimitRepository.createSharedLimit(name: 'Facility', creditLimit: 100000);
      final card = await seedCard(sharedLimitId: sharedLimit.id);
      final siblingAccount = await accountRepository.createAccount(
        name: 'Sibling Card Account',
        type: AccountType.card,
        openingBalance: 0,
        colorValue: 0xFF222222,
      );
      await creditCardRepository.createCard(
        accountId: siblingAccount.id,
        statementDay: 15,
        paymentDueDay: 5,
        creditLimit: 0,
        sharedLimitId: sharedLimit.id,
      );

      await permanentlyDeleteCreditCardAndHistory(card, repos);

      expect(await sharedCreditLimitRepository.getByKey(sharedLimit.id), isNotNull);
    });
  });
}
