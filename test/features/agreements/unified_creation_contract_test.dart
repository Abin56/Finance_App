import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Loan uses conservative additive defaults', () {
    final value = Loan(
      id: 'legacy',
      loanAmount: 1000,
      loanDate: DateTime(2026),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 2),
      scheduleId: 'schedule',
      createdAt: DateTime(2026),
    );
    expect(value.agreementKind, LoanAgreementKind.loan);
    expect(value.fundingSource, isNull);
    expect(value.purchaseAmount, isNull);
  });

  test('installment purchase serializes the Web-compatible field contract', () {
    final value = Loan(
      id: 'purchase',
      loanAmount: 50000,
      loanDate: DateTime(2026),
      repaymentType: LoanRepaymentType.installment,
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 12,
      scheduleId: 'schedule',
      createdAt: DateTime(2026),
      agreementKind: LoanAgreementKind.installmentPurchase,
      fundingSource: LoanFundingSource.creditCard,
      linkedCreditCardId: 'card-1',
      purchaseTransactionId: 'txn-1',
      purchaseAmount: 60000,
      downPayment: 10000,
    );
    final data = value.toFirestore();
    expect(
      [
        data['agreementKind'],
        data['fundingSource'],
        data['linkedCreditCardId'],
        data['purchaseTransactionId'],
        data['purchaseAmount'],
        data['downPayment'],
        data['loanAmount'],
      ],
      [
        'installmentPurchase',
        'creditCard',
        'card-1',
        'txn-1',
        60000,
        10000,
        50000,
      ],
    );
  });
}
