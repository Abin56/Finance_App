import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../../core/errors/app_exception.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../core/payment_schedule/domain/owner_type.dart';
import '../../../core/utils/id_generator.dart';
import '../../accounts/domain/account.dart';
import '../../expense/domain/expense.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_type.dart';
import '../domain/advance_application.dart';
import '../domain/ledger_entry.dart';
import '../domain/ledger_entry_type.dart';
import '../domain/person.dart';
import '../domain/person_payment.dart';

/// Where one allocation line goes — the path that owns that obligation.
sealed class PaymentRoute {
  const PaymentRoute();
}

/// A manual "gave"/"borrowed" entry.
class EntryRoute extends PaymentRoute {
  const EntryRoute(this.parentEntryId);
  final String parentEntryId;
}

/// An opted-in EMI / taken-Loan installment (`emi-inst:` / `loan-inst:` key).
class DerivedRoute extends PaymentRoute {
  const DerivedRoute(this.obligationRef, this.sourceKind);
  final String obligationRef;

  /// emiInstallment / loanInstallment.
  final String sourceKind;
}

/// A split/assigned-expense share: its ledger entry + the expense's tracking installment.
class SplitRoute extends PaymentRoute {
  const SplitRoute({
    required this.parentEntryId,
    required this.sourceKind,
    required this.expenseId,
    required this.participantKey,
    required this.scheduleId,
    required this.installmentId,
  });
  final String parentEntryId;
  final String sourceKind;
  final String expenseId;
  final String participantKey;
  final String scheduleId;
  final String installmentId;
}

class PaymentLine {
  const PaymentLine({required this.key, required this.amount, required this.route});
  final String key;
  final double amount;
  final PaymentRoute route;
}

sealed class PaymentExtra {
  const PaymentExtra(this.amount);
  final double amount;
}

class AdvanceExtra extends PaymentExtra {
  const AdvanceExtra(super.amount);
}

class IncomeExtra extends PaymentExtra {
  const IncomeExtra(super.amount, {required this.categoryId, required this.description});
  final String categoryId;
  final String description;
}

class RecordPaymentInput {
  const RecordPaymentInput({
    required this.direction,
    required this.amount,
    required this.date,
    required this.accountId,
    required this.lines,
    this.extra,
    this.note = '',
  });
  final PaymentDirection direction;

  /// Total money that changed hands — must equal the lines plus the extra.
  final double amount;
  final DateTime date;

  /// Received into (they paid me) / paid from (I paid them).
  final String accountId;
  final List<PaymentLine> lines;
  final PaymentExtra? extra;
  final String note;
}

/// Buffers writes until [flush] and serves reads from its own cache — so
/// revert + record can run in ONE Firestore transaction while every `get`
/// still happens before the first `set`.
class _Session {
  _Session(this.tx);
  final fs.Transaction tx;
  final Map<String, Object?> _cache = {};
  final Map<String, void Function()> _writes = {};

  Future<T?> read<T>(fs.DocumentReference<T> ref) async {
    if (!_cache.containsKey(ref.path)) {
      final snap = await tx.get(ref);
      _cache[ref.path] = snap.data();
    }
    return _cache[ref.path] as T?;
  }

  void write<T>(fs.DocumentReference<T> ref, T data) {
    _cache[ref.path] = data;
    _writes[ref.path] = () => tx.set(ref, data);
  }

  void flush() {
    for (final w in _writes.values) {
      w();
    }
  }
}

/// Record Payment persistence — Dart port of the web app's
/// `lib/repositories/person-payment-repository.ts`; the documents it writes are
/// identical, so a payment recorded on either app is edited / reverted on the
/// other:
///  - ONE cash-leg [Transaction] (`isPersonLedgerMovement`) for the money that
///    settles obligations or is held as advance;
///  - one settlement [LedgerEntry] per obligation, sharing `paymentId`;
///  - for a split share, the tracking [InstallmentPayment] (+ `amountPaid`, +
///    the participant's received status when fully paid);
///  - an advance entry, or a separate normal Income [Transaction] — never both;
///  - the person's cached balance, once.
class PersonPaymentRepository {
  PersonPaymentRepository({
    required this.firestore,
    required this.people,
    required this.ledger,
    required this.transactions,
    required this.accounts,
    required this.expenses,
    required this.applications,
    required this.installmentRef,
    required this.installmentPaymentRef,
    required this.cashLegCategoryId,
  });

  final fs.FirebaseFirestore firestore;
  final fs.CollectionReference<Person> people;
  final fs.CollectionReference<LedgerEntry> ledger;
  final fs.CollectionReference<Transaction> transactions;
  final fs.CollectionReference<Account> accounts;
  final fs.CollectionReference<Expense> expenses;
  final fs.CollectionReference<AdvanceApplication> applications;
  final fs.DocumentReference<Installment> Function(String scheduleId, String installmentId) installmentRef;
  final fs.DocumentReference<InstallmentPayment> Function(String scheduleId, String installmentId, String paymentId)
      installmentPaymentRef;
  final String cashLegCategoryId;

  Future<String> recordPayment(Person person, RecordPaymentInput input) async {
    final paymentId = IdGenerator.generate();
    await firestore.runTransaction((tx) async {
      final s = _Session(tx);
      await _record(s, person, input, paymentId);
      s.flush();
    });
    return paymentId;
  }

  Future<void> revertPayment(Person person, String paymentId) async {
    final pre = await _preload(paymentId);
    await firestore.runTransaction((tx) async {
      final s = _Session(tx);
      await _revert(s, person, pre);
      s.flush();
    });
  }

  /// Revert + record in the same transaction. Advance already applied from
  /// this payment is re-pointed to the new advance, which can't be smaller.
  Future<String> editPayment(Person person, String paymentId, RecordPaymentInput input) async {
    final pre = await _preload(paymentId);
    final applied = round2(pre.apps.where((a) => a.deletedAt == null).fold(0.0, (t, a) => t + a.amount));
    final newAdvance = input.extra is AdvanceExtra ? input.extra!.amount : 0.0;
    if (applied > paymentEpsilon && newAdvance + paymentEpsilon < applied) {
      throw AppException(
        '₹${applied.toStringAsFixed(2)} of this payment\'s advance is already applied — the advance can\'t be less than that.',
      );
    }
    final newId = IdGenerator.generate();
    await firestore.runTransaction((tx) async {
      final s = _Session(tx);
      await _revert(s, person, pre);
      final advanceId = await _record(s, person, input, newId);
      if (advanceId != null) {
        for (final a in pre.apps.where((a) => a.deletedAt == null)) {
          final moved = AdvanceApplication(
            id: IdGenerator.generate(),
            personId: a.personId,
            advanceEntryId: advanceId,
            obligationKey: a.obligationKey,
            amount: a.amount,
            date: a.date,
            createdAt: DateTime.now(),
          );
          s.write(applications.doc(moved.id), moved);
        }
      }
      s.flush();
    });
    return newId;
  }

  /// Applies advance to one obligation — [uses] from [drawAdvance]. No cash or balance move.
  Future<void> applyAdvance(
    Person person, {
    required String obligationKey,
    required List<AdvanceUse> uses,
    required DateTime date,
  }) async {
    if (uses.isEmpty) throw const AppException('Nothing to apply.');
    await firestore.runTransaction((tx) async {
      final s = _Session(tx);
      for (final u in uses) {
        final e = await s.read(ledger.doc(u.advanceEntryId));
        if (e == null || e.isDeleted || !e.isAdvance) throw const AppException('That advance no longer exists.');
        if (u.amount <= 0) throw const AppException('Amount must be greater than 0');
      }
      for (final u in uses) {
        final app = AdvanceApplication(
          id: IdGenerator.generate(),
          personId: person.id,
          advanceEntryId: u.advanceEntryId,
          obligationKey: obligationKey,
          amount: round2(u.amount),
          date: date,
          createdAt: DateTime.now(),
        );
        s.write(applications.doc(app.id), app);
      }
      s.flush();
    });
  }

  Future<void> removeAdvanceApplications(List<AdvanceApplication> apps) async {
    await firestore.runTransaction((tx) async {
      final s = _Session(tx);
      final fresh = <AdvanceApplication>[];
      for (final a in apps) {
        final f = await s.read(applications.doc(a.id));
        if (f != null && f.deletedAt == null) fresh.add(f);
      }
      final now = DateTime.now();
      for (final a in fresh) {
        a.deletedAt = now;
        s.write(applications.doc(a.id), a);
      }
      s.flush();
    });
  }

  // ---------------------------------------------------------------------------

  Future<({List<LedgerEntry> entries, List<AdvanceApplication> apps})> _preload(String paymentId) async {
    final entries = (await ledger.where('paymentId', isEqualTo: paymentId).get()).docs.map((d) => d.data()).where((e) => !e.isDeleted).toList();
    if (entries.isEmpty) throw const AppException('This payment no longer exists.');
    final apps = <AdvanceApplication>[];
    for (final e in entries.where((e) => e.isAdvance)) {
      apps.addAll((await applications.where('advanceEntryId', isEqualTo: e.id).get()).docs.map((d) => d.data()));
    }
    return (entries: entries, apps: apps);
  }

  Future<void> _applyToAccount(_Session s, String accountId, double delta) async {
    final account = await s.read(accounts.doc(accountId));
    if (account == null) throw const AppException('Account not found');
    if (delta == 0) return;
    final newBalance = account.currentBalance + delta;
    account.recordEdit(field: 'currentBalance', oldValue: account.currentBalance.toString(), newValue: newBalance.toString());
    account.currentBalance = newBalance;
    s.write(accounts.doc(account.id), account);
  }

  Future<void> _applyToPerson(_Session s, Person person, double delta) async {
    final fresh = await s.read(people.doc(person.id));
    if (fresh == null) throw const AppException('Person not found');
    if (delta == 0) return;
    final newBalance = fresh.currentBalance + delta;
    fresh.recordEdit(field: 'currentBalance', oldValue: fresh.currentBalance.toString(), newValue: newBalance.toString());
    fresh.currentBalance = newBalance;
    s.write(people.doc(fresh.id), fresh);
  }

  Future<Transaction> _createTransaction(
    _Session s, {
    required TransactionType type,
    required double amount,
    required DateTime date,
    required String accountId,
    required String categoryId,
    required String description,
    required String notes,
    String? linkedPersonId,
    bool isPersonLedgerMovement = false,
  }) async {
    final t = Transaction(
      id: IdGenerator.generate(),
      type: type,
      amount: amount,
      dateTime: date,
      accountId: accountId,
      categoryId: categoryId,
      description: description,
      notes: notes,
      linkedPersonId: linkedPersonId,
      createdAt: DateTime.now(),
      isPersonLedgerMovement: isPersonLedgerMovement,
    );
    await _applyToAccount(s, accountId, t.balanceEffect);
    s.write(transactions.doc(t.id), t);
    return t;
  }

  Future<String?> _record(_Session s, Person person, RecordPaymentInput input, String paymentId) async {
    final lines = [
      for (final l in input.lines)
        if (l.amount > paymentEpsilon) PaymentLine(key: l.key, amount: round2(l.amount), route: l.route),
    ];
    final extra = input.extra != null && input.extra!.amount > paymentEpsilon ? input.extra : null;
    final allocated = round2(lines.fold(0.0, (t, l) => t + l.amount));
    final total = round2(allocated + (extra?.amount ?? 0));
    final cashIn = input.direction == PaymentDirection.theyPaid;

    if (!(input.amount > 0)) throw const AppException('Amount must be greater than 0');
    if ((total - round2(input.amount)).abs() > paymentEpsilon) {
      throw const AppException('Every rupee of the payment must be allocated or explicitly classified.');
    }
    if (lines.isEmpty && extra is! AdvanceExtra) throw const AppException('Select what this payment is for.');
    if (extra is IncomeExtra && !cashIn) throw const AppException('Only money received can be recorded as income.');
    if (input.accountId.isEmpty) {
      throw AppException(cashIn ? 'Choose the account it was received into.' : 'Choose the account it was paid from.');
    }

    if (await s.read(people.doc(person.id)) == null) throw const AppException('Person not found');
    for (final l in lines) {
      final r = l.route;
      final parentId = switch (r) {
        EntryRoute(:final parentEntryId) => parentEntryId,
        SplitRoute(:final parentEntryId) => parentEntryId,
        DerivedRoute() => null,
      };
      if (parentId != null) {
        final parent = await s.read(ledger.doc(parentId));
        if (parent == null || parent.isDeleted) throw const AppException('A selected obligation no longer exists.');
        if (l.amount > parent.amount + paymentEpsilon) throw const AppException('A payment line is more than its obligation.');
      }
      if (r is SplitRoute) {
        final inst = await s.read(installmentRef(r.scheduleId, r.installmentId));
        if (inst == null || inst.isDeleted) throw const AppException('A selected split share no longer exists.');
        if (l.amount > round2(inst.amountDue - inst.amountPaid) + paymentEpsilon) {
          throw const AppException('A split share has less outstanding than this payment line.');
        }
      }
    }

    final settledCash = round2(allocated + (extra is AdvanceExtra ? extra.amount : 0));
    Transaction? cashLeg;
    if (settledCash > paymentEpsilon) {
      cashLeg = await _createTransaction(
        s,
        type: cashIn ? TransactionType.income : TransactionType.expense,
        amount: settledCash,
        date: input.date,
        accountId: input.accountId,
        categoryId: cashLegCategoryId,
        description: person.name,
        notes: input.note.trim(),
        linkedPersonId: person.id,
        isPersonLedgerMovement: true,
      );
    }
    Transaction? income;
    if (extra is IncomeExtra) {
      income = await _createTransaction(
        s,
        type: TransactionType.income,
        amount: extra.amount,
        date: input.date,
        accountId: input.accountId,
        categoryId: extra.categoryId,
        description: extra.description.trim().isEmpty ? '${person.name} — extra' : extra.description.trim(),
        notes: input.note.trim(),
      );
    }

    final type = cashIn ? LedgerEntryType.receivedBack : LedgerEntryType.repaid;
    LedgerEntry entry(double amount, {String? parentEntryId, String? obligationRef, required String sourceKind, String? installmentPaymentRef}) =>
        LedgerEntry(
          id: IdGenerator.generate(),
          personId: person.id,
          type: type,
          amount: amount,
          date: input.date,
          createdAt: DateTime.now(),
          note: input.note.trim(),
          transactionRef: cashLeg?.id,
          parentEntryId: parentEntryId,
          obligationRef: obligationRef,
          sourceKind: sourceKind,
          receivedStatus: 'received',
          paymentId: paymentId,
          installmentPaymentRef: installmentPaymentRef,
          incomeTransactionRef: income?.id,
        );

    final entries = <LedgerEntry>[];
    for (final l in lines) {
      switch (l.route) {
        case EntryRoute(:final parentEntryId):
          entries.add(entry(l.amount, parentEntryId: parentEntryId, sourceKind: 'manual'));
        case DerivedRoute(:final obligationRef, :final sourceKind):
          entries.add(entry(l.amount, obligationRef: obligationRef, sourceKind: sourceKind));
        case final SplitRoute r:
          final ref = await _writeSplitPayment(s, r, l.amount, input.date, input.note.trim());
          entries.add(entry(l.amount, parentEntryId: r.parentEntryId, sourceKind: r.sourceKind, installmentPaymentRef: ref));
      }
    }
    String? advanceId;
    if (extra is AdvanceExtra) {
      final a = entry(extra.amount, sourceKind: 'advance');
      advanceId = a.id;
      entries.add(a);
    }
    await _applyToPerson(s, person, round2(entries.fold(0.0, (t, e) => t + e.signedAmount)));
    for (final e in entries) {
      s.write(ledger.doc(e.id), e);
    }
    return advanceId;
  }

  Future<String> _writeSplitPayment(_Session s, SplitRoute r, double amount, DateTime date, String note) async {
    final ref = installmentRef(r.scheduleId, r.installmentId);
    final inst = (await s.read(ref))!;
    final newPaid = (inst.amountPaid + amount).clamp(0.0, inst.amountDue).toDouble();
    final payment = InstallmentPayment(
      id: IdGenerator.generate(),
      installmentId: inst.id,
      scheduleId: inst.scheduleId,
      ownerType: inst.ownerType,
      ownerId: inst.ownerId,
      amount: amount,
      date: date,
      createdAt: DateTime.now(),
      note: note,
      remainingBalanceAfterPayment: round2(inst.amountDue - newPaid),
    );
    s.write(installmentPaymentRef(r.scheduleId, r.installmentId, payment.id), payment);
    inst.recordEdit(field: 'amountPaid', oldValue: inst.amountPaid.toString(), newValue: newPaid.toString());
    inst.amountPaid = newPaid;
    s.write(ref, inst);
    if (newPaid >= inst.amountDue - paymentEpsilon) await _setParticipantStatus(s, r.expenseId, r.participantKey, 'received');
    return '${r.scheduleId}/${r.installmentId}/${payment.id}';
  }

  static String _participantKey(String? personId, String name) => personId ?? 'name:$name';

  Future<void> _setParticipantStatus(_Session s, String expenseId, String participantKey, String status) async {
    final ref = expenses.doc(expenseId);
    final expense = await s.read(ref);
    if (expense == null) return;
    final i = expense.participants.indexWhere((p) => _participantKey(p.personId, p.name) == participantKey);
    if (i < 0 || expense.participants[i].receivedStatus == status) return;
    final before = expense.participants.map((p) => p.toMap()).toList().toString();
    expense.participants = [
      for (var j = 0; j < expense.participants.length; j++)
        j == i ? expense.participants[j].copyWith(receivedStatus: status) : expense.participants[j],
    ];
    expense.recordEdit(field: 'participants', oldValue: before, newValue: expense.participants.map((p) => p.toMap()).toList().toString());
    s.write(ref, expense);
  }

  Future<void> _revert(_Session s, Person person, ({List<LedgerEntry> entries, List<AdvanceApplication> apps}) pre) async {
    if (await s.read(people.doc(person.id)) == null) throw const AppException('Person not found');
    final fresh = <LedgerEntry>[];
    for (final e in pre.entries) {
      final f = await s.read(ledger.doc(e.id));
      if (f != null && !f.isDeleted) fresh.add(f);
    }
    if (fresh.isEmpty) throw const AppException('This payment was already reverted.');

    // Cash: the People cash leg and any separate income, each reversed out of its account.
    final cashIds = {for (final e in fresh) if (e.transactionRef != null) e.transactionRef!};
    final incomeIds = {for (final e in fresh) if (e.incomeTransactionRef != null) e.incomeTransactionRef!};
    for (final id in {...cashIds, ...incomeIds}) {
      final t = await s.read(transactions.doc(id));
      if (t == null || t.isDeleted) continue;
      final ok = cashIds.contains(id) ? t.isPersonLedgerMovement && t.linkedPersonId == person.id : true;
      if (!ok) continue;
      await _applyToAccount(s, t.accountId, -t.balanceEffect);
      t.markDeleted();
      s.write(transactions.doc(t.id), t);
    }

    // Split tracking.
    for (final e in fresh) {
      final ref = e.installmentPaymentRef;
      if (ref == null) continue;
      final parts = ref.split('/');
      final payRef = installmentPaymentRef(parts[0], parts[1], parts[2]);
      final pay = await s.read(payRef);
      if (pay == null || pay.isDeleted) continue;
      final instRef = installmentRef(parts[0], parts[1]);
      final inst = await s.read(instRef);
      if (inst != null) {
        final newPaid = (inst.amountPaid - pay.amount).clamp(0.0, inst.amountDue).toDouble();
        inst.recordEdit(field: 'amountPaid', oldValue: inst.amountPaid.toString(), newValue: newPaid.toString());
        inst.amountPaid = newPaid;
        s.write(instRef, inst);
        if (newPaid < inst.amountDue - paymentEpsilon && inst.ownerType == OwnerType.splitExpense) {
          final expense = await s.read(expenses.doc(inst.ownerId));
          final participant = expense?.participants.where((p) => p.installmentId == parts[1]).firstOrNull;
          if (participant != null) {
            await _setParticipantStatus(s, inst.ownerId, _participantKey(participant.personId, participant.name), 'yetToReceive');
          }
        }
      }
      pay.markDeleted();
      s.write(payRef, pay);
    }

    // Advance drawn from this payment: un-applied — those obligations reopen.
    final now = DateTime.now();
    for (final a in pre.apps) {
      final f = await s.read(applications.doc(a.id));
      if (f != null && f.deletedAt == null) {
        f.deletedAt = now;
        s.write(applications.doc(f.id), f);
      }
    }

    await _applyToPerson(s, person, round2(-fresh.fold(0.0, (t, e) => t + e.signedAmount)));
    for (final e in fresh) {
      e.markDeleted();
      s.write(ledger.doc(e.id), e);
    }
  }
}
