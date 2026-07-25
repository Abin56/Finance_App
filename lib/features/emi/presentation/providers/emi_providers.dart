import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/cycle_anchor.dart';
import '../../../../core/payment_schedule/domain/cycle_engine.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_cycle_item.dart';
import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../data/emi_payment_breakdown_repository.dart';
import '../../data/emi_repository.dart';
import '../../domain/emi.dart';
import '../../domain/emi_payment_breakdown.dart';
import '../../domain/emi_payment_history_entry.dart';
import '../../domain/emi_status.dart';

final emiRepositoryProvider = Provider<EmiRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.emis)
      .withConverter<Emi>(
        fromFirestore: Emi.fromFirestore,
        toFirestore: (emi, _) => emi.toFirestore(),
      );
  return EmiRepository(
    collection,
    ref.watch(paymentScheduleRepositoryProvider),
    (scheduleId) => ref.watch(installmentRepositoryProvider(scheduleId)),
  );
});

final emisStreamProvider = StreamProvider<List<Emi>>((ref) {
  return ref.watch(emiRepositoryProvider).watchAll();
});

final emisTrashStreamProvider = StreamProvider<List<Emi>>((ref) {
  return ref.watch(emiRepositoryProvider).watchTrash();
});

/// Breakdown repository for one EMI's `paymentBreakdowns` subcollection —
/// scoped by EMI id, mirrors `installmentPaymentRepositoryProvider`'s
/// per-schedule scoping shape.
final emiPaymentBreakdownRepositoryProvider =
    Provider.autoDispose.family<EmiPaymentBreakdownRepository, String>((ref, emiId) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.emis)
      .doc(emiId)
      .collection(FirestoreCollections.paymentBreakdowns)
      .withConverter<EmiPaymentBreakdown>(
        fromFirestore: EmiPaymentBreakdown.fromFirestore,
        toFirestore: (breakdown, _) => breakdown.toFirestore(),
      );
  return EmiPaymentBreakdownRepository(collection);
});

final emiPaymentBreakdownsStreamProvider =
    StreamProvider.autoDispose.family<List<EmiPaymentBreakdown>, String>((ref, emiId) {
  return ref.watch(emiPaymentBreakdownRepositoryProvider(emiId)).watchAll();
});

/// An EMI's current status, derived from its linked schedule's installments.
final emiStatusProvider = Provider.autoDispose.family<EmiStatus, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  return emi.statusGiven(installments);
});

/// Sum of remaining amounts across an EMI's installments.
final emiRemainingAmountProvider = Provider.autoDispose.family<double, Emi>((ref, emi) {
  return ref.watch(remainingAmountProvider(emi.scheduleId));
});

/// Sum of amounts paid so far across an EMI's installments — "paid", not
/// "received", since an EMI is a liability rather than a receivable.
final emiTotalPaidProvider = Provider.autoDispose.family<double, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  return installments.fold(0.0, (sum, i) => sum + i.amountPaid);
});

/// Count of installments already fully paid — the "N" in "N / tenure EMIs
/// Paid" on the EMI Details hero card.
final emiInstallmentsPaidProvider = Provider.autoDispose.family<int, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  return installments.where((i) => i.status == InstallmentStatus.paid).length;
});

/// Count of installments still owed (not fully paid, not skipped) — distinct
/// from `installmentCount - emiInstallmentsPaidProvider` so a skipped
/// installment doesn't count as "remaining tenure" still to be paid.
final emiRemainingTenureProvider = Provider.autoDispose.family<int, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  return installments.where((i) => i.remainingAmount > 0 && !i.isSkipped).length;
});

/// Remaining principal across all installments, assuming each installment's
/// own payments settle its interest portion before its principal portion
/// (the standard repayment convention) — display-only, mirrors
/// `LoanDetailScreen`'s equivalent computation. Promoted from
/// `EmiDetailScreen`'s former private method so any screen/widget can read
/// the same figure.
final emiPrincipalOutstandingProvider = Provider.autoDispose.family<double, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  return installments.fold(0.0, (sum, i) {
    final interestPortion = i.interestPortion ?? 0;
    final principalPortion = i.principalPortion ?? i.amountDue;
    final paidTowardPrincipal = (i.amountPaid - interestPortion).clamp(0, principalPortion);
    return sum + (principalPortion - paidTowardPrincipal);
  });
});

/// Remaining interest across all installments — see
/// [emiPrincipalOutstandingProvider] for the settlement convention assumed.
final emiInterestOutstandingProvider = Provider.autoDispose.family<double, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  return installments.fold(0.0, (sum, i) {
    final interestPortion = i.interestPortion ?? 0;
    final paidTowardInterest = i.amountPaid.clamp(0, interestPortion);
    return sum + (interestPortion - paidTowardInterest);
  });
});

/// Total interest payable across the *entire* schedule (paid + outstanding)
/// — distinct from Reports' `interestPaidProvider`, which only sums
/// interest paid so far.
final emiTotalInterestPayableProvider = Provider.autoDispose.family<double, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  return installments.fold(0.0, (sum, i) => sum + (i.interestPortion ?? 0));
});

/// Fraction (0..1) of this EMI's total schedule paid off so far — promoted
/// from `EmiDetailScreen`'s former inline `completion` calculation so a
/// dashboard widget can reuse the exact same figure as the detail screen's
/// progress ring/bar.
final emiLoanProgressProvider = Provider.autoDispose.family<double, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  final totalDue = installments.fold(0.0, (sum, i) => sum + i.amountDue);
  if (totalDue == 0) return 0;
  final paid = ref.watch(emiTotalPaidProvider(emi));
  return paid / totalDue;
});

/// Every non-closed EMI.
final activeEmisProvider = Provider<List<Emi>>((ref) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.where((e) => ref.watch(emiStatusProvider(e)) != EmiStatus.closed).toList();
});

/// Every EMI with at least one overdue installment, not closed.
final overdueEmisProvider = Provider<List<Emi>>((ref) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.where((e) => ref.watch(emiStatusProvider(e)) == EmiStatus.overdue).toList();
});

/// Active EMIs whose this-month installment isn't already paid or skipped —
/// the dashboard's "Due this month" stat.
final dueThisMonthEmisProvider = Provider<List<Emi>>((ref) {
  final emis = ref.watch(activeEmisProvider);
  return emis.where((emi) {
    final thisMonth = ref.watch(thisMonthInstallmentsProvider(emi.scheduleId));
    return thisMonth.any((i) => i.remainingAmount > 0);
  }).toList();
});

/// Sum of remaining amounts across each active EMI's this-month installment.
final dueThisMonthAmountProvider = Provider<double>((ref) {
  final emis = ref.watch(dueThisMonthEmisProvider);
  return emis.fold(0.0, (sum, emi) {
    final thisMonth = ref.watch(thisMonthInstallmentsProvider(emi.scheduleId));
    return sum + thisMonth.fold(0.0, (s, i) => s + i.remainingAmount);
  });
});

/// Sum of remaining amounts across every non-closed EMI — the dashboard's
/// "Remaining loan balance" stat.
final totalRemainingEmiBalanceProvider = Provider<double>((ref) {
  final emis = ref.watch(activeEmisProvider);
  return emis.fold(0.0, (sum, emi) => sum + ref.watch(emiRemainingAmountProvider(emi)));
});

/// Active categories, offered to the EMI form regardless of `CategoryType`
/// (income/expense-scoped filtering doesn't apply to EMI).
final activeCategoriesProvider = Provider<List<Category>>((ref) {
  final categories = ref.watch(categoriesStreamProvider).value ?? const [];
  return categories.where((c) => c.isActive).toList();
});

/// One EMI's full payment timeline — every [InstallmentPayment] across every
/// installment of its schedule, folded in chronological order so each
/// entry's [EmiPaymentHistoryEntry.remainingBalanceAfter] reflects the whole
/// EMI's remaining balance immediately after that payment, not just the one
/// installment it landed on. A skipped installment with no payment still
/// gets an entry (dated at its due date) so the timeline reads as a
/// complete story of the EMI, matching the "skip an installment" feature.
final emiPaymentHistoryProvider = Provider.autoDispose.family<List<EmiPaymentHistoryEntry>, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  final sortedInstallments = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

  final breakdowns = ref.watch(emiPaymentBreakdownsStreamProvider(emi.id)).value ?? const [];
  final breakdownByPaymentId = {for (final b in breakdowns) b.paymentId: b};

  final totalDue = installments.fold(0.0, (sum, i) => sum + i.amountDue);

  final rawEntries = <({DateTime date, Installment installment, InstallmentPayment? payment})>[];
  for (final installment in sortedInstallments) {
    if (installment.isSkipped) {
      rawEntries.add((date: installment.dueDate, installment: installment, payment: null));
      continue;
    }
    final payments = ref.watch(
      installmentPaymentsStreamProvider((scheduleId: emi.scheduleId, installmentId: installment.id)),
    ).value ?? const [];
    for (final payment in payments) {
      rawEntries.add((date: payment.date, installment: installment, payment: payment));
    }
  }
  rawEntries.sort((a, b) => a.date.compareTo(b.date));

  var paidSoFar = 0.0;
  final entries = <EmiPaymentHistoryEntry>[];
  for (final raw in rawEntries) {
    final installment = raw.installment;
    final payment = raw.payment;
    if (payment == null) {
      entries.add(EmiPaymentHistoryEntry(
        date: raw.date,
        amount: 0,
        note: '',
        status: EmiPaymentHistoryStatus.skipped,
        remainingBalanceAfter: (totalDue - paidSoFar).clamp(0, totalDue),
        installmentSequenceNumber: installment.sequenceNumber,
      ));
      continue;
    }
    paidSoFar += payment.amount;
    entries.add(EmiPaymentHistoryEntry(
      date: payment.date,
      amount: payment.amount,
      note: payment.note,
      status: EmiPaymentHistoryEntry.statusFor(payment, installment),
      remainingBalanceAfter: (totalDue - paidSoFar).clamp(0, totalDue),
      installmentSequenceNumber: installment.sequenceNumber,
      payment: payment,
      breakdown: breakdownByPaymentId[payment.id],
    ));
  }
  return entries;
});

/// Sum of amountPaid across this-month installments, across every active EMI
/// — the dashboard's "Paid this month" stat.
final emiPaidThisMonthProvider = Provider<double>((ref) {
  final emis = ref.watch(activeEmisProvider);
  return emis.fold(0.0, (sum, emi) {
    final thisMonth = ref.watch(thisMonthInstallmentsProvider(emi.scheduleId));
    return sum + thisMonth.fold(0.0, (s, i) => s + i.amountPaid);
  });
});

/// Sum of remaining amounts across every overdue installment, across every
/// active EMI — the dashboard's "Overdue" amount (as opposed to
/// `overdueEmisProvider`, which counts EMIs, not the money involved).
final emiOverdueAmountProvider = Provider<double>((ref) {
  final emis = ref.watch(activeEmisProvider);
  return emis.fold(0.0, (sum, emi) {
    final overdue = ref.watch(overdueInstallmentsProvider(emi.scheduleId));
    return sum + overdue.fold(0.0, (s, i) => s + i.remainingAmount);
  });
});

/// The single next unpaid, non-skipped installment due across every active
/// EMI, paired with its owning EMI — null when nothing is outstanding.
final nextEmiDueProvider = Provider<({Emi emi, Installment installment})?>((ref) {
  final emis = ref.watch(activeEmisProvider);
  ({Emi emi, Installment installment})? next;
  for (final emi in emis) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    final unpaid = installments.where((i) => i.status != InstallmentStatus.paid && !i.isSkipped);
    for (final installment in unpaid) {
      if (next == null || installment.dueDate.isBefore(next.installment.dueDate)) {
        next = (emi: emi, installment: installment);
      }
    }
  }
  return next;
});

/// The cycle anchor EMI installments classify against. Day 17, matching the
/// People module's `personCycleAnchor` and Credit Cards' default statement
/// day — the same coincidental-but-consistent default already used
/// elsewhere in this codebase (`CreditCardProfile.statementDay`'s implicit
/// default, the Dashboard's salary-cycle strategies). EMI has no
/// per-schedule anchor-day concept of its own today, so every EMI shares
/// this one constant for now, same posture as People's.
const emiCycleAnchor = CycleAnchor(anchorDay: 17);

/// One EMI's installments split into Previous-Cycle-Pending / Current /
/// Future via the shared `CycleEngine`, the same carry-forward rule Credit
/// Cards (`statementCycleViewProvider`) and People
/// (`personCycleViewProvider`) already ship. Raw `CycleItem`-typed result —
/// see [emiCycleViewRecordProvider] below for the unwrapped `Installment`
/// view every screen should actually watch, mirroring how
/// `statementCycleViewProvider` composes over its own raw engine call.
final emiCycleViewProvider = Provider.autoDispose.family<CycleEngineResult<InstallmentCycleItem>, Emi>((ref, emi) {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  final items = installments.map(InstallmentCycleItem.new).toList();
  return CycleEngine.classifyForCarryForward(items, emiCycleAnchor);
});

/// The two-section carry-forward view for one EMI's installments, unwrapped
/// back to plain [Installment]s — mirrors
/// [StatementCycleView]/`statementCycleViewProvider` exactly. Unlike Credit
/// Cards (whose live current cycle isn't materialized as a `Statement` yet,
/// so `current` is fetched separately), every EMI installment is
/// materialized upfront by `generateInstallments`, so [current] here is
/// simply [emiCycleViewProvider]'s own `result.current`, unwrapped — no
/// separate "live" fetch needed. Plural (a weekly/custom schedule could
/// land more than one installment in the same current-cycle window).
typedef EmiCycleView = ({List<Installment> previousCyclePending, List<Installment> current});

final emiCycleViewRecordProvider = Provider.autoDispose.family<EmiCycleView, Emi>((ref, emi) {
  final result = ref.watch(emiCycleViewProvider(emi));
  return (
    previousCyclePending: result.previousCyclePending.map((item) => item.installment).toList(),
    current: result.current.map((item) => item.installment).toList(),
  );
});

/// Every unpaid, non-skipped installment due within the next 7 days
/// (inclusive of today), across every active EMI — the dashboard's
/// "Upcoming 7 days" stat.
final emiUpcoming7DaysProvider = Provider<List<Installment>>((ref) {
  final emis = ref.watch(activeEmisProvider);
  final today = DateTime.now().dateOnly;
  final horizon = today.add(const Duration(days: 7));
  final result = <Installment>[];
  for (final emi in emis) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    result.addAll(installments.where((i) {
      if (i.status == InstallmentStatus.paid || i.isSkipped) return false;
      final due = i.dueDate.dateOnly;
      return !due.isBefore(today) && !due.isAfter(horizon);
    }));
  }
  return result;
});
