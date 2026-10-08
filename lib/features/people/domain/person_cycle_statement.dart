/// PersonCycleStatement — Dart port of the web app's single People-Ledger
/// calculation (`lib/engines/person-cycle-statement.ts`). Both apps must give
/// identical answers for the same Firestore data; they are held to that by
/// `test/cross_platform_fixtures/person_payment_fixture.json` (the same file
/// the web test suite reads).
///
/// Sign convention: positive = they owe me more, negative = I owe them more.
///
/// Sources, each counted exactly once:
///  - Person ledger entries (manual gave/borrowed, split/assigned shares,
///    settlements). Legacy Loan-generated entries (`transactionRef` = a Loan
///    id) are excluded — Loans are settled from the Loan.
///  - Opted-in person EMI / taken-Loan installments (`beneficiaryRepaysInstallments`)
///    — each installment's `amountDue` on its due date. Paying the lender never
///    settles the person; only a Person settlement does.
///  - Loans with this person as counterparty — each installment, settled by
///    its own `amountPaid`.
///  - Advance: a settlement with `sourceKind == 'advance'` moves the advance
///    balance, never pending. An [AdvanceApplicationInput] settles one
///    obligation from advance (no cash, no ledger balance).
///
/// Cycles run 18th → 17th. Previous pending is rebuilt from dated events, never
/// from today's cached balance.
library;

const int peopleCycleEndDay = 17;
const double _eps = 0.005;

double _r2(double v) => (v * 100).roundToDouble() / 100;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class StatementCycle {
  const StatementCycle(this.start, this.end);

  /// First day, 00:00 local.
  final DateTime start;

  /// Last day, 00:00 local (inclusive).
  final DateTime end;

  static StatementCycle containing(DateTime date, [int endDay = peopleCycleEndDay]) {
    final y = date.year;
    final m = date.month;
    if (date.day > endDay) {
      return StatementCycle(DateTime(y, m, endDay + 1), DateTime(y, m + 1, endDay));
    }
    return StatementCycle(DateTime(y, m - 1, endDay + 1), DateTime(y, m, endDay));
  }

  StatementCycle shift(int offset, [int endDay = peopleCycleEndDay]) =>
      containing(DateTime(end.year, end.month + offset, endDay), endDay);

  bool sameAs(StatementCycle other) => start == other.start;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String formatDate(DateTime d, {bool withYear = false}) {
    final base = '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}';
    return withYear ? '$base ${d.year}' : base;
  }

  String get label {
    if (start.year == end.year) return '${formatDate(start)} – ${formatDate(end)} ${end.year}';
    return '${formatDate(start)} ${start.year} – ${formatDate(end)} ${end.year}';
  }
}

// ---------------------------------------------------------------------------
// Inputs — plain values, so the engine is independent of the Firestore models.
// ---------------------------------------------------------------------------

class StatementLedgerInput {
  const StatementLedgerInput({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.note = '',
    this.increasesBalance = true,
    this.transactionRef,
    this.parentEntryId,
    this.sourceKind,
    this.obligationRef,
    this.paymentId,
    this.deleted = false,
  });

  final String id;

  /// gave / borrowed / receivedBack / repaid / adjustment.
  final String type;
  final double amount;
  final DateTime date;
  final DateTime createdAt;
  final String note;
  final bool increasesBalance;
  final String? transactionRef;
  final String? parentEntryId;
  final String? sourceKind;
  final String? obligationRef;
  final String? paymentId;
  final bool deleted;

  double get signedAmount {
    switch (type) {
      case 'gave':
      case 'repaid':
        return amount;
      case 'borrowed':
      case 'receivedBack':
        return -amount;
      default:
        return increasesBalance ? amount : -amount;
    }
  }
}

class StatementEmiSource {
  const StatementEmiSource({
    required this.id,
    required this.name,
    required this.scheduleId,
    this.beneficiaryPersonId,
    this.beneficiaryRepaysInstallments = false,
    this.isClosed = false,
    this.deleted = false,
  });
  final String id;
  final String name;
  final String scheduleId;
  final String? beneficiaryPersonId;
  final bool beneficiaryRepaysInstallments;
  final bool isClosed;
  final bool deleted;
}

class StatementLoanSource {
  const StatementLoanSource({
    required this.id,
    required this.scheduleId,
    required this.taken,
    this.name,
    this.institutionName,
    this.personId,
    this.beneficiaryPersonId,
    this.beneficiaryRepaysInstallments = false,
    this.isClosed = false,
    this.deleted = false,
  });
  final String id;
  final String scheduleId;

  /// direction == taken (I borrowed) — else given (I lent).
  final bool taken;
  final String? name;
  final String? institutionName;
  final String? personId;
  final String? beneficiaryPersonId;
  final bool beneficiaryRepaysInstallments;
  final bool isClosed;
  final bool deleted;
}

class StatementInstallment {
  const StatementInstallment({
    required this.id,
    required this.scheduleId,
    required this.sequenceNumber,
    required this.dueDate,
    required this.amountDue,
    required this.amountPaid,
    required this.createdAt,
    this.isSkipped = false,
    this.deleted = false,
  });
  final String id;
  final String scheduleId;
  final int sequenceNumber;
  final DateTime dueDate;
  final double amountDue;
  final double amountPaid;
  final DateTime createdAt;
  final bool isSkipped;
  final bool deleted;
}

class StatementLoanPayment {
  const StatementLoanPayment({this.installmentId, required this.amount, required this.date, this.deleted = false});
  final String? installmentId;
  final double amount;
  final DateTime date;
  final bool deleted;
}

class AdvanceApplicationInput {
  const AdvanceApplicationInput({
    required this.id,
    required this.advanceEntryId,
    required this.obligationKey,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.deleted = false,
  });
  final String id;
  final String advanceEntryId;
  final String obligationKey;
  final double amount;
  final DateTime date;
  final DateTime createdAt;
  final bool deleted;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

enum StatementCategory { opening, split, emi, loan, gave, borrowed, adjustment, received, repaid, advance, advanceApplied }

const Map<StatementCategory, String> statementCategoryLabel = {
  StatementCategory.opening: 'Opening balance',
  StatementCategory.split: 'Expense shares',
  StatementCategory.emi: 'EMI',
  StatementCategory.loan: 'Loan installments',
  StatementCategory.gave: 'Money I Gave',
  StatementCategory.borrowed: 'Money I Borrowed',
  StatementCategory.adjustment: 'Adjustments',
  StatementCategory.received: 'Received',
  StatementCategory.repaid: 'Paid',
  StatementCategory.advance: 'Advance',
  StatementCategory.advanceApplied: 'Advance applied',
};

const Map<StatementCategory, String> statementTypeLabel = {
  StatementCategory.opening: 'Opening balance',
  StatementCategory.split: 'Split expense',
  StatementCategory.emi: 'EMI',
  StatementCategory.loan: 'Loan EMI',
  StatementCategory.gave: 'Money I Gave',
  StatementCategory.borrowed: 'Money I Borrowed',
  StatementCategory.adjustment: 'Adjustment',
  StatementCategory.received: 'Settlement',
  StatementCategory.repaid: 'Settlement',
  StatementCategory.advance: 'Advance',
  StatementCategory.advanceApplied: 'Advance applied',
};

class StatementSettles {
  const StatementSettles(this.title, this.originalAmount, this.remainingAfter);
  final String title;
  final double originalAmount;
  final double remainingAfter;
}

class StatementRow {
  const StatementRow({
    required this.key,
    required this.date,
    required this.createdAt,
    required this.isObligation,
    required this.category,
    required this.title,
    required this.amount,
    required this.signedAmount,
    required this.advanceDelta,
    required this.runningBalance,
    this.settles,
    this.settlesKey,
    this.remainingNow,
    this.paymentId,
    this.installmentNumber,
    this.loanId,
  });

  /// `ledger:{id}`, `opening:{personId}`, `emi-inst:{id}`, `loan-inst:{id}`, `loan-pay:…`, `adv-app:{id}`.
  final String key;
  final DateTime date;
  final DateTime createdAt;
  final bool isObligation;
  final StatementCategory category;
  final String title;
  final double amount;

  /// Effect on pending. 0 for an advance.
  final double signedAmount;

  /// Effect on the advance balance (− they paid ahead, + I paid ahead).
  final double advanceDelta;
  final double runningBalance;
  final StatementSettles? settles;
  final String? settlesKey;

  /// What is still open on an obligation today.
  final double? remainingNow;
  final String? paymentId;
  final int? installmentNumber;
  final String? loanId;

  String get typeLabel => statementTypeLabel[category]!;
}

enum StatementDirection { theyOwe, iOwe, settled }

StatementDirection directionOfSigned(double signed) {
  if (signed.abs() < _eps) return StatementDirection.settled;
  return signed > 0 ? StatementDirection.theyOwe : StatementDirection.iOwe;
}

String directionHeadline(StatementDirection d) => switch (d) {
      StatementDirection.theyOwe => 'They owe you',
      StatementDirection.iOwe => 'You owe them',
      StatementDirection.settled => 'Settled',
    };

class PersonCycleStatement {
  const PersonCycleStatement({
    required this.personId,
    required this.cycle,
    required this.previousPending,
    required this.cycleActivity,
    required this.cycleSettlements,
    required this.currentPending,
    required this.previousAdvance,
    required this.advanceBalance,
    required this.cashReceived,
    required this.cashPaid,
    required this.rows,
  });

  final String personId;
  final StatementCycle cycle;
  final double previousPending;
  final double cycleActivity;
  final double cycleSettlements;
  final double currentPending;

  /// Advance held (− = they paid me ahead). Ledger balance = pending + advance.
  final double previousAdvance;
  final double advanceBalance;

  /// Real money that changed hands this cycle (never an advance application).
  final double cashReceived;
  final double cashPaid;
  final List<StatementRow> rows;

  StatementDirection get direction => directionOfSigned(currentPending);
  double get amount => direction == StatementDirection.settled ? 0 : currentPending.abs();
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class _Event {
  _Event({
    required this.key,
    required this.date,
    required this.createdAt,
    required this.order,
    required this.isObligation,
    required this.category,
    required this.title,
    required this.amount,
    required this.signedAmount,
    this.advanceDelta = 0,
    this.settlesKey,
    this.paymentId,
    this.installmentNumber,
    this.loanId,
  });
  final String key;
  final DateTime date;
  final DateTime createdAt;
  final int order;
  final bool isObligation;
  final StatementCategory category;
  final String title;
  final double amount;
  final double signedAmount;
  final double advanceDelta;
  final String? settlesKey;
  final String? paymentId;
  final int? installmentNumber;
  final String? loanId;
}

StatementCategory _ledgerCategory(StatementLedgerInput e) {
  switch (e.type) {
    case 'gave':
      return e.sourceKind == 'splitExpense' ? StatementCategory.split : StatementCategory.gave;
    case 'borrowed':
      return StatementCategory.borrowed;
    case 'receivedBack':
      return e.sourceKind == 'advance' ? StatementCategory.advance : StatementCategory.received;
    case 'repaid':
      return e.sourceKind == 'advance' ? StatementCategory.advance : StatementCategory.repaid;
    default:
      return StatementCategory.adjustment;
  }
}

final RegExp _splitPrefix = RegExp(r'^Split:\s*');
final RegExp _receivedPrefix = RegExp(r'^(Split settlement|Received):');

String _ledgerTitle(StatementLedgerInput e, StatementCategory c) {
  final note = e.note.trim();
  if (c == StatementCategory.split || e.sourceKind == 'assignedExpense') {
    final t = note.replaceFirst(_splitPrefix, '');
    return t.isEmpty ? 'Expense share' : t;
  }
  if (c == StatementCategory.received) {
    if (_receivedPrefix.hasMatch(note)) return 'Payment received';
    return note.isNotEmpty && note != 'Settled all' ? note : 'Payment received';
  }
  if (c == StatementCategory.repaid) return note.isNotEmpty && note != 'Settled all' ? note : 'Payment made';
  if (c == StatementCategory.advance) {
    if (note.isNotEmpty) return note;
    return e.type == 'receivedBack' ? 'Advance received' : 'Advance paid';
  }
  if (note.isNotEmpty) return note;
  return c == StatementCategory.gave
      ? 'Money I Gave'
      : c == StatementCategory.borrowed
          ? 'Money I Borrowed'
          : 'Adjustment';
}

bool _beneficiaryOwes(String? beneficiary, bool repays, bool deleted, String personId) =>
    !deleted && beneficiary == personId && repays;

List<_Event> _collectEvents({
  required String personId,
  required double openingBalance,
  required DateTime personCreatedAt,
  required List<StatementLedgerInput> ledger,
  required Set<String> loanIds,
  required List<StatementEmiSource> emis,
  required List<StatementLoanSource> loans,
  required List<StatementInstallment> installments,
  required List<StatementLoanPayment> loanPayments,
  required List<AdvanceApplicationInput> applications,
}) {
  final events = <_Event>[];
  final seen = <String>{};
  void push(_Event e) {
    if (seen.add(e.key)) events.add(e);
  }

  if (openingBalance.abs() >= _eps) {
    push(_Event(
      key: 'opening:$personId',
      date: personCreatedAt,
      createdAt: personCreatedAt,
      order: 0,
      isObligation: true,
      category: StatementCategory.opening,
      title: 'Opening balance',
      amount: openingBalance.abs(),
      signedAmount: openingBalance,
    ));
  }

  final active = ledger.where((e) => !e.deleted && !(e.transactionRef != null && loanIds.contains(e.transactionRef))).toList();
  final giveByRef = <String, StatementLedgerInput>{};
  for (final e in active) {
    if (e.type == 'gave' && e.transactionRef != null) giveByRef[e.transactionRef!] = e;
  }
  for (final e in active) {
    final c = _ledgerCategory(e);
    final isSettlement = e.type == 'receivedBack' || e.type == 'repaid';
    String? settlesKey;
    if (isSettlement) {
      if (e.obligationRef != null) {
        settlesKey = e.obligationRef;
      } else if (e.parentEntryId != null) {
        settlesKey = 'ledger:${e.parentEntryId}';
      } else if (e.transactionRef != null && giveByRef.containsKey(e.transactionRef)) {
        settlesKey = 'ledger:${giveByRef[e.transactionRef]!.id}';
      }
    }
    final isAdvance = c == StatementCategory.advance;
    push(_Event(
      key: 'ledger:${e.id}',
      date: e.date,
      createdAt: e.createdAt,
      order: isSettlement ? 2 : 1,
      isObligation: !isSettlement,
      category: c,
      title: _ledgerTitle(e, c),
      amount: e.amount,
      signedAmount: isAdvance ? 0 : e.signedAmount,
      advanceDelta: isAdvance ? e.signedAmount : 0,
      settlesKey: isAdvance ? null : settlesKey,
      paymentId: e.paymentId,
    ));
  }

  // Opted-in person EMI / taken-Loan installments.
  final bySchedule = <String, (String kind, String name, bool isClosed)>{};
  for (final emi in emis) {
    if (_beneficiaryOwes(emi.beneficiaryPersonId, emi.beneficiaryRepaysInstallments, emi.deleted, personId)) {
      bySchedule[emi.scheduleId] = ('emi', emi.name.trim().isEmpty ? 'EMI' : emi.name.trim(), emi.isClosed);
    }
  }
  for (final loan in loans) {
    if (loan.taken && _beneficiaryOwes(loan.beneficiaryPersonId, loan.beneficiaryRepaysInstallments, loan.deleted, personId)) {
      final n = (loan.name?.trim().isNotEmpty ?? false)
          ? loan.name!.trim()
          : (loan.institutionName?.trim().isNotEmpty ?? false)
              ? loan.institutionName!.trim()
              : 'Loan EMI';
      bySchedule[loan.scheduleId] = ('loan', n, loan.isClosed);
    }
  }
  final seenInst = <String>{};
  for (final inst in installments) {
    final source = bySchedule[inst.scheduleId];
    if (source == null || inst.deleted || seenInst.contains(inst.id)) continue;
    if (inst.isSkipped && inst.amountPaid <= 0) continue;
    if (source.$3 && inst.amountPaid <= 0) continue;
    seenInst.add(inst.id);
    push(_Event(
      key: '${source.$1 == 'emi' ? 'emi-inst' : 'loan-inst'}:${inst.id}',
      date: inst.dueDate,
      createdAt: inst.createdAt,
      order: 1,
      isObligation: true,
      category: StatementCategory.emi,
      title: source.$2,
      amount: inst.amountDue,
      signedAmount: inst.amountDue,
      installmentNumber: inst.sequenceNumber,
    ));
  }

  // Loans with this person as counterparty.
  final paymentsByInst = <String, List<StatementLoanPayment>>{};
  for (final p in loanPayments) {
    if (p.deleted || p.installmentId == null || p.amount <= 0) continue;
    paymentsByInst.putIfAbsent(p.installmentId!, () => []).add(p);
  }
  for (final loan in loans) {
    if (loan.deleted || loan.personId != personId) continue;
    final sign = loan.taken ? -1.0 : 1.0;
    final name = (loan.name?.trim().isNotEmpty ?? false) ? loan.name!.trim() : 'Loan';
    final scheduled = installments.where((i) => i.scheduleId == loan.scheduleId && !i.deleted && !i.isSkipped).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    for (final inst in scheduled) {
      if (loan.isClosed && inst.amountPaid <= 0) continue;
      final obligationKey = 'loan-inst:${inst.id}';
      push(_Event(
        key: obligationKey,
        date: inst.dueDate,
        createdAt: inst.createdAt,
        order: 1,
        isObligation: true,
        category: StatementCategory.loan,
        title: name,
        amount: inst.amountDue,
        signedAmount: sign * inst.amountDue,
        installmentNumber: inst.sequenceNumber,
        loanId: loan.id,
      ));
      final paid = _r2(inst.amountPaid < inst.amountDue ? inst.amountPaid : inst.amountDue);
      if (paid <= 0) continue;
      var left = paid;
      final dated = [...(paymentsByInst[inst.id] ?? const <StatementLoanPayment>[])]..sort((a, b) => a.date.compareTo(b.date));
      final parts = <(double, DateTime)>[];
      for (final p in dated) {
        if (left <= 0) break;
        final a = _r2(p.amount < left ? p.amount : left);
        parts.add((a, p.date));
        left = _r2(left - a);
      }
      if (left > 0) parts.add((left, inst.dueDate));
      for (var n = 0; n < parts.length; n++) {
        push(_Event(
          key: 'loan-pay:${inst.id}:$n',
          date: parts[n].$2,
          createdAt: parts[n].$2,
          order: 2,
          isObligation: false,
          category: loan.taken ? StatementCategory.repaid : StatementCategory.received,
          title: loan.taken ? 'Paid · $name' : 'Received · $name',
          amount: parts[n].$1,
          signedAmount: -sign * parts[n].$1,
          settlesKey: obligationKey,
          loanId: loan.id,
        ));
      }
    }
  }

  // Advance applications — only against an existing advance and obligation, in the covering direction.
  final advanceSign = <String, double>{};
  for (final e in events) {
    if (e.category == StatementCategory.advance && e.key.startsWith('ledger:')) {
      advanceSign[e.key.substring(7)] = e.advanceDelta.sign;
    }
  }
  final obligations = {for (final e in events.where((e) => e.isObligation)) e.key: e};
  for (final app in applications) {
    if (app.deleted || app.amount <= 0) continue;
    final aSign = advanceSign[app.advanceEntryId];
    final obligation = obligations[app.obligationKey];
    if (aSign == null || obligation == null) continue;
    final oSign = obligation.signedAmount.sign;
    if (oSign == 0 || aSign != -oSign) continue;
    push(_Event(
      key: 'adv-app:${app.id}',
      date: app.date,
      createdAt: app.createdAt,
      order: 2,
      isObligation: false,
      category: StatementCategory.advanceApplied,
      title: 'Advance applied',
      amount: app.amount,
      signedAmount: -oSign * app.amount,
      advanceDelta: oSign * app.amount,
      settlesKey: app.obligationKey,
    ));
  }
  return events;
}

int _compareEvents(_Event a, _Event b) {
  var c = _day(a.date).compareTo(_day(b.date));
  if (c != 0) return c;
  c = a.order.compareTo(b.order);
  if (c != 0) return c;
  c = a.date.compareTo(b.date);
  if (c != 0) return c;
  c = a.createdAt.compareTo(b.createdAt);
  if (c != 0) return c;
  return a.key.compareTo(b.key);
}

const _remainingCategories = {
  StatementCategory.split,
  StatementCategory.gave,
  StatementCategory.borrowed,
  StatementCategory.emi,
  StatementCategory.loan,
};

PersonCycleStatement buildPersonCycleStatement({
  required String personId,
  required double openingBalance,
  required DateTime personCreatedAt,
  required List<StatementLedgerInput> ledger,
  required StatementCycle cycle,
  Set<String> loanIds = const {},
  List<StatementEmiSource> emis = const [],
  List<StatementLoanSource> loans = const [],
  List<StatementInstallment> installments = const [],
  List<StatementLoanPayment> loanPayments = const [],
  List<AdvanceApplicationInput> advanceApplications = const [],
}) {
  final events = _collectEvents(
    personId: personId,
    openingBalance: openingBalance,
    personCreatedAt: personCreatedAt,
    ledger: ledger,
    loanIds: loanIds,
    emis: emis,
    loans: loans,
    installments: installments,
    loanPayments: loanPayments,
    applications: advanceApplications,
  )..sort(_compareEvents);
  final startIdx = _day(cycle.start);
  final endIdx = _day(cycle.end);

  final obligationByKey = {for (final e in events.where((e) => e.isObligation)) e.key: e};
  final settledSoFar = <String, double>{};
  final remainingAfter = <String, double>{};
  for (final e in events) {
    if (e.isObligation || e.settlesKey == null) continue;
    final original = obligationByKey[e.settlesKey];
    if (original == null) continue;
    final next = _r2((settledSoFar[e.settlesKey] ?? 0) + e.amount);
    settledSoFar[e.settlesKey!] = next;
    final rem = _r2(original.amount - next);
    remainingAfter[e.key] = rem < 0 ? 0 : rem;
  }

  var previousPending = 0.0;
  var previousAdvance = 0.0;
  var advanceBalance = 0.0;
  var running = 0.0;
  final rows = <StatementRow>[];
  for (final e in events) {
    final d = _day(e.date);
    if (d.isBefore(startIdx)) {
      previousPending = _r2(previousPending + e.signedAmount);
      previousAdvance = _r2(previousAdvance + e.advanceDelta);
      continue;
    }
    if (d.isAfter(endIdx)) continue;
    if (rows.isEmpty) {
      running = previousPending;
      advanceBalance = previousAdvance;
    }
    advanceBalance = _r2(advanceBalance + e.advanceDelta);
    running = _r2(running + e.signedAmount);
    final original = e.settlesKey != null ? obligationByKey[e.settlesKey] : null;
    double? remainingNow;
    if (e.isObligation && _remainingCategories.contains(e.category)) {
      final r = _r2(e.amount - (settledSoFar[e.key] ?? 0));
      remainingNow = r < 0 ? 0 : r;
    }
    rows.add(StatementRow(
      key: e.key,
      date: e.date,
      createdAt: e.createdAt,
      isObligation: e.isObligation,
      category: e.category,
      title: e.title,
      amount: e.amount,
      signedAmount: e.signedAmount,
      advanceDelta: e.advanceDelta,
      runningBalance: running,
      settles: original == null ? null : StatementSettles(original.title, original.amount, remainingAfter[e.key] ?? 0),
      settlesKey: original == null ? null : e.settlesKey,
      remainingNow: remainingNow,
      paymentId: e.paymentId,
      installmentNumber: e.installmentNumber,
      loanId: e.loanId,
    ));
  }
  if (rows.isEmpty) advanceBalance = previousAdvance;

  final cycleActivity = _r2(rows.where((r) => r.isObligation).fold(0.0, (s, r) => s + r.signedAmount));
  final cycleSettlements = _r2(rows.where((r) => !r.isObligation).fold(0.0, (s, r) => s + r.signedAmount));
  final current = _r2(previousPending + cycleActivity + cycleSettlements);
  var cashReceived = 0.0;
  var cashPaid = 0.0;
  for (final r in rows) {
    if (r.category == StatementCategory.received || (r.category == StatementCategory.advance && r.advanceDelta < 0)) {
      cashReceived = _r2(cashReceived + r.amount);
    } else if (r.category == StatementCategory.repaid || (r.category == StatementCategory.advance && r.advanceDelta > 0)) {
      cashPaid = _r2(cashPaid + r.amount);
    }
  }
  return PersonCycleStatement(
    personId: personId,
    cycle: cycle,
    previousPending: previousPending,
    cycleActivity: cycleActivity,
    cycleSettlements: cycleSettlements,
    currentPending: current.abs() < _eps ? 0 : current,
    previousAdvance: previousAdvance.abs() < _eps ? 0 : previousAdvance,
    advanceBalance: advanceBalance.abs() < _eps ? 0 : advanceBalance,
    cashReceived: cashReceived,
    cashPaid: cashPaid,
    rows: rows,
  );
}
