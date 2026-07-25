import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/payment_schedule/domain/cycle_anchor.dart';
import '../../../../core/payment_schedule/domain/cycle_engine.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_cycle_item.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/loan_repository.dart';
import '../../domain/loan.dart';
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

/// Sum of remaining amounts across every loan — the dashboard's "Amount to
/// receive" stat.
final totalAmountToReceiveProvider = Provider<double>((ref) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.fold(0.0, (sum, l) => sum + ref.watch(loanRemainingAmountProvider(l)));
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
