import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/bill_repository.dart';
import '../../data/payment_repository.dart';
import '../../domain/bill.dart';
import '../../domain/bill_occurrence.dart';
import '../../domain/bill_status.dart';
import '../../domain/payment_record.dart';
import 'bill_occurrence_providers.dart';

final billRepositoryProvider = Provider<BillRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.bills)
      .withConverter<Bill>(
        fromFirestore: Bill.fromFirestore,
        toFirestore: (bill, _) => bill.toFirestore(),
      );
  return BillRepository(collection);
});

final billsStreamProvider = StreamProvider<List<Bill>>((ref) {
  return ref.watch(billRepositoryProvider).watchAll();
});

final billsTrashStreamProvider = StreamProvider<List<Bill>>((ref) {
  return ref.watch(billRepositoryProvider).watchTrash();
});

/// Payment repository for a single bill's subcollection, scoped by
/// [billId] — a fresh repository per bill, mirrors `ledgerRepositoryProvider`.
final paymentRepositoryProvider = Provider.autoDispose.family<PaymentRepository, String>((ref, billId) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.bills)
      .doc(billId)
      .collection(FirestoreCollections.payments)
      .withConverter<PaymentRecord>(
        fromFirestore: PaymentRecord.fromFirestore,
        toFirestore: (payment, _) => payment.toFirestore(),
      );
  return PaymentRepository(collection, ref.watch(billOccurrenceRepositoryProvider(billId)));
});

final paymentsStreamProvider = StreamProvider.autoDispose.family<List<PaymentRecord>, String>((ref, billId) {
  return ref.watch(paymentRepositoryProvider(billId)).watchAll();
});

final paymentsTrashStreamProvider = StreamProvider.autoDispose.family<List<PaymentRecord>, String>((ref, billId) {
  return ref.watch(paymentRepositoryProvider(billId)).watchTrash();
});

/// Every bill's current occurrence, keyed by bill id — the one place every
/// status-derived provider below reads from, so none of them re-derive
/// "find this bill's current occurrence" independently. Watches
/// [materializeBillOccurrenceProvider] for each bill too, so simply
/// watching this provider is enough to keep every bill's occurrence data
/// fresh without every screen needing to remember to trigger it itself.
final currentOccurrenceByBillIdProvider = Provider<Map<String, BillOccurrence>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final map = <String, BillOccurrence>{};
  for (final bill in bills) {
    ref.watch(materializeBillOccurrenceProvider(bill.id));
    final occurrence = ref.watch(currentBillOccurrenceProvider(bill.id));
    if (occurrence != null) map[bill.id] = occurrence;
  }
  return map;
});

/// Bills overdue as of today (by their current occurrence), oldest due
/// date first.
final overdueBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final occurrences = ref.watch(currentOccurrenceByBillIdProvider);
  final overdue = bills.where((b) => occurrences[b.id]?.status == BillStatus.overdue).toList()
    ..sort((a, b) => occurrences[a.id]!.dueDate.compareTo(occurrences[b.id]!.dueDate));
  return overdue;
});

/// Bills due today (by their current occurrence).
final dueTodayBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final occurrences = ref.watch(currentOccurrenceByBillIdProvider);
  return bills.where((b) => occurrences[b.id]?.status == BillStatus.dueToday).toList();
});

/// Bills due after today (upcoming, partially paid but not yet due, or
/// skipped are excluded — this is strictly the "still ahead" list),
/// nearest due date first.
final upcomingBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final occurrences = ref.watch(currentOccurrenceByBillIdProvider);
  final upcoming = bills.where((b) => occurrences[b.id]?.status == BillStatus.upcoming).toList()
    ..sort((a, b) => occurrences[a.id]!.dueDate.compareTo(occurrences[b.id]!.dueDate));
  return upcoming;
});

final paidBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final occurrences = ref.watch(currentOccurrenceByBillIdProvider);
  return bills.where((b) => occurrences[b.id]?.status == BillStatus.paid).toList();
});

/// Sum of remaining amounts for bills due within the next 7 days
/// (inclusive of today), for the dashboard's "Due this week" stat.
final totalDueThisWeekProvider = Provider<double>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final occurrences = ref.watch(currentOccurrenceByBillIdProvider);
  final today = DateTime.now().dateOnly;
  final weekEnd = today.add(const Duration(days: 6));
  var total = 0.0;
  for (final bill in bills) {
    final occurrence = occurrences[bill.id];
    if (occurrence == null) continue;
    if (occurrence.status == BillStatus.paid || occurrence.status == BillStatus.skipped) continue;
    if (occurrence.dueDate.dateOnly.isBefore(today) || occurrence.dueDate.dateOnly.isAfter(weekEnd)) continue;
    total += occurrence.remainingAmount;
  }
  return total;
});

/// Sum of remaining amounts for every overdue bill, for the dashboard's
/// "Total due" stat alongside [overdueCountProvider].
final totalOverdueAmountProvider = Provider<double>((ref) {
  final occurrences = ref.watch(currentOccurrenceByBillIdProvider);
  return ref
      .watch(overdueBillsProvider)
      .fold(0.0, (total, bill) => total + occurrences[bill.id]!.remainingAmount);
});

final overdueCountProvider = Provider<int>((ref) {
  return ref.watch(overdueBillsProvider).length;
});
