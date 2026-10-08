import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../accounts/domain/account.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../expense/domain/expense.dart';
import '../../../lending/domain/loan_direction.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../data/person_payment_repository.dart';
import '../../domain/advance_application.dart';
import '../../domain/ledger_entry.dart';
import '../../domain/ledger_entry_type.dart';
import '../../domain/person_cycle_statement.dart';
import '../../domain/person_payment.dart';
import 'people_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart' show PendingSplitParticipant;
import 'person_pending_participants_providers.dart';

/// Live `people/{personId}/advanceApplications` (active only).
final advanceApplicationsProvider = StreamProvider.autoDispose.family<List<AdvanceApplication>, String>((ref, personId) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  return firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.people)
      .doc(personId)
      .collection(FirestoreCollections.advanceApplications)
      .withConverter<AdvanceApplication>(fromFirestore: AdvanceApplication.fromFirestore, toFirestore: (a, _) => a.toFirestore())
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).where((a) => a.deletedAt == null).toList());
});

/// Everything the People statement engine reads for one person, from the
/// same live sources the rest of the app uses. Null while loading.
class PersonStatementSources {
  const PersonStatementSources({
    required this.personId,
    required this.openingBalance,
    required this.createdAt,
    required this.ledger,
    required this.ledgerEntries,
    required this.emis,
    required this.loans,
    required this.loanIds,
    required this.installments,
    required this.applications,
  });
  final String personId;
  final double openingBalance;
  final DateTime createdAt;
  final List<StatementLedgerInput> ledger;
  final List<LedgerEntry> ledgerEntries;
  final List<StatementEmiSource> emis;
  final List<StatementLoanSource> loans;
  final Set<String> loanIds;
  final List<StatementInstallment> installments;
  final List<AdvanceApplication> applications;

  PersonCycleStatement statement(StatementCycle cycle) => buildPersonCycleStatement(
        personId: personId,
        openingBalance: openingBalance,
        personCreatedAt: createdAt,
        ledger: ledger,
        cycle: cycle,
        loanIds: loanIds,
        emis: emis,
        loans: loans,
        installments: installments,
        advanceApplications: [
          for (final a in applications)
            AdvanceApplicationInput(
              id: a.id,
              advanceEntryId: a.advanceEntryId,
              obligationKey: a.obligationKey,
              amount: a.amount,
              date: a.date,
              createdAt: a.createdAt,
              deleted: a.deletedAt != null,
            ),
        ],
      );

  /// The whole history through the end of the current cycle (no future installments).
  PersonCycleStatement allTime() =>
      statement(StatementCycle(DateTime(1970), StatementCycle.containing(DateTime.now()).end));

  /// Advance entries with what is left of each (oldest first).
  List<AdvanceSource> advances() => advanceRemaining(
        [
          for (final e in ledgerEntries)
            if (!e.isDeleted && e.isAdvance)
              AdvanceSource(
                entryId: e.id,
                date: e.date,
                createdAt: e.createdAt,
                amount: e.amount,
                side: e.type == LedgerEntryType.receivedBack ? ObligationSide.theyOwe : ObligationSide.iOwe,
              ),
        ],
        [for (final a in applications) (advanceEntryId: a.advanceEntryId, amount: a.amount, deleted: a.deletedAt != null)],
      );
}

final personStatementSourcesProvider = Provider.autoDispose.family<PersonStatementSources?, String>((ref, personId) {
  final person = ref.watch(peopleStreamProvider).value?.where((p) => p.id == personId).firstOrNull;
  final ledgerAsync = ref.watch(ledgerStreamProvider(personId));
  final appsAsync = ref.watch(advanceApplicationsProvider(personId));
  final emis = ref.watch(emisStreamProvider).value;
  final loans = ref.watch(loansStreamProvider).value;
  final trashedLoans = ref.watch(loansTrashStreamProvider).value ?? const [];
  if (person == null || ledgerAsync.value == null || appsAsync.value == null || emis == null || loans == null) return null;

  final schedules = <String>{
    for (final e in emis)
      if (e.beneficiaryPersonId == personId) e.scheduleId,
    for (final l in loans)
      if (l.personId == personId || l.beneficiaryPersonId == personId) l.scheduleId,
  };
  final installments = <Installment>[
    for (final s in schedules) ...(ref.watch(installmentsStreamProvider(s)).value ?? const <Installment>[]),
  ];
  final entries = ledgerAsync.value!;
  return PersonStatementSources(
    personId: personId,
    openingBalance: person.openingBalance,
    createdAt: person.createdAt,
    ledgerEntries: entries,
    ledger: [
      for (final e in entries)
        StatementLedgerInput(
          id: e.id,
          type: e.type.name,
          amount: e.amount,
          date: e.date,
          createdAt: e.createdAt,
          note: e.note,
          increasesBalance: e.increasesBalance,
          transactionRef: e.transactionRef,
          parentEntryId: e.parentEntryId,
          sourceKind: e.sourceKind,
          obligationRef: e.obligationRef,
          paymentId: e.paymentId,
          deleted: e.isDeleted,
        ),
    ],
    emis: [
      for (final e in emis)
        StatementEmiSource(
          id: e.id,
          name: e.name,
          scheduleId: e.scheduleId,
          beneficiaryPersonId: e.beneficiaryPersonId,
          beneficiaryRepaysInstallments: e.beneficiaryRepaysInstallments,
          isClosed: e.isClosed,
          deleted: e.isDeleted,
        ),
    ],
    loans: [
      for (final l in loans)
        StatementLoanSource(
          id: l.id,
          scheduleId: l.scheduleId,
          taken: l.direction == LoanDirection.taken,
          name: l.name,
          institutionName: l.institutionName,
          personId: l.personId,
          beneficiaryPersonId: l.beneficiaryPersonId,
          beneficiaryRepaysInstallments: l.beneficiaryRepaysInstallments,
          isClosed: l.isClosed,
          deleted: l.isDeleted,
        ),
    ],
    loanIds: {for (final l in [...loans, ...trashedLoans]) l.id},
    installments: [
      for (final i in installments)
        StatementInstallment(
          id: i.id,
          scheduleId: i.scheduleId,
          sequenceNumber: i.sequenceNumber,
          dueDate: i.dueDate,
          amountDue: i.amountDue,
          amountPaid: i.amountPaid,
          createdAt: i.createdAt,
          isSkipped: i.isSkipped,
          deleted: i.isDeleted,
        ),
    ],
    applications: appsAsync.value!,
  );
});

/// An obligation the Record Payment sheet can settle, with the route that owns it.
class PayableObligation {
  const PayableObligation(this.obligation, this.route, this.typeLabel);
  final PaymentObligation obligation;
  final PaymentRoute route;
  final String typeLabel;
}

/// Every open, individually settleable obligation — both sides, oldest first.
/// Same rule as the web app's `payableObligations` (via `LedgerRow.settle`):
/// manual gave/borrowed entries, split/assigned shares that still have a
/// tracking installment, and opted-in EMI installments. Loan-counterparty
/// installments are paid on the Loan, never here.
final payableObligationsProvider = Provider.autoDispose.family<List<PayableObligation>, String>((ref, personId) {
  final sources = ref.watch(personStatementSourcesProvider(personId));
  if (sources == null) return const [];
  return buildPayableObligations(sources, ref.watch(personSplitParticipantsProvider(personId)));
});

/// [reopen]: when editing a payment, what that payment put on each obligation —
/// added back first, since the edit reverts it in the same write.
List<PayableObligation> buildPayableObligations(
  PersonStatementSources sources,
  List<PendingSplitParticipant> pending, {
  Map<String, double> reopen = const {},
}) {
  final entryById = {for (final e in sources.ledgerEntries) e.id: e};
  final result = <PayableObligation>[];
  for (final r in sources.allTime().rows) {
    final remaining = r.remainingNow == null ? null : round2(r.remainingNow! + (reopen[r.key] ?? 0));
    if (!r.isObligation || remaining == null || remaining <= paymentEpsilon) continue;
    PaymentRoute? route;
    var outstanding = remaining;
    if (r.category == StatementCategory.emi) {
      route = DerivedRoute(r.key, r.key.startsWith('loan-inst:') ? 'loanInstallment' : 'emiInstallment');
    } else if (r.key.startsWith('ledger:')) {
      final e = entryById[r.key.substring(7)];
      if (e == null) continue;
      final isShare = r.category == StatementCategory.split || e.sourceKind == 'assignedExpense';
      if ((e.type == LedgerEntryType.gave || e.type == LedgerEntryType.borrowed) && !isShare && e.transactionRef == null) {
        route = EntryRoute(e.id);
      } else if (isShare) {
        final match = pending.where((p) => p.expense.transactionId == e.transactionRef).firstOrNull;
        if (match == null) continue;
        final left = round2(match.installment.remainingAmount + (reopen[r.key] ?? 0));
        if (left <= paymentEpsilon) continue;
        outstanding = remaining < left ? remaining : left;
        route = SplitRoute(
          parentEntryId: e.id,
          sourceKind: e.sourceKind == 'assignedExpense' ? 'assignedExpense' : 'splitExpense',
          expenseId: match.expense.id,
          participantKey: match.participant.personId ?? 'name:${match.participant.name}',
          scheduleId: match.installment.scheduleId,
          installmentId: match.installment.id,
        );
      }
    }
    if (route == null) continue;
    result.add(PayableObligation(
      PaymentObligation(
        key: r.key,
        title: r.title,
        date: r.date,
        createdAt: r.createdAt,
        amount: r.amount,
        outstanding: outstanding,
        side: r.signedAmount < 0 ? ObligationSide.iOwe : ObligationSide.theyOwe,
      ),
      route,
      r.typeLabel,
    ));
  }
  result.sort((a, b) => compareOldestFirst(a.obligation, b.obligation));
  return result;
}

final personPaymentRepositoryProvider = FutureProvider.autoDispose.family<PersonPaymentRepository, String>((ref, personId) async {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final user = firestore.collection(FirestoreCollections.users).doc(uid);
  final category = await ref.watch(categoryRepositoryProvider).getOrCreatePersonalLoanCategory();
  final people = user.collection(FirestoreCollections.people);
  return PersonPaymentRepository(
    firestore: firestore,
    people: ref.watch(personRepositoryProvider).collection,
    ledger: people.doc(personId).collection(FirestoreCollections.ledger).withConverter<LedgerEntry>(
          fromFirestore: LedgerEntry.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        ),
    transactions: user.collection(FirestoreCollections.transactions).withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        ),
    accounts: user.collection(FirestoreCollections.accounts).withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        ),
    expenses: user.collection(FirestoreCollections.expenses).withConverter<Expense>(
          fromFirestore: Expense.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        ),
    applications: people.doc(personId).collection(FirestoreCollections.advanceApplications).withConverter<AdvanceApplication>(
          fromFirestore: AdvanceApplication.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        ),
    installmentRef: (s, i) => user
        .collection(FirestoreCollections.paymentSchedules)
        .doc(s)
        .collection(FirestoreCollections.installments)
        .withConverter<Installment>(fromFirestore: Installment.fromFirestore, toFirestore: (x, _) => x.toFirestore())
        .doc(i),
    installmentPaymentRef: (s, i, p) => user
        .collection(FirestoreCollections.paymentSchedules)
        .doc(s)
        .collection(FirestoreCollections.installments)
        .doc(i)
        .collection(FirestoreCollections.payments)
        .withConverter<InstallmentPayment>(fromFirestore: InstallmentPayment.fromFirestore, toFirestore: (x, _) => x.toFirestore())
        .doc(p),
    cashLegCategoryId: category.id,
  );
});
