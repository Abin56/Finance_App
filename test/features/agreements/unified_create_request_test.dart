import 'package:finance_app/features/agreements/domain/unified_create_request.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:flutter_test/flutter_test.dart';

UnifiedCreateForm form({
  UnifiedCreateKind? kind = UnifiedCreateKind.borrowed,
  LoanFundingSource funding = LoanFundingSource.bank,
  String amount = '50000',
  String downPayment = '0',
  UnifiedRepayment repayment = UnifiedRepayment.scheduled,
  DateTime? dueDate,
  String? personId,
  String? cardId,
  bool recordMovement = false,
  String? movementAccountId,
}) => UnifiedCreateForm(
  kind: kind,
  funding: funding,
  name: 'Test',
  amount: amount,
  downPayment: downPayment,
  repayment: repayment,
  dueDate: dueDate,
  personId: personId,
  cardId: cardId,
  recordMovement: recordMovement,
  movementAccountId: movementAccountId,
);

void main() {
  group('account movement choice (parity with web unified-create-request)', () {
    test('labels the explicit opt-in per agreement kind', () {
      expect(
        movementChoiceLabel(form()),
        'Record money received in an account',
      );
      expect(
        movementChoiceLabel(form(kind: UnifiedCreateKind.lent)),
        'Record money sent from an account',
      );
      expect(
        movementChoiceLabel(
          form(
            kind: UnifiedCreateKind.installmentPurchase,
            downPayment: '10000',
          ),
        ),
        'Record down payment from an account',
      );
      expect(
        movementChoiceLabel(form(kind: UnifiedCreateKind.installmentPurchase)),
        isNull,
      );
    });

    test('selecting an account alone never moves money', () {
      expect(
        unifiedCreateFigures(form(movementAccountId: 'hdfc')).movesMoney,
        isFalse,
      );
    });

    test('an account is required only when the movement is enabled', () {
      expect(unifiedCreateError(form()), isNull);
      expect(
        unifiedCreateError(form(recordMovement: true)),
        'Choose the account',
      );
      expect(
        unifiedCreateError(
          form(recordMovement: true, movementAccountId: 'hdfc'),
        ),
        isNull,
      );
    });

    test('a stale opt-in on a zero down payment is ignored', () {
      final f = form(
        kind: UnifiedCreateKind.installmentPurchase,
        amount: '60000',
        recordMovement: true,
      );
      expect(unifiedCreateError(f), isNull);
      expect(unifiedCreateFigures(f).movesMoney, isFalse);
    });

    test(
      'borrowed +principal; lent −principal; purchase −down payment only',
      () {
        expect(
          unifiedCreateFigures(
            form(recordMovement: true, movementAccountId: 'a'),
          ).movementDelta,
          50000,
        );
        expect(
          unifiedCreateFigures(
            form(
              kind: UnifiedCreateKind.lent,
              recordMovement: true,
              movementAccountId: 'a',
            ),
          ).movementDelta,
          -50000,
        );
        final purchase = unifiedCreateFigures(
          form(
            kind: UnifiedCreateKind.installmentPurchase,
            amount: '60000',
            downPayment: '10000',
            recordMovement: true,
            movementAccountId: 'a',
          ),
        );
        expect(purchase.principal, 50000);
        expect(purchase.movementDelta, -10000);
      },
    );
  });

  group('one-time repayment', () {
    test('needs a repay-by date and skips the payment count', () {
      expect(
        unifiedCreateError(form(repayment: UnifiedRepayment.oneTime)),
        'Choose when it will be repaid',
      );
      expect(
        unifiedCreateError(
          form(
            repayment: UnifiedRepayment.oneTime,
            dueDate: DateTime(2026, 12, 31),
          ),
        ),
        isNull,
      );
    });

    test('is never offered to an installment purchase', () {
      final f = form(
        kind: UnifiedCreateKind.installmentPurchase,
        amount: '60000',
        downPayment: '10000',
        repayment: UnifiedRepayment.oneTime,
      );
      expect(f.isOneTime, isFalse);
    });
  });

  test('person funding requires a person; card funding requires a card', () {
    expect(
      unifiedCreateError(
        form(kind: UnifiedCreateKind.lent, funding: LoanFundingSource.person),
      ),
      'Choose a person',
    );
    expect(
      unifiedCreateError(
        form(
          kind: UnifiedCreateKind.installmentPurchase,
          funding: LoanFundingSource.creditCard,
        ),
      ),
      'Choose a credit card',
    );
  });
}
