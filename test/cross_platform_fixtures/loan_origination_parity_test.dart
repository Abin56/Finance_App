// Cross-platform parity for unified-agreement origination. flowfi-web loads a
// byte-identical copy of `loan_origination_fixture.json`
// (tests/cross-platform-fixtures/loan-origination-parity.test.ts) and asserts
// the same ids, movement direction, schedule shape, principal effect and
// income/expense classification.
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/core/payment_schedule/domain/payment_allocation_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_origination.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File(
            'test/cross_platform_fixtures/loan_origination_fixture.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

LoanAgreementKind _kind(String name) =>
    LoanAgreementKind.values.firstWhere((v) => v.name == name);
LoanDirection _direction(String name) =>
    LoanDirection.values.firstWhere((v) => v.name == name);
LoanFundingSource? _funding(String? name) => name == null
    ? null
    : LoanFundingSource.values.firstWhere((v) => v.name == name);
double? _num(Object? v) => (v as num?)?.toDouble();

void main() {
  final fixture = _fixture();

  test('derives every document id from the idempotency key', () {
    final ids = OriginationIds(fixture['idempotencyKey'] as String);
    final expected = fixture['ids'] as Map<String, dynamic>;
    expect(ids.loanId, expected['loanId']);
    expect(ids.scheduleId, expected['scheduleId']);
    expect(ids.transactionId, expected['transactionId']);
    (expected['installmentIds'] as Map<String, dynamic>).forEach(
      (seq, id) => expect(ids.installmentId(int.parse(seq)), id),
    );
    expect(isOriginationTransactionId(ids.transactionId), isTrue);
    expect(isOriginationTransactionId('disb_x_txn'), isFalse);
    expect(maxAtomicOriginationInstallments, fixture['maxAtomicInstallments']);
  });

  test('rejects keys that are not safe, stable document-id fragments', () {
    for (final key in (fixture['invalidKeys'] as List).cast<String>()) {
      expect(() => assertValidOriginationKey(key), throwsA(anything));
    }
  });

  for (final scenario
      in (fixture['scenarios'] as List).cast<Map<String, dynamic>>()) {
    test(scenario['name'], () {
      final input = scenario['input'] as Map<String, dynamic>;
      final expected = scenario['expected'] as Map<String, dynamic>;
      final kind = _kind(input['agreementKind'] as String);
      final direction = _direction(input['direction'] as String);
      final movement = planOriginationMovement(
        agreementKind: kind,
        direction: direction,
        loanAmount: _num(input['loanAmount'])!,
        downPayment: _num(input['downPayment']),
        movementAccountId: input['movementAccountId'] as String?,
      );
      final expectedMovement = expected['movement'] as Map<String, dynamic>?;
      if (expectedMovement == null) {
        expect(movement, isNull);
      } else {
        expect(movement!.kind.name, expectedMovement['kind']);
        expect(
          movement.transactionType.name,
          expectedMovement['transactionType'],
        );
        expect(movement.amount, _num(expectedMovement['amount']));
        expect(movement.balanceDelta, _num(expectedMovement['balanceDelta']));
        expect(
          movement.allocationType?.name,
          expectedMovement['allocationType'],
        );
        final txn = Transaction(
          id: 'orig_k_txn',
          type: movement.transactionType,
          amount: movement.amount,
          dateTime: DateTime(2026),
          accountId: 'a',
          categoryId: 'loan_payment',
          createdAt: DateTime(2026),
          loanId: 'loan',
          paymentAllocationType: movement.allocationType,
        );
        expect(
          !txn.isNonIncomeExpenseMovement,
          expectedMovement['countsAsIncomeExpense'],
        );
      }

      final shape = originationScheduleShape(
        LoanRepaymentType.values.firstWhere(
          (v) => v.name == input['repaymentType'],
        ),
        input['installmentFrequency'] == null
            ? null
            : ScheduleType.values.firstWhere(
                (v) => v.name == input['installmentFrequency'],
              ),
        input['installmentCount'] as int?,
      );
      final schedule = expected['schedule'] as Map<String, dynamic>;
      expect(shape.scheduleType.name, schedule['scheduleType']);
      expect(shape.installmentCount, schedule['installmentCount']);

      final effect = originationPrincipalEffect(
        agreementKind: kind,
        direction: direction,
        fundingSource: _funding(input['fundingSource'] as String?),
        loanAmount: _num(input['loanAmount'])!,
        downPayment: _num(input['downPayment']),
        movementAccountId: input['movementAccountId'] as String?,
      );
      final expectedEffect = expected['effect'] as Map<String, dynamic>;
      expect(effect.accountDelta, _num(expectedEffect['accountDelta']));
      expect(effect.liabilityDelta, _num(expectedEffect['liabilityDelta']));
      expect(effect.receivableDelta, _num(expectedEffect['receivableDelta']));
    });
  }

  for (final scenario
      in (fixture['rejected'] as List).cast<Map<String, dynamic>>()) {
    test('rejects: ${scenario['name']}', () {
      final input = scenario['input'] as Map<String, dynamic>;
      expect(
        () => planOriginationMovement(
          agreementKind: _kind(input['agreementKind'] as String),
          direction: _direction(input['direction'] as String),
          loanAmount: _num(input['loanAmount'])!,
          downPayment: _num(input['downPayment']),
          movementAccountId: input['movementAccountId'] as String?,
        ),
        throwsA(anything),
      );
    });
  }

  test('allocation reuse: principal movements are the existing value', () {
    expect(
      PaymentAllocationType.values.map((v) => v.name),
      contains('additionalDisbursement'),
    );
    expect(TransactionType.values.map((v) => v.name), ['income', 'expense']);
  });

  test('recovers the origination key from a Loan id', () {
    for (final row
        in (fixture['loanIdKeys'] as List).cast<Map<String, dynamic>>()) {
      expect(originationKeyFromLoanId(row['loanId'] as String), row['key']);
    }
  });

  for (final row
      in (fixture['reversalMessages'] as List).cast<Map<String, dynamic>>()) {
    test('confirmation copy: ${row['message']}', () {
      final movement = row['movement'] as Map<String, dynamic>?;
      expect(
        originationReversalMessage(
          movement == null
              ? null
              : (
                  kind: originationMovementKindOf(
                    type: TransactionType.values.byName(
                      movement['type'] as String,
                    ),
                    paymentAllocationType:
                        movement['paymentAllocationType'] == null
                        ? null
                        : PaymentAllocationType.values.byName(
                            movement['paymentAllocationType'] as String,
                          ),
                  ),
                  amount: _num(movement['amount'])!,
                  accountName: movement['accountName'] as String,
                ),
        ),
        row['message'],
      );
    });
  }
}
