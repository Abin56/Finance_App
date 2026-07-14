import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/bill_repository.dart';
import '../../data/payment_repository.dart';
import '../../domain/bill.dart';
import '../../domain/bill_status.dart';
import '../../domain/payment_record.dart';

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
final paymentRepositoryProvider = Provider.family<PaymentRepository, String>((ref, billId) {
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
  return PaymentRepository(collection, ref.watch(billRepositoryProvider));
});

final paymentsStreamProvider = StreamProvider.family<List<PaymentRecord>, String>((ref, billId) {
  return ref.watch(paymentRepositoryProvider(billId)).watchAll();
});

final paymentsTrashStreamProvider = StreamProvider.family<List<PaymentRecord>, String>((ref, billId) {
  return ref.watch(paymentRepositoryProvider(billId)).watchTrash();
});

/// Bills overdue as of today, oldest due date first.
final overdueBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final overdue = bills.where((b) => b.status == BillStatus.overdue).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return overdue;
});

/// Bills due today.
final dueTodayBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  return bills.where((b) => b.status == BillStatus.dueToday).toList();
});

/// Bills due after today (upcoming, partially paid but not yet due, or
/// skipped are excluded — this is strictly the "still ahead" list),
/// nearest due date first.
final upcomingBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final upcoming = bills.where((b) => b.status == BillStatus.upcoming).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return upcoming;
});

final paidBillsProvider = Provider<List<Bill>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  return bills.where((b) => b.status == BillStatus.paid).toList();
});

/// Sum of remaining amounts for bills due within the next 7 days
/// (inclusive of today), for the dashboard's "Due this week" stat.
final totalDueThisWeekProvider = Provider<double>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final today = DateTime.now().dateOnly;
  final weekEnd = today.add(const Duration(days: 6));
  return bills
      .where((b) => b.status != BillStatus.paid && b.status != BillStatus.skipped)
      .where((b) => !b.dueDate.dateOnly.isBefore(today) && !b.dueDate.dateOnly.isAfter(weekEnd))
      .fold(0.0, (total, b) => total + b.remainingAmount);
});

/// Sum of remaining amounts for every overdue bill, for the dashboard's
/// "Total due" stat alongside [overdueCountProvider].
final totalOverdueAmountProvider = Provider<double>((ref) {
  return ref.watch(overdueBillsProvider).fold(0.0, (total, b) => total + b.remainingAmount);
});

final overdueCountProvider = Provider<int>((ref) {
  return ref.watch(overdueBillsProvider).length;
});

/// Every non-paid, non-skipped bill due on [date] — powers the calendar's
/// tap-a-date day list.
final billsForDateProvider = Provider.family<List<Bill>, DateTime>((ref, date) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  return bills.where((b) => b.dueDate.isSameDay(date)).toList();
});
