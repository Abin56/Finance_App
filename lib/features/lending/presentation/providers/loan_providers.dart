import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/payment_schedule/domain/cycle_anchor.dart';
import '../../../../core/payment_schedule/domain/cycle_engine.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_cycle_item.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/loan_repository.dart';
import '../../domain/loan.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_status.dart';

final loanRepositoryProvider = Provider<LoanRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.loans)
      .withConverter<Loan>(
        fromFirestore: Loan.fromFirestore,
        toFirestore: (loan, _) => loan.toFirestore(),
      );
  return LoanRepository(
    collection,
    ref.watch(paymentScheduleRepositoryProvider),
    (scheduleId) => ref.watch(installmentRepositoryProvider(scheduleId)),
  );
});

final loansStreamProvider = StreamProvider<List<Loan>>((ref) {
  return ref.watch(loanRepositoryProvider).watchAll();
});

final loansTrashStreamProvider = StreamProvider<List<Loan>>((ref) {
  return ref.watch(loanRepositoryProvider).watchTrash();
});

/// Every loan for one person, for the person statement timeline — filtered
/// client-side over [loansStreamProvider], same approach `creditorsProvider`/
/// `debtorsProvider` use over `peopleStreamProvider`.
final loansForPersonProvider = Provider.autoDispose.family<List<Loan>, String>((ref, personId) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.where((l) => l.personId == personId).toList();
});

/// Every loan this person actually pays on the account owner's behalf —
/// distinct from [loansForPersonProvider] (that person as the lender/
/// counterparty via [Loan.personId]). Covers "I took a bank loan, but a
/// friend pays the EMIs" — see [Loan.payerPersonId].
final loansPayableByPersonProvider = Provider.autoDispose.family<List<Loan>, String>((ref, personId) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.where((l) => l.payerPersonId == personId).toList();
});

/// The next installment still owed on a loan — the earliest (by
/// sequenceNumber) installment that isn't fully paid or skipped, or `null`
/// once every installment is settled. Powers the "Upcoming EMI" reminder on
/// a linked person's page (see `PersonLoansSummaryCard`) — every loan's
/// installments already exist for its full term (`generateInstallments`
/// materializes them upfront at creation), so this is a pure read, not a
/// projection/generation of new data.
final loanNextUpcomingInstallmentProvider = Provider.autoDispose.family<Installment?, Loan>((ref, loan) {
  final installments = [...ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const []]
    ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  return installments
      .where((i) => i.status != InstallmentStatus.paid && !i.isSkipped)
      .firstOrNull;
});

/// A loan's current status, derived from its linked schedule's installments.
final loanStatusProvider = Provider.autoDispose.family<LoanStatus, Loan>((ref, loan) {
  final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
  return loan.statusGiven(installments);
});

/// Sum of remaining amounts across a loan's installments.
final loanRemainingAmountProvider = Provider.autoDispose.family<double, Loan>((ref, loan) {
  return ref.watch(remainingAmountProvider(loan.scheduleId));
});

/// Sum of amounts actually paid so far across a loan's installments.
final loanTotalReceivedProvider = Provider.autoDispose.family<double, Loan>((ref, loan) {
  final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
  return installments.fold(0.0, (sum, i) => sum + i.amountPaid);
});

/// Every non-closed loan.
final activeLoansProvider = Provider<List<Loan>>((ref) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.where((l) => ref.watch(loanStatusProvider(l)) != LoanStatus.closed).toList();
});

/// Sum of remaining amounts across every non-closed [LoanDirection.given]
/// loan — the dashboard's "To Receive" stat. Excludes closed loans since a
/// loan can be closed early as forgiven/written-off while still carrying
/// unpaid installments (see `Loan.isClosed`) — that remainder is no longer
/// actually expected, so it must not inflate the total (mirrors
/// [activeLoansProvider]'s own closed-status exclusion).
final totalAmountToReceiveProvider = Provider<double>((ref) {
  final loans = ref.watch(activeLoansProvider);
  return loans
      .where((l) => l.direction == LoanDirection.given)
      .fold(0.0, (sum, l) => sum + ref.watch(loanRemainingAmountProvider(l)));
});

/// Sum of remaining amounts across every non-closed [LoanDirection.taken]
/// loan — the dashboard's "To Pay" stat. See [totalAmountToReceiveProvider]
/// for why closed loans are excluded.
final totalAmountToPayProvider = Provider<double>((ref) {
  final loans = ref.watch(activeLoansProvider);
  return loans
      .where((l) => l.direction == LoanDirection.taken)
      .fold(0.0, (sum, l) => sum + ref.watch(loanRemainingAmountProvider(l)));
});

/// The cycle anchor Loan installments classify against — day 17, the same
/// default reused for EMI's `emiCycleAnchor` and People's `personCycleAnchor`.
/// Loans have no per-schedule anchor-day concept of their own today, so
/// every loan shares this one constant for now.
const loanCycleAnchor = CycleAnchor(anchorDay: 17);

/// One loan's installments split into Previous-Cycle-Pending / Current /
/// Future via the shared `CycleEngine`, the same carry-forward rule Credit
/// Cards/People/EMI already use. Raw `CycleItem`-typed result — see
/// [loanCycleViewRecordProvider] below for the unwrapped `Installment` view
/// every screen should actually watch.
final loanCycleViewProvider = Provider.autoDispose.family<CycleEngineResult<InstallmentCycleItem>, Loan>((ref, loan) {
  final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
  final items = installments.map(InstallmentCycleItem.new).toList();
  return CycleEngine.classifyForCarryForward(items, loanCycleAnchor);
});

/// The two-section carry-forward view for one loan's installments, unwrapped
/// back to plain [Installment]s — mirrors `EmiCycleView`/
/// [emiCycleViewRecordProvider] exactly. Every loan installment is
/// materialized upfront by `generateInstallments`, so [current] is simply
/// [loanCycleViewProvider]'s own `result.current`, unwrapped — no separate
/// "live" fetch needed.
typedef LoanCycleView = ({List<Installment> previousCyclePending, List<Installment> current});

final loanCycleViewRecordProvider = Provider.autoDispose.family<LoanCycleView, Loan>((ref, loan) {
  final result = ref.watch(loanCycleViewProvider(loan));
  return (
    previousCyclePending: result.previousCyclePending.map((item) => item.installment).toList(),
    current: result.current.map((item) => item.installment).toList(),
  );
});
