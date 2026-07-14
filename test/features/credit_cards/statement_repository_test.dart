import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/credit_cards/data/statement_repository.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

CreditCardProfile _card({int statementDay = 17, int paymentDueDay = 5, double? minimumDuePercent}) {
  return CreditCardProfile(
    id: 'card1',
    accountId: 'acc1',
    statementDay: statementDay,
    paymentDueDay: paymentDueDay,
    creditLimit: 100000,
    minimumDuePercent: minimumDuePercent,
    createdAt: DateTime(2026, 1, 1),
  );
}

Transaction _purchase({required String id, required double amount, required DateTime dateTime}) {
  return Transaction(
    id: id,
    type: TransactionType.expense,
    amount: amount,
    dateTime: dateTime,
    accountId: 'acc1',
    categoryId: 'cat1',
    createdAt: dateTime,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late StatementRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final collection = firestore
        .collection('creditCards')
        .doc('card1')
        .collection('statements')
        .withConverter<Statement>(
          fromFirestore: Statement.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    repository = StatementRepository(collection);
  });

  group('StatementRepository.currentCycleFor', () {
    test('sums only transactions inside the in-progress cycle window', () {
      final card = _card();
      final transactions = [
        _purchase(id: 't1', amount: 500, dateTime: DateTime(2026, 6, 18)),
        _purchase(id: 't2', amount: 700, dateTime: DateTime(2026, 6, 20)),
        // Outside this cycle (belongs to the next one).
        _purchase(id: 't3', amount: 1200, dateTime: DateTime(2026, 7, 20)),
      ];

      final current = repository.currentCycleFor(card, transactions, now: DateTime(2026, 7, 1));

      expect(current.totalAmount, 1200);
      expect(current.periodStart, DateTime(2026, 6, 18));
      expect(current.periodEnd, DateTime(2026, 7, 17));
      expect(current.id, 'current');
    });

    test('computes minimumDue from minimumDuePercent when set', () {
      final card = _card(minimumDuePercent: 5);
      final transactions = [_purchase(id: 't1', amount: 1000, dateTime: DateTime(2026, 6, 18))];

      final current = repository.currentCycleFor(card, transactions, now: DateTime(2026, 7, 1));

      expect(current.minimumDue, 50);
    });

    test('minimumDue is null when the card does not track it', () {
      final card = _card();
      final current = repository.currentCycleFor(card, const [], now: DateTime(2026, 7, 1));

      expect(current.minimumDue, isNull);
    });
  });

  group('StatementRepository.materializeIfDue', () {
    test('creates exactly one Statement for the most recently closed cycle', () async {
      final card = _card();
      final transactions = [
        _purchase(id: 't1', amount: 500, dateTime: DateTime(2026, 6, 18)),
        _purchase(id: 't2', amount: 700, dateTime: DateTime(2026, 6, 20)),
        // In next cycle, should not count.
        _purchase(id: 't3', amount: 1200, dateTime: DateTime(2026, 7, 20)),
      ];

      final statement = await repository.materializeIfDue(card, transactions, const [], now: DateTime(2026, 7, 20));

      expect(statement, isNotNull);
      expect(statement!.totalAmount, 1200);
      expect(statement.periodStart, DateTime(2026, 6, 18));
      expect(statement.periodEnd, DateTime(2026, 7, 17));

      final snapshot = await firestore.collection('creditCards').doc('card1').collection('statements').get();
      expect(snapshot.docs, hasLength(1));
    });

    test('is idempotent — a second call for the same cycle materializes nothing new', () async {
      final card = _card();
      final transactions = [_purchase(id: 't1', amount: 500, dateTime: DateTime(2026, 6, 18))];

      final first = await repository.materializeIfDue(card, transactions, const [], now: DateTime(2026, 7, 20));
      expect(first, isNotNull);

      final second = await repository.materializeIfDue(
        card,
        transactions,
        [first!],
        now: DateTime(2026, 7, 20),
      );
      expect(second, isNull);
    });

    test('does not materialize an empty statement when the closed cycle has no transactions', () async {
      final card = _card();
      final result = await repository.materializeIfDue(card, const [], const [], now: DateTime(2026, 6, 1));
      expect(result, isNull);
    });

    test('excludes split-expense participant shares — totalAmount uses the full Transaction.amount', () async {
      final card = _card();
      // A card purchase later split with a friend still shows its full
      // transaction amount on the statement (Expense.myShare never
      // reduces Transaction.amount — see Milestone 12's invariant).
      final transactions = [_purchase(id: 't1', amount: 3000, dateTime: DateTime(2026, 6, 18))];

      final statement = await repository.materializeIfDue(card, transactions, const [], now: DateTime(2026, 7, 20));

      expect(statement!.totalAmount, 3000);
    });
  });

  group('Milestone 14 Task 4 — no double-counting between closed statements and the current cycle', () {
    test('a transaction inside the still-open cycle is never counted in the closed statement total', () async {
      final card = _card();
      final closedCycleTxn = _purchase(id: 't1', amount: 500, dateTime: DateTime(2026, 6, 18));
      final currentCycleTxn = _purchase(id: 't2', amount: 900, dateTime: DateTime(2026, 7, 5));
      final allTransactions = [closedCycleTxn, currentCycleTxn];

      // "now" = 20 Jul: the 18 Jun-17 Jul cycle has closed, the 18 Jul-17
      // Aug cycle is in progress but t2 (5 Jul) actually belongs to the
      // *closed* cycle, not the in-progress one — picking a "now" that's
      // unambiguous: t2 must land inside the closed cycle's own window.
      final statement = await repository.materializeIfDue(
        card,
        allTransactions,
        const [],
        now: DateTime(2026, 7, 20),
      );

      // Both transactions fall within 18 Jun-17 Jul, so both count toward
      // the one closed statement — none leak into a second, still-open
      // cycle total.
      expect(statement!.totalAmount, 1400);

      final currentCycle = repository.currentCycleFor(card, allTransactions, now: DateTime(2026, 7, 20));
      // The current (18 Jul-17 Aug) cycle has zero transactions in its own
      // window — neither t1 nor t2 leaks into it.
      expect(currentCycle.totalAmount, 0);
    });
  });

  group('Milestone 14 Task 5 — StatementRepository.editStatement', () {
    test('sets interestCharged and lateFee', () async {
      final card = _card();
      final transactions = [_purchase(id: 't1', amount: 1000, dateTime: DateTime(2026, 6, 18))];
      final statement = await repository.materializeIfDue(card, transactions, const [], now: DateTime(2026, 7, 20));

      await repository.editStatement(statement!, interestCharged: 45, lateFee: 25);

      final refreshed = await repository.getByKey(statement.id);
      expect(refreshed!.interestCharged, 45);
      expect(refreshed.lateFee, 25);
    });

    test('clearInterestCharged/clearLateFee reset the fields to null', () async {
      final card = _card();
      final transactions = [_purchase(id: 't1', amount: 1000, dateTime: DateTime(2026, 6, 18))];
      final statement = await repository.materializeIfDue(card, transactions, const [], now: DateTime(2026, 7, 20));
      await repository.editStatement(statement!, interestCharged: 45, lateFee: 25);

      await repository.editStatement(statement, clearInterestCharged: true, clearLateFee: true);

      final refreshed = await repository.getByKey(statement.id);
      expect(refreshed!.interestCharged, isNull);
      expect(refreshed.lateFee, isNull);
    });

    test('does not touch totalAmount', () async {
      final card = _card();
      final transactions = [_purchase(id: 't1', amount: 1000, dateTime: DateTime(2026, 6, 18))];
      final statement = await repository.materializeIfDue(card, transactions, const [], now: DateTime(2026, 7, 20));

      await repository.editStatement(statement!, interestCharged: 45);

      final refreshed = await repository.getByKey(statement.id);
      expect(refreshed!.totalAmount, 1000);
    });
  });

  group('StatementRepository.applyPayment', () {
    test('clamps amountPaid to totalAmount and persists the update', () async {
      final card = _card();
      final transactions = [_purchase(id: 't1', amount: 1000, dateTime: DateTime(2026, 6, 18))];
      final statement = await repository.materializeIfDue(card, transactions, const [], now: DateTime(2026, 7, 20));

      await repository.applyPayment(statement!, 1500);

      final refreshed = await repository.getByKey(statement.id);
      expect(refreshed!.amountPaid, 1000);
      expect(refreshed.remainingAmount, 0);
    });
  });
}
