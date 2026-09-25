import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/prepayment_reamortization_policy.dart';
import 'package:finance_app/core/payment_schedule/domain/disbursement_reamortization_policy.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_adjustment_preview.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final loan = Loan(
    id: 'loan-1',
    loanAmount: 3000,
    loanDate: DateTime.utc(2026, 1, 1),
    repaymentType: LoanRepaymentType.installment,
    scheduleId: 'schedule-1',
    createdAt: DateTime.utc(2026, 1, 1),
    direction: LoanDirection.taken,
    category: LoanCategory.institutional,
    installmentFrequency: ScheduleType.monthly,
    installmentCount: 3,
  );

  Installment installment(int sequence, int month) => Installment(
    id: 'installment-$sequence',
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    sequenceNumber: sequence,
    dueDate: DateTime.utc(2026, month, 1),
    amountDue: 1000,
    amountPaid: 0,
    isSkipped: false,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  final installments = [
    installment(1, 2),
    installment(2, 3),
    installment(3, 4),
  ];

  test('keeps scheduled allocation and explicit prepayment distinct', () {
    final preview = previewPrincipalPrepayment(
      loan: loan,
      installments: installments,
      principalAmount: 500,
      date: DateTime.utc(2026, 1, 15),
    );

    expect(preview.scheduledAmount, 1000);
    expect(preview.principalAmount, 500);
    expect(preview.transactionAmount, 1500);
    expect(preview.principalBefore, 3000);
    expect(preview.maximumPrincipalAmount, 2000);
    expect(preview.principalAfter, 1500);
    expect(preview.outcome, isA<PrepaymentReamortizationSolved>());
    final outcome = preview.outcome! as PrepaymentReamortizationSolved;
    expect(outcome.remainingInstallmentCount, 2);
    expect(outcome.installmentAmount, 750);
  });

  test('uses Hold Tenure for an additional disbursement preview', () {
    final preview = previewAdditionalDisbursement(
      loan: loan,
      installments: installments,
      amount: 1500,
    );

    expect(preview.principalBefore, 3000);
    expect(preview.principalAfter, 4500);
    expect(preview.remainingInstallmentCount, 3);
    expect(preview.outcome, isA<DisbursementReamortizationSolved>());
    final outcome = preview.outcome! as DisbursementReamortizationSolved;
    expect(outcome.installmentAmount, 1500);
  });
}
