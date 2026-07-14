import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/firestore_constants.dart';
import '../../../providers/firebase_providers.dart';
import '../../data/installment_payment_repository.dart';
import '../../data/installment_repository.dart';
import '../../data/payment_schedule_repository.dart';
import '../../domain/installment.dart';
import '../../domain/installment_payment.dart';
import '../../domain/payment_schedule.dart';

final paymentScheduleRepositoryProvider = Provider<PaymentScheduleRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.paymentSchedules)
      .withConverter<PaymentSchedule>(
        fromFirestore: PaymentSchedule.fromFirestore,
        toFirestore: (schedule, _) => schedule.toFirestore(),
      );
  return PaymentScheduleRepository(collection);
});

final scheduleStreamProvider = StreamProvider.family<PaymentSchedule?, String>((ref, scheduleId) {
  return ref.watch(paymentScheduleRepositoryProvider).watchOne(scheduleId);
});

/// Installment repository for a single schedule's subcollection, scoped by
/// [scheduleId] — a fresh repository per schedule, mirrors
/// `ledgerRepositoryProvider`.
final installmentRepositoryProvider = Provider.family<InstallmentRepository, String>((ref, scheduleId) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.paymentSchedules)
      .doc(scheduleId)
      .collection(FirestoreCollections.installments)
      .withConverter<Installment>(
        fromFirestore: Installment.fromFirestore,
        toFirestore: (installment, _) => installment.toFirestore(),
      );
  return InstallmentRepository(collection);
});

final installmentsStreamProvider = StreamProvider.family<List<Installment>, String>((ref, scheduleId) {
  return ref.watch(installmentRepositoryProvider(scheduleId)).watchAll();
});

final installmentsTrashStreamProvider = StreamProvider.family<List<Installment>, String>((ref, scheduleId) {
  return ref.watch(installmentRepositoryProvider(scheduleId)).watchTrash();
});

/// Payment repository for a single installment's subcollection, scoped by
/// (scheduleId, installmentId).
final installmentPaymentRepositoryProvider =
    Provider.family<InstallmentPaymentRepository, ({String scheduleId, String installmentId})>((ref, key) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.paymentSchedules)
      .doc(key.scheduleId)
      .collection(FirestoreCollections.installments)
      .doc(key.installmentId)
      .collection(FirestoreCollections.payments)
      .withConverter<InstallmentPayment>(
        fromFirestore: InstallmentPayment.fromFirestore,
        toFirestore: (payment, _) => payment.toFirestore(),
      );
  return InstallmentPaymentRepository(collection, ref.watch(installmentRepositoryProvider(key.scheduleId)));
});

final installmentPaymentsStreamProvider =
    StreamProvider.family<List<InstallmentPayment>, ({String scheduleId, String installmentId})>((ref, key) {
  return ref.watch(installmentPaymentRepositoryProvider(key)).watchAll();
});

final installmentPaymentsTrashStreamProvider =
    StreamProvider.family<List<InstallmentPayment>, ({String scheduleId, String installmentId})>((ref, key) {
  return ref.watch(installmentPaymentRepositoryProvider(key)).watchTrash();
});

/// This calendar week's installments for [scheduleId].
final thisWeekInstallmentsProvider = Provider.family<List<Installment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return ref.watch(installmentRepositoryProvider(scheduleId)).thisWeek(installments);
});

/// This calendar month's installments for [scheduleId].
final thisMonthInstallmentsProvider = Provider.family<List<Installment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return ref.watch(installmentRepositoryProvider(scheduleId)).thisMonth(installments);
});

/// Next calendar month's installments for [scheduleId].
final nextMonthInstallmentsProvider = Provider.family<List<Installment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return ref.watch(installmentRepositoryProvider(scheduleId)).nextMonth(installments);
});

/// Installments due after next calendar month for [scheduleId].
final futureInstallmentsProvider = Provider.family<List<Installment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return ref.watch(installmentRepositoryProvider(scheduleId)).future(installments);
});

/// Overdue installments for [scheduleId].
final overdueInstallmentsProvider = Provider.family<List<Installment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return ref.watch(installmentRepositoryProvider(scheduleId)).overdue(installments);
});

/// Sum of remaining amounts across [scheduleId]'s non-skipped installments.
final remainingAmountProvider = Provider.family<double, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return ref.watch(installmentRepositoryProvider(scheduleId)).remainingAmount(installments);
});
