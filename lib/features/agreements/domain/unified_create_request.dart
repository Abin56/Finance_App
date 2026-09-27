import '../../../core/interest/interest_type.dart';
import '../../lending/domain/loan.dart';

/// Pure form logic for the unified "Add Loan / Installment" wizard —
/// validation, the explicit account-movement choice and the figures the
/// review step shows. Mirrors the web app's
/// `features/agreements/lib/unified-create-request.ts`; no Flutter/Firestore,
/// so it is unit-tested directly.
enum UnifiedCreateKind { borrowed, lent, installmentPurchase }

enum UnifiedRepayment { scheduled, oneTime }

class UnifiedCreateForm {
  const UnifiedCreateForm({
    this.kind,
    this.funding = LoanFundingSource.bank,
    this.name = '',
    this.provider = '',
    this.personId,
    this.amount = '',
    this.downPayment = '0',
    this.repayment = UnifiedRepayment.scheduled,
    this.count = '12',
    this.dueDate,
    this.rate = '',
    this.interestType = InterestType.reducingBalance,
    this.cardId,
    this.purchaseId,
    this.recordMovement = false,
    this.movementAccountId,
  });

  final UnifiedCreateKind? kind;
  final LoanFundingSource funding;
  final String name;
  final String provider;
  final String? personId;
  final String amount;
  final String downPayment;
  final UnifiedRepayment repayment;
  final String count;
  final DateTime? dueDate;
  final String rate;
  final InterestType interestType;
  final String? cardId;
  final String? purchaseId;

  /// The explicit opt-in — selecting an account alone never moves money.
  final bool recordMovement;
  final String? movementAccountId;

  bool get isOneTime =>
      kind != UnifiedCreateKind.installmentPurchase &&
      repayment == UnifiedRepayment.oneTime;
}

/// The toggle label for the account movement, or null when this agreement has
/// nothing to record.
String? movementChoiceLabel(UnifiedCreateForm form) => switch (form.kind) {
  UnifiedCreateKind.borrowed => 'Record money received in an account',
  UnifiedCreateKind.lent => 'Record money sent from an account',
  UnifiedCreateKind.installmentPurchase =>
    (double.tryParse(form.downPayment) ?? 0) > 0
        ? 'Record down payment from an account'
        : null,
  null => null,
};

class UnifiedCreateFigures {
  const UnifiedCreateFigures({
    required this.purchase,
    required this.down,
    required this.principal,
    required this.movesMoney,
    required this.movementAmount,
    required this.movementDelta,
  });

  final double purchase;
  final double down;
  final double principal;

  /// True only when the user opted in AND this agreement has a movement.
  final bool movesMoney;
  final double movementAmount;

  /// +received / −paid, as the Account will see it.
  final double movementDelta;
}

UnifiedCreateFigures unifiedCreateFigures(UnifiedCreateForm form) {
  final purchase = double.tryParse(form.amount) ?? 0;
  final down = form.kind == UnifiedCreateKind.installmentPurchase
      ? double.tryParse(form.downPayment) ?? 0
      : 0.0;
  final principal = purchase - down;
  final movesMoney = form.recordMovement && movementChoiceLabel(form) != null;
  final movementAmount = !movesMoney
      ? 0.0
      : form.kind == UnifiedCreateKind.installmentPurchase
      ? down
      : principal;
  return UnifiedCreateFigures(
    purchase: purchase,
    down: down,
    principal: principal,
    movesMoney: movesMoney,
    movementAmount: movementAmount,
    movementDelta: form.kind == UnifiedCreateKind.borrowed
        ? movementAmount
        : -movementAmount,
  );
}

/// Why the terms step can't continue yet, or null when it can.
String? unifiedCreateError(UnifiedCreateForm form) {
  final f = unifiedCreateFigures(form);
  final kind = form.kind;
  if (kind == null) return 'Choose what you are adding';
  if (form.name.trim().isEmpty) {
    return kind == UnifiedCreateKind.installmentPurchase
        ? 'Enter what you bought'
        : 'Enter a name';
  }
  if (!(f.purchase > 0)) return 'Enter an amount';
  if (f.down < 0 || f.down > f.purchase) {
    return 'Down payment must be between 0 and the purchase amount';
  }
  if (!(f.principal > 0)) return 'Nothing is left to finance';
  if (form.funding == LoanFundingSource.person && form.personId == null) {
    return 'Choose a person';
  }
  if (form.funding == LoanFundingSource.creditCard && form.cardId == null) {
    return 'Choose a credit card';
  }
  if (form.isOneTime && form.dueDate == null) {
    return 'Choose when it will be repaid';
  }
  final count = int.tryParse(form.count);
  if (!form.isOneTime && (count == null || count < 1)) {
    return 'Enter the number of payments';
  }
  if (form.rate.trim().isNotEmpty &&
      !((double.tryParse(form.rate) ?? -1) >= 0)) {
    return 'Interest rate cannot be negative';
  }
  if (f.movesMoney && form.movementAccountId == null) {
    return 'Choose the account';
  }
  return null;
}

String fundingLabel(LoanFundingSource value) => switch (value) {
  LoanFundingSource.bank => 'Bank',
  LoanFundingSource.financeCompany => 'Finance Company',
  LoanFundingSource.creditCard => 'Credit Card',
  LoanFundingSource.person => 'Person',
  LoanFundingSource.other => 'Other',
};
