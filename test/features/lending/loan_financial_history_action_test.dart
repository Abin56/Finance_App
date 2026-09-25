import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_allocation_type.dart';
import 'package:finance_app/features/lending/domain/loan_additional_disbursement.dart';
import 'package:finance_app/features/lending/domain/loan_financial_history_action.dart';
import 'package:finance_app/features/lending/domain/loan_reamortization_event.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);
  Installment installment(int sequence) => Installment(
    id: 'i$sequence',
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    sequenceNumber: sequence,
    dueDate: DateTime.utc(2026, sequence + 1, 1),
    amountDue: 3000,
    amountPaid: 3000,
    isSkipped: false,
    createdAt: createdAt,
  );
  InstallmentPayment payment(
    int sequence, {
    PaymentAllocationType type = PaymentAllocationType.advanceEmi,
    double amount = 3000,
  }) => InstallmentPayment(
    id: 'p$sequence',
    installmentId: 'i$sequence',
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    amount: amount,
    date: DateTime.utc(2026, 1, 15),
    createdAt: createdAt,
    allocationType: type,
    remainingBalanceAfterPayment: 0,
    transactionId: 'txn-1',
  );
  Transaction transaction({double amount = 9000}) => Transaction(
    id: 'txn-1',
    type: TransactionType.expense,
    amount: amount,
    dateTime: DateTime.utc(2026, 1, 15),
    accountId: 'account-1',
    categoryId: 'loan_payment',
    createdAt: createdAt,
    loanId: 'loan-1',
    installmentId: 'i1',
    installmentPaymentId: 'p1',
  );

  test('groups a multi-installment payment by persisted transaction id', () {
    final actions = composeLoanFinancialHistory(
      installments: [installment(1), installment(2), installment(3)],
      payments: [payment(1), payment(2), payment(3)],
      transactions: [transaction()],
      disbursements: const [],
      reamortizationEvents: const [],
    );

    expect(actions, hasLength(1));
    expect(
      actions.single.kind,
      LoanFinancialHistoryKind.multiInstallmentPayment,
    );
    expect(actions.single.amount, 9000);
    expect(actions.single.accountId, 'account-1');
    expect(
      actions.single.allocations.map((item) => item.installmentSequenceNumber),
      [1, 2, 3],
    );
  });

  test('links a re-amortization event and retains reversed prepayment', () {
    final prepayment = payment(
      3,
      type: PaymentAllocationType.principalPrepayment,
      amount: 5000,
    )..deletedAt = DateTime.utc(2026, 1, 20);
    final event = LoanReamortizationEvent(
      id: 'event-1',
      loanId: 'loan-1',
      triggerType: ReamortizationTriggerType.prepayment,
      triggeredByPaymentId: 'p3',
      principalBefore: 42000,
      principalAfter: 37000,
      installmentCountBefore: 14,
      installmentCountAfter: 12,
      date: DateTime.utc(2026, 1, 15),
      createdAt: createdAt,
      reversed: true,
      reversedAt: DateTime.utc(2026, 1, 20),
    );
    final actions = composeLoanFinancialHistory(
      installments: [installment(1), installment(3)],
      payments: [payment(1), prepayment],
      transactions: [
        transaction(amount: 8000)..deletedAt = DateTime.utc(2026, 1, 20),
      ],
      disbursements: const [],
      reamortizationEvents: [event],
    );

    expect(actions, hasLength(1));
    expect(actions.single.kind, LoanFinancialHistoryKind.principalPrepayment);
    expect(actions.single.amount, 8000);
    expect(actions.single.reversed, isTrue);
    expect(actions.single.reamortizationEvent?.principalAfter, 37000);
  });

  test('links and retains a reversed additional disbursement', () {
    final item = LoanAdditionalDisbursement(
      id: 'd1',
      loanId: 'loan-1',
      amount: 10000,
      date: DateTime.utc(2026, 2, 1),
      createdAt: createdAt,
      transactionId: 'txn-d1',
    )..deletedAt = DateTime.utc(2026, 2, 2);
    final actions = composeLoanFinancialHistory(
      installments: const [],
      payments: const [],
      transactions: const [],
      disbursements: [item],
      reamortizationEvents: const [],
    );

    expect(
      actions.single.kind,
      LoanFinancialHistoryKind.additionalDisbursement,
    );
    expect(actions.single.amount, 10000);
    expect(actions.single.reversed, isTrue);
  });
}
