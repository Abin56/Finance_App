import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
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
final loansForPersonProvider = Provider.family<List<Loan>, String>((ref, personId) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.where((l) => l.personId == personId).toList();
});

/// A loan's current status, derived from its linked schedule's installments.
final loanStatusProvider = Provider.family<LoanStatus, Loan>((ref, loan) {
  final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
  return loan.statusGiven(installments);
});

/// Sum of remaining amounts across a loan's installments.
final loanRemainingAmountProvider = Provider.family<double, Loan>((ref, loan) {
  return ref.watch(remainingAmountProvider(loan.scheduleId));
});

/// Sum of amounts actually paid so far across a loan's installments.
final loanTotalReceivedProvider = Provider.family<double, Loan>((ref, loan) {
  final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
  return installments.fold(0.0, (sum, i) => sum + i.amountPaid);
});

/// Every non-closed loan.
final activeLoansProvider = Provider<List<Loan>>((ref) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.where((l) => ref.watch(loanStatusProvider(l)) != LoanStatus.closed).toList();
});

/// Every loan with at least one overdue installment, not closed.
final lendingOverdueLoansProvider = Provider<List<Loan>>((ref) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.where((l) => ref.watch(loanStatusProvider(l)) == LoanStatus.overdue).toList();
});

/// Lifetime total lent across every non-deleted loan (distinct from "amount
/// to receive", which nets out repayments already made).
final totalMoneyLentProvider = Provider<double>((ref) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.fold(0.0, (sum, l) => sum + l.loanAmount);
});

/// Sum of remaining amounts across every loan — the dashboard's "Amount to
/// receive" stat.
final totalAmountToReceiveProvider = Provider<double>((ref) {
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  return loans.fold(0.0, (sum, l) => sum + ref.watch(loanRemainingAmountProvider(l)));
});
