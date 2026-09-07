import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/payment_schedule/domain/cycle_anchor.dart';
import '../../../../core/payment_schedule/domain/cycle_engine.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_cycle_item.dart';
import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../data/loan_repository.dart';
import '../../domain/loan.dart';
import '../../domain/loan_dashboard_metrics.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_financial_summary.dart';
import '../../domain/loan_payment_history_entry.dart';
import '../../domain/loan_status.dart';
import '../../domain/loan_timeline_entry.dart';
import '../../domain/person_loan_ledger_summary.dart';

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
final loansForPersonProvider = Provider.autoDispose.family<List<Loan>, String>((
  ref,
  personId,
) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.where((l) => l.personId == personId).toList();
});

/// Every loan this person actually pays on the account owner's behalf —
/// distinct from [loansForPersonProvider] (that person as the lender/
/// counterparty via [Loan.personId]). Covers "I took a bank loan, but a
/// friend pays the EMIs" — see [Loan.payerPersonId].
final loansPayableByPersonProvider = Provider.autoDispose
    .family<List<Loan>, String>((ref, personId) {
      final loans = ref.watch(loansStreamProvider).value ?? const [];
      return loans.where((l) => l.payerPersonId == personId).toList();
    });

/// This person's combined "who owes whom" picture — see
/// [PersonLoanLedgerSummary]'s own doc comment for why adding the ledger
/// balance to loan outstanding totals is always safe (independent sources,
/// never the same event counted twice). Folds exactly the same loans
/// [PersonLoansSummaryCard] already reads ([loansForPersonProvider] +
/// [loansPayableByPersonProvider], deduped by id) through
/// [loanRemainingAmountProvider] — no new loan-balance calculation, and the
/// ledger side is read straight off `Person.currentBalance`, never
/// recomputed from raw [LedgerEntry]s here.
final personLoanLedgerSummaryProvider = Provider.autoDispose.family<PersonLoanLedgerSummary, String>((ref, personId) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  final person = people.where((p) => p.id == personId).firstOrNull;
  final ledgerBalance = person?.currentBalance ?? 0;

  final asLender = ref.watch(loansForPersonProvider(personId));
  final asPayer = ref.watch(loansPayableByPersonProvider(personId));
  final loans = <String, Loan>{
    for (final loan in asLender) loan.id: loan,
    for (final loan in asPayer) loan.id: loan,
  }.values;

  var loanGivenTotal = 0.0;
  var loanGivenOutstanding = 0.0;
  var loanTakenTotal = 0.0;
  var loanTakenOutstanding = 0.0;
  for (final loan in loans) {
    if (ref.watch(loanStatusProvider(loan)) == LoanStatus.closed) continue;
    final remaining = ref.watch(loanRemainingAmountProvider(loan));
    if (loan.direction == LoanDirection.given) {
      loanGivenTotal += loan.loanAmount;
      loanGivenOutstanding += remaining;
    } else {
      loanTakenTotal += loan.loanAmount;
      loanTakenOutstanding += remaining;
    }
  }

  return PersonLoanLedgerSummary(
    ledgerBalance: ledgerBalance,
    loanGivenTotal: loanGivenTotal,
    loanGivenOutstanding: loanGivenOutstanding,
    loanTakenTotal: loanTakenTotal,
    loanTakenOutstanding: loanTakenOutstanding,
  );
});

/// The single reusable financial summary for one loan — see
/// [LoanFinancialSummary]. Every screen that needs principal/interest/paid/
/// outstanding/progress/next-installment/overdue numbers should watch this
/// (or one of the thin wrappers below) instead of recomputing them from
/// installments locally.
final loanFinancialSummaryProvider = Provider.autoDispose.family<LoanFinancialSummary, Loan>((ref, loan) {
  final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
  return LoanFinancialSummary.from(installments: installments, originalPrincipal: loan.loanAmount);
});

/// The next installment still owed on a loan — the earliest (by
/// sequenceNumber) installment that isn't fully paid or skipped, or `null`
/// once every installment is settled. Powers the "Upcoming EMI" reminder on
/// a linked person's page (see `PersonLoansSummaryCard`). Thin wrapper over
/// [loanFinancialSummaryProvider] — do not recompute this independently.
final loanNextUpcomingInstallmentProvider = Provider.autoDispose
    .family<Installment?, Loan>((ref, loan) {
      return ref.watch(loanFinancialSummaryProvider(loan)).nextInstallment;
    });

/// A loan's current status, derived from its linked schedule's installments.
final loanStatusProvider = Provider.autoDispose.family<LoanStatus, Loan>((
  ref,
  loan,
) {
  final installments =
      ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
  return loan.statusGiven(installments);
});

/// Sum of remaining amounts across a loan's installments. Thin wrapper over
/// [loanFinancialSummaryProvider] — do not recompute this independently.
final loanRemainingAmountProvider = Provider.autoDispose.family<double, Loan>((
  ref,
  loan,
) {
  return ref.watch(loanFinancialSummaryProvider(loan)).outstanding;
});

/// Sum of amounts actually paid so far across a loan's installments. Thin
/// wrapper over [loanFinancialSummaryProvider] — do not recompute this
/// independently.
final loanTotalReceivedProvider = Provider.autoDispose.family<double, Loan>((
  ref,
  loan,
) {
  return ref.watch(loanFinancialSummaryProvider(loan)).totalPaid;
});

/// Every non-closed loan.
final activeLoansProvider = Provider<List<Loan>>((ref) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans
      .where((l) => ref.watch(loanStatusProvider(l)) != LoanStatus.closed)
      .toList();
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
final loanCycleViewProvider = Provider.autoDispose
    .family<CycleEngineResult<InstallmentCycleItem>, Loan>((ref, loan) {
      final installments =
          ref.watch(installmentsStreamProvider(loan.scheduleId)).value ??
          const [];
      final items = installments.map(InstallmentCycleItem.new).toList();
      return CycleEngine.classifyForCarryForward(items, loanCycleAnchor);
    });

/// The two-section carry-forward view for one loan's installments, unwrapped
/// back to plain [Installment]s — mirrors `EmiCycleView`/
/// [emiCycleViewRecordProvider] exactly. Every loan installment is
/// materialized upfront by `generateInstallments`, so [current] is simply
/// [loanCycleViewProvider]'s own `result.current`, unwrapped — no separate
/// "live" fetch needed.
typedef LoanCycleView = ({
  List<Installment> previousCyclePending,
  List<Installment> current,
});

final loanCycleViewRecordProvider = Provider.autoDispose
    .family<LoanCycleView, Loan>((ref, loan) {
      final result = ref.watch(loanCycleViewProvider(loan));
      return (
        previousCyclePending: result.previousCyclePending
            .map((item) => item.installment)
            .toList(),
        current: result.current.map((item) => item.installment).toList(),
      );
    });

/// One loan's full payment timeline — every [InstallmentPayment] across
/// every installment of its schedule, folded in chronological order so each
/// entry's [LoanPaymentHistoryEntry.remainingBalanceAfter] reflects the
/// whole loan's remaining balance immediately after that payment. Mirrors
/// `emiPaymentHistoryProvider`'s fan-out exactly, but loan-scoped and using
/// the real [InstallmentPayment.payerPersonId] rather than note-parsing.
final loanPaymentHistoryProvider = Provider.autoDispose
    .family<List<LoanPaymentHistoryEntry>, Loan>((ref, loan) {
      final installments =
          ref.watch(installmentsStreamProvider(loan.scheduleId)).value ??
          const [];
      final sortedInstallments = [...installments]
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      final totalDue = installments.fold(0.0, (sum, i) => sum + i.amountDue);

      final rawEntries =
          <({DateTime date, Installment installment, InstallmentPayment payment})>[];
      for (final installment in sortedInstallments) {
        final payments =
            ref
                .watch(
                  installmentPaymentsStreamProvider((
                    scheduleId: loan.scheduleId,
                    installmentId: installment.id,
                  )),
                )
                .value ??
            const [];
        for (final payment in payments) {
          rawEntries.add((
            date: payment.date,
            installment: installment,
            payment: payment,
          ));
        }
      }
      rawEntries.sort((a, b) => a.date.compareTo(b.date));

      var paidSoFar = 0.0;
      final entries = <LoanPaymentHistoryEntry>[];
      for (final raw in rawEntries) {
        paidSoFar += raw.payment.amount;
        entries.add(
          LoanPaymentHistoryEntry(
            payment: raw.payment,
            installmentSequenceNumber: raw.installment.sequenceNumber,
            status: LoanPaymentHistoryEntry.statusFor(
              raw.payment,
              raw.installment,
            ),
            remainingBalanceAfter: (totalDue - paidSoFar).clamp(0, totalDue),
          ),
        );
      }
      return entries.reversed.toList();
    });

/// Every active loan paired with its [LoanFinancialSummary] — the shared
/// input the Loan Dashboard's aggregate stats and the per-loan installment
/// lookups below both fold over, so every dashboard number traces back to
/// [loanFinancialSummaryProvider], never a separate calculation.
final activeLoansWithSummaryProvider = Provider<List<LoanWithSummary>>((ref) {
  final loans = ref.watch(activeLoansProvider);
  return [
    for (final loan in loans)
      (loan: loan, summary: ref.watch(loanFinancialSummaryProvider(loan))),
  ];
});

/// The Loan Dashboard's aggregate totals (Borrowed/Lent/Outstanding/Paid/
/// Interest Remaining, overdue, upcoming-7/30-day) — see
/// [LoanDashboardMetrics]'s own doc comment for why this is loan-balance-only
/// and deliberately never scoped by a transaction-style date range: a loan's
/// original principal and outstanding balance are lifetime figures, not
/// activity within a period, so filtering them by "This Month"/"Last Month"
/// the way Cash Flow filters transactions would silently misrepresent a
/// loan's true balance. Only the "Monthly Repayment" schedule breakdown
/// (see [loanMonthlyRepaymentsProvider]) is inherently period-shaped, since
/// it's already grouped by due-month.
final loanDashboardMetricsProvider = Provider<LoanDashboardMetrics>((ref) {
  final loansWithSummary = ref.watch(activeLoansWithSummaryProvider);
  return LoanDashboardMetrics.from(
    loansWithSummary,
    installmentsFor: (loan) =>
        ref.watch(installmentsStreamProvider(loan.scheduleId)).value ??
        const [],
  );
});

/// Scheduled repayment totals for the next [monthsAhead] calendar months
/// (default 3) across every active loan's installments — a direct readout of
/// `Installment.amountDue` grouped by due-month, per
/// [LoanDashboardMetrics.monthlyRepayments]. Never recomputes an EMI amount.
final loanMonthlyRepaymentsProvider = Provider.autoDispose
    .family<List<MonthlyRepaymentBucket>, int>((ref, monthsAhead) {
      final loans = ref.watch(activeLoansProvider);
      final installments = <Installment>[
        for (final loan in loans)
          ...?ref.watch(installmentsStreamProvider(loan.scheduleId)).value,
      ];
      return LoanDashboardMetrics.monthlyRepayments(
        installments,
        monthsAhead: monthsAhead,
      );
    });

/// One loan's honest event timeline — see [LoanTimelineEntry.build] for
/// exactly which event types are (and are deliberately not) derived. Watches
/// every installment's live and soft-deleted payments in addition to
/// [Loan.editHistory], which is already loaded on the [Loan] itself.
final loanTimelineProvider = Provider.autoDispose
    .family<List<LoanTimelineEntry>, Loan>((ref, loan) {
      final installments =
          ref.watch(installmentsStreamProvider(loan.scheduleId)).value ??
          const [];

      final payments = <InstallmentPayment>[];
      final deletedPayments = <InstallmentPayment>[];
      for (final installment in installments) {
        final key = (
          scheduleId: loan.scheduleId,
          installmentId: installment.id,
        );
        payments.addAll(
          ref.watch(installmentPaymentsStreamProvider(key)).value ?? const [],
        );
        deletedPayments.addAll(
          ref.watch(installmentPaymentsTrashStreamProvider(key)).value ??
              const [],
        );
      }

      return LoanTimelineEntry.build(
        loan: loan,
        installments: installments,
        payments: payments,
        deletedPayments: deletedPayments,
      );
    });
