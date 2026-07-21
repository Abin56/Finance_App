import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
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
