import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../domain/person_timeline_builder.dart';
import '../../domain/person_timeline_entry.dart';
import 'people_providers.dart';

/// Every payment recorded across a loan's whole installment schedule —
/// fans out over the schedule's installments (payments are stored per
/// installment, not per schedule) since no schedule-wide payment stream
/// exists on `InstallmentPaymentRepository`.
final _loanPaymentsProvider = Provider.family<List<InstallmentPayment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return [
    for (final installment in installments)
      ...ref.watch(installmentPaymentsStreamProvider((scheduleId: scheduleId, installmentId: installment.id))).value ??
          const [],
  ];
});

/// One person's complete financial timeline — folds their [LedgerEntry]s
/// (money given/borrowed/received/repaid/adjustments, and — since
/// `ExpenseRepository` already posts ledger entries for person-linked
/// expense participants — assigned/split expenses too) together with their
/// [Loan]s and loan payments, via [PersonTimelineBuilder]. This is the one
/// place all of a person's money-interaction sources are pulled together.
final personTimelineProvider = Provider.family<List<PersonTimelineEntry>, String>((ref, personId) {
  final ledgerEntries = ref.watch(ledgerStreamProvider(personId)).value ?? const [];
  final loans = ref.watch(loansForPersonProvider(personId));
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];

  final loanData = [
    for (final loan in loans)
      LoanTimelineData(
        loan: loan,
        installments: ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [],
        payments: ref.watch(_loanPaymentsProvider(loan.scheduleId)),
      ),
  ];

  final participantCountByTransactionRef = {
    for (final expense in expenses) expense.transactionId: expense.participants.length,
  };

  final installmentStatusByTransactionRef = <String, InstallmentStatus>{};
  for (final expense in expenses) {
    if (expense.scheduleId == null) continue;
    final participant = expense.participants.where((p) => p.personId == personId).firstOrNull;
    if (participant?.installmentId == null) continue;
    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final installment = installments.where((i) => i.id == participant!.installmentId).firstOrNull;
    if (installment == null) continue;
    installmentStatusByTransactionRef[expense.transactionId] = installment.status;
  }

  return PersonTimelineBuilder.build(
    ledgerEntries: ledgerEntries,
    loans: loanData,
    participantCountByTransactionRef: participantCountByTransactionRef,
    installmentStatusByTransactionRef: installmentStatusByTransactionRef,
  );
});
