import 'package:finance_app/core/dashboard/presentation/providers/upcoming_due_provider.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_occurrence_providers.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/expense_participant.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for [upcomingDueProvider] — the "Spend This Pay Period" card's
/// Upcoming Due aggregation. Every underlying feature stream is overridden
/// directly (rather than seeded through fake_cloud_firestore) since the
/// provider's own job is purely to filter/merge/sort what those streams
/// already report, never to reimplement `.status`/`.remainingAmount`.
void main() {
  final now = DateTime.now();
  final cycleStart = now.subtract(const Duration(days: 10));
  final cutoff = now.add(const Duration(days: 10));
  final cycle = (start: cycleStart, end: cutoff);

  const emiScheduleId = 'emi-schedule';
  const loanScheduleId = 'loan-schedule';

  final emi = Emi(
    id: 'emi1',
    name: 'Fridge EMI',
    principalAmount: 20000,
    startDate: now.subtract(const Duration(days: 400)),
    installmentFrequency: ScheduleType.monthly,
    installmentCount: 24,
    endDate: now.add(const Duration(days: 400)),
    scheduleId: emiScheduleId,
    createdAt: now,
  );

  final loan = Loan(
    id: 'loan1',
    personId: 'p1',
    loanAmount: 5000,
    loanDate: now.subtract(const Duration(days: 100)),
    repaymentType: LoanRepaymentType.installment,
    scheduleId: loanScheduleId,
    createdAt: now,
    name: 'Loan to Sam',
  );

  final card = CreditCardProfile(
    id: 'card1',
    accountId: 'acc1',
    statementDay: 17,
    paymentDueDay: 5,
    creditLimit: 100000,
    createdAt: now,
    lastFourDigits: '9999',
  );

  Installment installment({
    required String id,
    required String scheduleId,
    required OwnerType ownerType,
    required DateTime dueDate,
    double amountDue = 1000,
    double amountPaid = 0,
    bool isSkipped = false,
  }) {
    return Installment(
      id: id,
      scheduleId: scheduleId,
      ownerType: ownerType,
      ownerId: 'owner',
      sequenceNumber: 1,
      dueDate: dueDate,
      amountDue: amountDue,
      amountPaid: amountPaid,
      isSkipped: isSkipped,
      createdAt: now,
    );
  }

  final emiUpcoming = installment(
    id: 'emiA',
    scheduleId: emiScheduleId,
    ownerType: OwnerType.emi,
    dueDate: now.add(const Duration(days: 5)),
  );
  final emiBeyondCutoff = installment(
    id: 'emiB',
    scheduleId: emiScheduleId,
    ownerType: OwnerType.emi,
    dueDate: now.add(const Duration(days: 20)),
  );
  final emiOverdueCarriedOver = installment(
    id: 'emiC',
    scheduleId: emiScheduleId,
    ownerType: OwnerType.emi,
    dueDate: now.subtract(const Duration(days: 40)),
  );
  final emiAlreadyPaid = installment(
    id: 'emiD',
    scheduleId: emiScheduleId,
    ownerType: OwnerType.emi,
    dueDate: now.add(const Duration(days: 2)),
    amountDue: 500,
    amountPaid: 500,
  );

  final loanInstallment = installment(
    id: 'loanA',
    scheduleId: loanScheduleId,
    ownerType: OwnerType.loan,
    dueDate: now.add(const Duration(days: 1)),
  );

  final bill = Bill(
    id: 'bill1',
    name: 'Electricity',
    amount: 2000,
    nextDueDate: now.add(const Duration(days: 3)),
    recurrence: BillRecurrence.monthly,
    createdAt: now,
  );
  final billOccurrence = BillOccurrence(
    id: 'bill1-occ',
    billId: bill.id,
    dueDate: now.add(const Duration(days: 3)),
    amount: 2000,
    createdAt: now,
  );

  final statement = Statement(
    id: 'stmt1',
    cardId: card.id,
    periodStart: now.subtract(const Duration(days: 30)),
    periodEnd: now,
    generatedDate: now,
    dueDate: now.add(const Duration(days: 4)),
    totalAmount: 3000,
    createdAt: now,
  );

  final splitInstallment = installment(
    id: 'splitA',
    scheduleId: 'expense-schedule',
    ownerType: OwnerType.splitExpense,
    dueDate: now.add(const Duration(days: 2)),
    amountDue: 400,
  );
  final expense = Expense(
    id: 'exp1',
    description: 'Dinner',
    totalAmount: 800,
    date: now,
    categoryId: 'cat1',
    accountId: 'acc1',
    transactionId: 'txn1',
    splitType: SplitType.equal,
    participants: [
      ExpenseParticipant(name: 'Me', share: 400, isMe: true, installmentId: null),
      ExpenseParticipant(name: 'Raj', share: 400, installmentId: splitInstallment.id),
    ],
    scheduleId: 'expense-schedule',
    createdAt: now,
  );
  final splitParticipantMe = (
    expense: expense,
    participant: expense.participants[0],
    installment: splitInstallment,
  );
  final splitParticipantOther = (
    expense: expense,
    participant: expense.participants[1],
    installment: splitInstallment,
  );

  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer(
      overrides: [
        activeCreditCardsProvider.overrideWithValue([card]),
        activeEmisProvider.overrideWithValue([emi]),
        activeLoansProvider.overrideWithValue([loan]),
        billsStreamProvider.overrideWith((ref) => Stream.value([bill])),
        // Each module's own `*CycleViewProvider` already runs the shared
        // CycleEngine against that module's anchor — overriding these
        // directly (rather than the raw streams underneath) matches how
        // `upcomingDueProvider` reads them post-consolidation, and lets each
        // fixture's previous/current split be stated explicitly instead of
        // re-deriving it from `now`.
        statementCycleViewProvider.overrideWith(
          (ref, cardId) => cardId == card.id
              ? (previousCyclePending: <Statement>[], current: statement)
              : (previousCyclePending: <Statement>[], current: null),
        ),
        emiCycleViewRecordProvider.overrideWith(
          (ref, e) => e.id == emi.id
              ? (previousCyclePending: [emiOverdueCarriedOver], current: [emiUpcoming, emiBeyondCutoff, emiAlreadyPaid])
              : (previousCyclePending: <Installment>[], current: <Installment>[]),
        ),
        loanCycleViewRecordProvider.overrideWith(
          (ref, l) => l.id == loan.id
              ? (previousCyclePending: <Installment>[], current: [loanInstallment])
              : (previousCyclePending: <Installment>[], current: <Installment>[]),
        ),
        billOccurrenceCycleViewProvider.overrideWith(
          (ref, billId) => billId == bill.id
              ? (previousCyclePending: <BillOccurrence>[], current: billOccurrence)
              : (previousCyclePending: <BillOccurrence>[], current: null),
        ),
        pendingSplitParticipantsProvider.overrideWithValue([splitParticipantMe, splitParticipantOther]),
      ],
    );
    addTearDown(container.dispose);

    await container.read(billsStreamProvider.future);
  });

  test('excludes an item due after the cycle cutoff', () {
    final items = container.read(upcomingDueProvider(cycle));
    expect(items.any((i) => i.routeId == emi.id && i.dueDate == emiBeyondCutoff.dueDate), isFalse);
  });

  test('keeps an unpaid item from before the current cycle visible with no lower bound', () {
    final items = container.read(upcomingDueProvider(cycle));
    final carriedOver = items.where((i) => i.kind == UpcomingDueKind.emi && i.dueDate == emiOverdueCarriedOver.dueDate);
    expect(carriedOver, hasLength(1));
  });

  test('marks an item due before the cycle started as carried over, and one due within it as not', () {
    final items = container.read(upcomingDueProvider(cycle));
    final carriedOver = items.firstWhere((i) => i.dueDate == emiOverdueCarriedOver.dueDate);
    final withinCycle = items.firstWhere((i) => i.dueDate == emiUpcoming.dueDate);
    expect(carriedOver.isCarriedOver, isTrue);
    expect(carriedOver.urgency, PaymentUrgency.carriedForward);
    expect(withinCycle.isCarriedOver, isFalse);
  });

  test('drops an item once fully paid', () {
    final items = container.read(upcomingDueProvider(cycle));
    expect(items.any((i) => i.dueDate == emiAlreadyPaid.dueDate && i.kind == UpcomingDueKind.emi), isFalse);
  });

  test('excludes the payer\'s own split-expense share but includes others\'', () {
    final items = container.read(upcomingDueProvider(cycle));
    final splitItems = items.where((i) => i.kind == UpcomingDueKind.splitExpense);
    expect(splitItems, hasLength(1));
    expect(splitItems.first.title, contains('Raj'));
  });

  test('includes one item per kind for everything due within the cutoff', () {
    final items = container.read(upcomingDueProvider(cycle));
    final kinds = items.map((i) => i.kind).toSet();
    expect(kinds, {
      UpcomingDueKind.creditCard,
      UpcomingDueKind.emi,
      UpcomingDueKind.loan,
      UpcomingDueKind.bill,
      UpcomingDueKind.splitExpense,
    });
  });

  test('sorts overdue items first, then by ascending due date', () {
    final items = container.read(upcomingDueProvider(cycle));
    expect(items.first.dueDate, emiOverdueCarriedOver.dueDate);
    for (var i = 1; i < items.length; i++) {
      final prevOverdue = items[i - 1].urgency.name == 'overdue';
      final curOverdue = items[i].urgency.name == 'overdue';
      if (!prevOverdue && !curOverdue) {
        expect(items[i].dueDate.isBefore(items[i - 1].dueDate), isFalse);
      }
    }
  });
}
