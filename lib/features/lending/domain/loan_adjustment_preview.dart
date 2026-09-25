import '../../../core/payment_schedule/domain/disbursement_reamortization_policy.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_settlement.dart';
import '../../../core/payment_schedule/domain/prepayment_reamortization_policy.dart';
import 'loan.dart';
import 'loan_financial_summary.dart';

class PrincipalPrepaymentPreview {
  const PrincipalPrepaymentPreview({
    required this.scheduledAmount,
    required this.principalAmount,
    required this.transactionAmount,
    required this.principalBefore,
    required this.maximumPrincipalAmount,
    required this.principalAfter,
    required this.installmentCountBefore,
    required this.outcome,
  });
  final double scheduledAmount;
  final double principalAmount;
  final double transactionAmount;
  final double principalBefore;
  final double maximumPrincipalAmount;
  final double principalAfter;
  final int installmentCountBefore;
  final PrepaymentReamortizationOutcome? outcome;
}

PrincipalPrepaymentPreview previewPrincipalPrepayment({
  required Loan loan,
  required List<Installment> installments,
  required double principalAmount,
  required DateTime date,
}) {
  final eligible =
      installments
          .where(
            (i) => i.deletedAt == null && !i.isSkipped && i.remainingAmount > 0,
          )
          .toList()
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  final due = eligible.where((i) => !i.dueDate.isAfter(date)).toList();
  final scope = due.isNotEmpty ? due : eligible.take(1).toList();
  final scheduledAmount = scope.fold(0.0, (sum, i) => sum + i.remainingAmount);
  final plan = scheduledAmount > 0
      ? InstallmentSettlement.plan(scope, scheduledAmount)
      : const InstallmentSettlementPlan(portions: [], unallocated: 0);
  final paidById = {
    for (final portion in plan.portions)
      portion.installment.id: portion.portion,
  };
  final afterScheduled = installments.map((i) {
    final clone = Installment(
      id: i.id,
      scheduleId: i.scheduleId,
      ownerType: i.ownerType,
      ownerId: i.ownerId,
      sequenceNumber: i.sequenceNumber,
      dueDate: i.dueDate,
      amountDue: i.amountDue,
      amountPaid: (i.amountPaid + (paidById[i.id] ?? 0))
          .clamp(0, i.amountDue)
          .toDouble(),
      isSkipped: i.isSkipped,
      principalPortion: i.principalPortion,
      interestPortion: i.interestPortion,
      createdAt: i.createdAt,
    );
    clone.deletedAt = i.deletedAt;
    return clone;
  }).toList();
  final principalBefore = LoanFinancialSummary.from(
    installments: installments,
    originalPrincipal: loan.loanAmount,
  ).principalRemaining;
  final afterScheduledPrincipal = LoanFinancialSummary.from(
    installments: afterScheduled,
    originalPrincipal: loan.loanAmount,
  ).principalRemaining;
  final principalAfter = (afterScheduledPrincipal - principalAmount)
      .clamp(0, loan.loanAmount)
      .toDouble();
  final untouched =
      afterScheduled
          .where(
            (i) => i.deletedAt == null && !i.isSkipped && i.amountPaid == 0,
          )
          .toList()
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  final outcome =
      untouched.isEmpty ||
          principalAmount <= 0 ||
          loan.installmentFrequency == null
      ? null
      : const ReduceTenurePolicy().solve(
          outstandingPrincipalAfter: principalAfter,
          interest: loan.interest == null
              ? null
              : ReamortizationInterestConfig(
                  type: loan.interest!.type,
                  ratePercent: loan.interest!.ratePercent,
                  period: loan.interest!.period,
                ),
          targetInstallmentAmount: untouched.first.amountDue,
          frequency: loan.installmentFrequency!,
        );
  return PrincipalPrepaymentPreview(
    scheduledAmount: scheduledAmount,
    principalAmount: principalAmount,
    transactionAmount: scheduledAmount + principalAmount,
    principalBefore: principalBefore,
    maximumPrincipalAmount: afterScheduledPrincipal,
    principalAfter: principalAfter,
    installmentCountBefore: loan.installmentCount ?? installments.length,
    outcome: outcome,
  );
}

class AdditionalDisbursementPreview {
  const AdditionalDisbursementPreview({
    required this.principalBefore,
    required this.principalAfter,
    required this.remainingInstallmentCount,
    required this.currentInstallmentAmount,
    required this.outcome,
  });
  final double principalBefore;
  final double principalAfter;
  final int remainingInstallmentCount;
  final double? currentInstallmentAmount;
  final DisbursementReamortizationOutcome? outcome;
}

AdditionalDisbursementPreview previewAdditionalDisbursement({
  required Loan loan,
  required List<Installment> installments,
  required double amount,
}) {
  final principalBefore = LoanFinancialSummary.from(
    installments: installments,
    originalPrincipal: loan.loanAmount,
  ).principalRemaining;
  final untouched =
      installments
          .where(
            (i) => i.deletedAt == null && !i.isSkipped && i.amountPaid == 0,
          )
          .toList()
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  final principalAfter = principalBefore + amount;
  final outcome =
      amount <= 0 || untouched.isEmpty || loan.installmentFrequency == null
      ? null
      : const HoldTenurePolicy().solve(
          outstandingPrincipalAfter: principalAfter,
          interest: loan.interest == null
              ? null
              : ReamortizationInterestConfig(
                  type: loan.interest!.type,
                  ratePercent: loan.interest!.ratePercent,
                  period: loan.interest!.period,
                ),
          remainingInstallmentCount: untouched.length,
          frequency: loan.installmentFrequency!,
        );
  return AdditionalDisbursementPreview(
    principalBefore: principalBefore,
    principalAfter: principalAfter,
    remainingInstallmentCount: untouched.length,
    currentInstallmentAmount: untouched.firstOrNull?.amountDue,
    outcome: outcome,
  );
}
