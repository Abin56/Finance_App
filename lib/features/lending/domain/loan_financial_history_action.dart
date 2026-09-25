import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../core/payment_schedule/domain/payment_allocation_type.dart';
import '../../transactions/domain/transaction.dart';
import 'loan_additional_disbursement.dart';
import 'loan_reamortization_event.dart';

enum LoanFinancialHistoryKind {
  regularEmi,
  partialEmi,
  advanceEmi,
  multiInstallmentPayment,
  principalPrepayment,
  additionalDisbursement,
}

class LoanPaymentAllocation {
  const LoanPaymentAllocation({
    required this.paymentId,
    required this.installmentId,
    required this.installmentSequenceNumber,
    required this.amount,
    required this.allocationType,
  });

  final String paymentId;
  final String installmentId;
  final int installmentSequenceNumber;
  final double amount;
  final PaymentAllocationType allocationType;
}

class LoanFinancialHistoryAction {
  const LoanFinancialHistoryAction({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    required this.reversed,
    required this.allocations,
    this.transactionId,
    this.accountId,
    this.note = '',
    this.reversedAt,
    this.reamortizationEvent,
  });

  final String id;
  final LoanFinancialHistoryKind kind;
  final double amount;
  final DateTime date;
  final bool reversed;
  final List<LoanPaymentAllocation> allocations;
  final String? transactionId;
  final String? accountId;
  final String note;
  final DateTime? reversedAt;
  final LoanReamortizationEvent? reamortizationEvent;
}

List<LoanFinancialHistoryAction> composeLoanFinancialHistory({
  required List<Installment> installments,
  required List<InstallmentPayment> payments,
  required List<Transaction> transactions,
  required List<LoanAdditionalDisbursement> disbursements,
  required List<LoanReamortizationEvent> reamortizationEvents,
}) {
  final installmentById = {for (final item in installments) item.id: item};
  final transactionById = {for (final item in transactions) item.id: item};
  final eventByPaymentId = <String, LoanReamortizationEvent>{};
  final eventByDisbursementId = <String, LoanReamortizationEvent>{};
  for (final event in reamortizationEvents) {
    if (event.triggeredByPaymentId != null) {
      eventByPaymentId[event.triggeredByPaymentId!] = event;
    }
    if (event.triggeredByDisbursementId != null) {
      eventByDisbursementId[event.triggeredByDisbursementId!] = event;
    }
  }

  final paymentGroups = <String, List<InstallmentPayment>>{};
  for (final payment in payments) {
    final key = payment.transactionId == null
        ? 'payment:${payment.id}'
        : 'transaction:${payment.transactionId}';
    paymentGroups.putIfAbsent(key, () => []).add(payment);
  }

  final actions = <LoanFinancialHistoryAction>[];
  for (final group in paymentGroups.entries) {
    final groupPayments = group.value
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final transactionId = groupPayments.first.transactionId;
    final transaction = transactionId == null
        ? null
        : transactionById[transactionId];
    LoanReamortizationEvent? event;
    for (final payment in groupPayments) {
      event ??= eventByPaymentId[payment.id];
    }
    final scheduledPayments = groupPayments
        .where(
          (payment) =>
              payment.allocationType !=
              PaymentAllocationType.principalPrepayment,
        )
        .toList();
    final hasPrepayment = groupPayments.any(
      (payment) =>
          payment.allocationType == PaymentAllocationType.principalPrepayment,
    );
    final hasAdvance = groupPayments.any(
      (payment) => payment.allocationType == PaymentAllocationType.advanceEmi,
    );
    final kind = hasPrepayment
        ? LoanFinancialHistoryKind.principalPrepayment
        : scheduledPayments.length > 1
        ? LoanFinancialHistoryKind.multiInstallmentPayment
        : hasAdvance
        ? LoanFinancialHistoryKind.advanceEmi
        : scheduledPayments.single.remainingBalanceAfterPayment != null &&
              scheduledPayments.single.remainingBalanceAfterPayment! > 0
        ? LoanFinancialHistoryKind.partialEmi
        : LoanFinancialHistoryKind.regularEmi;
    final allocations = <LoanPaymentAllocation>[
      for (final payment in groupPayments)
        LoanPaymentAllocation(
          paymentId: payment.id,
          installmentId: payment.installmentId,
          installmentSequenceNumber:
              installmentById[payment.installmentId]?.sequenceNumber ?? 0,
          amount: payment.amount,
          allocationType: payment.allocationType,
        ),
    ];
    actions.add(
      LoanFinancialHistoryAction(
        id: group.key,
        kind: kind,
        amount:
            transaction?.amount ??
            groupPayments.fold(0, (sum, payment) => sum + payment.amount),
        date: transaction?.dateTime ?? groupPayments.first.date,
        reversed:
            transaction?.deletedAt != null ||
            groupPayments.any((payment) => payment.deletedAt != null) ||
            event?.reversed == true,
        reversedAt: event?.reversedAt ?? transaction?.deletedAt,
        allocations: allocations,
        transactionId: transactionId,
        accountId: transaction?.accountId,
        note: groupPayments.first.note,
        reamortizationEvent: event,
      ),
    );
  }

  for (final disbursement in disbursements) {
    final transaction = disbursement.transactionId == null
        ? null
        : transactionById[disbursement.transactionId];
    final event = eventByDisbursementId[disbursement.id];
    actions.add(
      LoanFinancialHistoryAction(
        id: 'disbursement:${disbursement.id}',
        kind: LoanFinancialHistoryKind.additionalDisbursement,
        amount: transaction?.amount ?? disbursement.amount,
        date: transaction?.dateTime ?? disbursement.date,
        reversed:
            disbursement.deletedAt != null ||
            transaction?.deletedAt != null ||
            event?.reversed == true,
        reversedAt: event?.reversedAt ?? transaction?.deletedAt,
        allocations: const [],
        transactionId: disbursement.transactionId,
        accountId: transaction?.accountId,
        note: disbursement.note,
        reamortizationEvent: event,
      ),
    );
  }

  actions.sort((a, b) => b.date.compareTo(a.date));
  return actions;
}
