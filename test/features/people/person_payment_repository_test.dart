import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/people/data/person_payment_repository.dart';
import 'package:finance_app/features/people/domain/advance_application.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/domain/person_cycle_statement.dart';
import 'package:finance_app/features/people/domain/person_payment.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/atomic_fake_firestore.dart';

/// Record Payment on mobile — the real repository on an atomic fake
/// Firestore, read back through the Dart statement engine. Mirrors the web
/// app's `person-payment-repository.test.ts` (AMMA: KSEB ₹1,000 + EMI ₹2,000).
void main() {
  late AtomicFakeFirestore db;
  late PersonPaymentRepository repo;
  const uid = 'users/u';
  final sep = StatementCycle(DateTime(2026, 9, 18), DateTime(2026, 10, 17));
  final oct = sep.shift(1);
  final all = StatementCycle(DateTime(1970), DateTime(2027, 1, 17));
  final installments = <StatementInstallment>[];

  CollectionReference<T> col<T>(String path, T Function(DocumentSnapshot<Map<String, dynamic>>, SnapshotOptions?) from,
          Map<String, dynamic> Function(T) to) =>
      db.collection(path).withConverter<T>(fromFirestore: from, toFirestore: (v, _) => to(v));

  CollectionReference<LedgerEntry> ledgerCol() => col('$uid/people/amma/ledger', LedgerEntry.fromFirestore, (e) => e.toFirestore());
  CollectionReference<AdvanceApplication> appCol() =>
      col('$uid/people/amma/advanceApplications', AdvanceApplication.fromFirestore, (a) => a.toFirestore());

  Map<String, dynamic> audit() => {'deletedAt': null, 'lastEditedAt': null, 'editHistory': <dynamic>[]};

  setUp(() async {
    db = AtomicFakeFirestore();
    installments
      ..clear()
      ..add(StatementInstallment(
        id: 'i1', scheduleId: 'sch', sequenceNumber: 1, dueDate: DateTime(2026, 9, 30),
        amountDue: 2000, amountPaid: 0, createdAt: DateTime(2026, 9, 1),
      ));
    repo = PersonPaymentRepository(
      firestore: db,
      people: col('$uid/people', Person.fromFirestore, (p) => p.toFirestore()),
      ledger: ledgerCol(),
      transactions: col('$uid/transactions', Transaction.fromFirestore, (t) => t.toFirestore()),
      accounts: col('$uid/accounts', Account.fromFirestore, (a) => a.toFirestore()),
      expenses: col('$uid/expenses', Expense.fromFirestore, (e) => e.toFirestore()),
      applications: appCol(),
      installmentRef: (s, i) => col('$uid/paymentSchedules/$s/installments', Installment.fromFirestore, (x) => x.toFirestore()).doc(i),
      installmentPaymentRef: (s, i, p) =>
          col('$uid/paymentSchedules/$s/installments/$i/payments', InstallmentPayment.fromFirestore, (x) => x.toFirestore()).doc(p),
      cashLegCategoryId: 'default-both-personal-loan',
    );
    final created = Timestamp.fromDate(DateTime(2026, 1, 1));
    await db.doc('$uid/accounts/sbi').set({
      'name': 'SBI Savings', 'type': 'bank', 'openingBalance': 10000, 'currentBalance': 10000, 'colorValue': 0,
      'createdAt': created, 'isDefault': false, 'notes': '', ...audit(),
    });
    await db.doc('$uid/people/amma').set({
      'name': 'Amma', 'avatarColorValue': 0, 'openingBalance': 0, 'currentBalance': 1000, 'notes': '', 'createdAt': created, ...audit(),
    });
    await db.doc('$uid/people/amma/ledger/kseb').set({
      'personId': 'amma', 'type': 'gave', 'amount': 1000, 'date': Timestamp.fromDate(DateTime(2026, 9, 29)), 'note': 'KSEB bill',
      'transactionRef': null, 'increasesBalance': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 9, 29)), 'sourceKind': 'manual',
      'receivedStatus': 'yetToReceive', ...audit(),
    });
  });

  Future<Person> person() async => (await db.doc('$uid/people/amma').withConverter<Person>(
        fromFirestore: Person.fromFirestore, toFirestore: (p, _) => p.toFirestore()).get()).data()!;
  Future<double> account() async => ((await db.doc('$uid/accounts/sbi').get()).data()!['currentBalance'] as num).toDouble();
  Future<List<LedgerEntry>> entries() async => (await ledgerCol().get()).docs.map((d) => d.data()).toList();
  Future<List<AdvanceApplication>> apps() async => (await appCol().get()).docs.map((d) => d.data()).toList();

  Future<PersonCycleStatement> statement(StatementCycle cycle) async => buildPersonCycleStatement(
        personId: 'amma',
        openingBalance: 0,
        personCreatedAt: DateTime(2026, 1, 1),
        ledger: [
          for (final e in await entries())
            StatementLedgerInput(
              id: e.id, type: e.type.name, amount: e.amount, date: e.date, createdAt: e.createdAt, note: e.note,
              transactionRef: e.transactionRef, parentEntryId: e.parentEntryId, sourceKind: e.sourceKind,
              obligationRef: e.obligationRef, paymentId: e.paymentId, deleted: e.isDeleted,
            ),
        ],
        emis: const [StatementEmiSource(id: 'emi1', name: 'Phone EMI', scheduleId: 'sch', beneficiaryPersonId: 'amma', beneficiaryRepaysInstallments: true)],
        installments: installments,
        advanceApplications: [
          for (final a in await apps())
            AdvanceApplicationInput(
              id: a.id, advanceEntryId: a.advanceEntryId, obligationKey: a.obligationKey, amount: a.amount,
              date: a.date, createdAt: a.createdAt, deleted: a.deletedAt != null,
            ),
        ],
        cycle: cycle,
      );

  /// Automatic allocation over the open obligations — what the sheet submits.
  Future<RecordPaymentInput> input(double amount, {PaymentExtra? extra}) async {
    final s = await statement(all);
    final obligations = [
      for (final r in s.rows.where((r) => r.isObligation && (r.remainingNow ?? 0) > 0))
        PaymentObligation(key: r.key, title: r.title, date: r.date, createdAt: r.createdAt, amount: r.amount, outstanding: r.remainingNow!, side: ObligationSide.theyOwe),
    ];
    final alloc = allocatePayment(obligations: obligations, selectedKeys: obligations.map((o) => o.key), amount: amount);
    return RecordPaymentInput(
      direction: PaymentDirection.theyPaid,
      amount: amount,
      date: DateTime(2026, 10, 2),
      accountId: 'sbi',
      extra: extra,
      lines: [
        for (final l in alloc.lines)
          PaymentLine(
            key: l.key,
            amount: l.amount,
            route: l.key.startsWith('ledger:') ? EntryRoute(l.key.substring(7)) : DerivedRoute(l.key, 'emiInstallment'),
          ),
      ],
    );
  }

  test('Case A — ₹3,000 settles both; one account movement', () async {
    await repo.recordPayment(await person(), await input(3000));
    final s = await statement(sep);
    expect(s.currentPending, 0);
    expect(s.cashReceived, 3000);
    expect(await account(), 13000);
    final txs = (await db.collection('$uid/transactions').get()).docs;
    expect(txs, hasLength(1));
    expect(txs.single.data()['isPersonLedgerMovement'], true);
  });

  test('Case B — ₹2,500 partial, ₹500 carried to next cycle', () async {
    await repo.recordPayment(await person(), await input(2500));
    expect((await statement(sep)).currentPending, 500);
    expect((await statement(sep)).rows.firstWhere((r) => r.key == 'emi-inst:i1').remainingNow, 500);
    expect((await statement(oct)).previousPending, 500);
  });

  test('Case C — ₹5,000: extra must be classified; advance then applied next cycle; revert restores', () async {
    final unclassified = await input(5000);
    await expectLater(repo.recordPayment(await person(), unclassified), throwsA(isA<Exception>()));
    expect(await account(), 10000);

    final id = await repo.recordPayment(await person(), await input(5000, extra: const AdvanceExtra(2000)));
    var s = await statement(sep);
    expect([s.currentPending, s.advanceBalance, s.cashReceived], [0, -2000, 5000]);
    expect(await account(), 15000);
    // Ledger balance = pending + advance − derived EMI obligations (which live on the EMI).
    expect((await person()).currentBalance, 0 + -2000 - 2000);

    installments.add(StatementInstallment(
      id: 'i2', scheduleId: 'sch', sequenceNumber: 2, dueDate: DateTime(2026, 10, 30), amountDue: 1200, amountPaid: 0, createdAt: DateTime(2026, 9, 1),
    ));
    expect((await statement(oct)).currentPending, 1200);
    final advanceEntry = (await entries()).firstWhere((e) => e.isAdvance);
    final available = advanceRemaining(
      [AdvanceSource(entryId: advanceEntry.id, date: advanceEntry.date, createdAt: advanceEntry.createdAt, amount: advanceEntry.amount, side: ObligationSide.theyOwe)],
      [for (final a in await apps()) (advanceEntryId: a.advanceEntryId, amount: a.amount, deleted: a.deletedAt != null)],
    );
    await repo.applyAdvance(await person(), obligationKey: 'emi-inst:i2', uses: drawAdvance(available, ObligationSide.theyOwe, 1200), date: DateTime(2026, 10, 30));
    s = await statement(oct);
    expect([s.currentPending, s.advanceBalance, s.cashReceived], [0, -800, 0]);
    expect(await account(), 15000);

    await repo.revertPayment(await person(), id);
    expect(await account(), 10000);
    expect((await person()).currentBalance, 1000);
    s = await statement(all);
    expect(s.advanceBalance, 0);
    expect(s.rows.firstWhere((r) => r.key == 'emi-inst:i2').remainingNow, 1200);
  });

  test('edit ₹600 → ₹500 moves account, allocation and balance together', () async {
    final id = await repo.recordPayment(await person(), await input(600));
    expect(await account(), 10600);
    await repo.editPayment(
      await person(),
      id,
      RecordPaymentInput(
        direction: PaymentDirection.theyPaid, amount: 500, date: DateTime(2026, 10, 2), accountId: 'sbi',
        lines: const [PaymentLine(key: 'ledger:kseb', amount: 500, route: EntryRoute('kseb'))],
      ),
    );
    expect(await account(), 10500);
    expect((await statement(sep)).rows.firstWhere((r) => r.key == 'ledger:kseb').remainingNow, 500);
    expect((await person()).currentBalance, 500);
  });

  test('extra as income: separate Income transaction, never also a settlement', () async {
    await repo.recordPayment(await person(), await input(5000, extra: const IncomeExtra(2000, categoryId: 'gift', description: 'Gift')));
    final s = await statement(sep);
    expect([s.currentPending, s.advanceBalance, s.cashReceived], [0, 0, 3000]);
    expect(await account(), 15000);
    final txs = (await db.collection('$uid/transactions').get()).docs.map((d) => d.data()).toList();
    expect(txs.map((t) => [t['amount'], t['isPersonLedgerMovement']]).toSet(), {
      [3000.0, true],
      [2000.0, false],
    });
  });
}
