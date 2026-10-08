import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/payment_schedule/domain/payment_allocation_type.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import '../../transactions/domain/transaction_type.dart';
import 'loan.dart';
import 'loan_direction.dart';
import 'loan_repayment_type.dart';

/// Pure origination contract for [LoanRepository.createAgreementWithOrigination]
/// — deterministic document ids and the single physical money movement (if
/// any) a new Loan-backed agreement records. Mirrors the web app's
/// `lib/engines/loan-origination.ts` exactly; both are held to the same answers
/// by `test/cross_platform_fixtures/loan_origination_fixture.json`.
///
/// Rules:
///  - Account movement is opt-in. With no `movementAccountId` there is no
///    Transaction and no Account write.
///  - Money I Borrowed ([LoanAgreementKind.loan], [LoanDirection.taken])
///    records the principal received: +loanAmount into the Account.
///  - Money I Lent ([LoanDirection.given]) records the principal sent:
///    −loanAmount out of the Account.
///  - Installment Purchase records only the down payment actually paid now:
///    −downPayment. The financed principal never moves an Account at
///    origination, and no purchase Transaction is ever created here — a
///    tracked card purchase is linked by `purchaseTransactionId`, never
///    invented.
///  - Principal movements reuse the existing
///    [PaymentAllocationType.additionalDisbursement] (a principal
///    disbursement, not income/spending — see
///    `Transaction.isLoanPrincipalDisbursement`). A down payment carries no
///    allocation, so it keeps ordinary purchase (expense) semantics.

/// Loan + schedule + installments + (Transaction + Account) must fit one
/// Firestore transaction commit (500 writes); staying well below keeps the
/// whole origination one atomic commit instead of a multi-phase state machine.
const maxAtomicOriginationInstallments = 480;

final _idempotencyKeyPattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

void assertValidOriginationKey(String idempotencyKey) {
  if (!_idempotencyKeyPattern.hasMatch(idempotencyKey)) {
    throw const AppException(
      "Origination idempotency key must be 8–128 letters, digits, '-' or '_'",
    );
  }
}

class OriginationIds {
  OriginationIds(String idempotencyKey) : _prefix = 'orig_$idempotencyKey' {
    assertValidOriginationKey(idempotencyKey);
  }

  final String _prefix;

  String get loanId => '${_prefix}_loan';
  String get scheduleId => '${_prefix}_sched';
  String get transactionId => '${_prefix}_txn';

  /// 1-based, matching `Installment.sequenceNumber`.
  String installmentId(int sequenceNumber) => '${_prefix}_inst_$sequenceNumber';
}

/// True for a Transaction written by an origination (labels only — never used
/// for money math).
bool isOriginationTransactionId(String transactionId) =>
    transactionId.startsWith('orig_') && transactionId.endsWith('_txn');

enum OriginationMovementKind {
  principalReceived,
  principalSent,
  downPaymentPaid,
}

class OriginationMovement {
  const OriginationMovement({
    required this.kind,
    required this.transactionType,
    required this.amount,
    required this.balanceDelta,
    required this.allocationType,
  });

  final OriginationMovementKind kind;
  final TransactionType transactionType;
  final double amount;

  /// Signed `Account.currentBalance` delta.
  final double balanceDelta;
  final PaymentAllocationType? allocationType;
}

OriginationMovement? planOriginationMovement({
  required LoanAgreementKind agreementKind,
  required LoanDirection direction,
  required double loanAmount,
  required double? downPayment,
  required String? movementAccountId,
}) {
  if (movementAccountId == null) return null;
  if (agreementKind == LoanAgreementKind.installmentPurchase) {
    final down = downPayment ?? 0;
    if (!(down > 0)) {
      throw const AppException('There is no down payment to record');
    }
    return OriginationMovement(
      kind: OriginationMovementKind.downPaymentPaid,
      transactionType: TransactionType.expense,
      amount: down,
      balanceDelta: -down,
      allocationType: null,
    );
  }
  return direction == LoanDirection.taken
      ? OriginationMovement(
          kind: OriginationMovementKind.principalReceived,
          transactionType: TransactionType.income,
          amount: loanAmount,
          balanceDelta: loanAmount,
          allocationType: PaymentAllocationType.additionalDisbursement,
        )
      : OriginationMovement(
          kind: OriginationMovementKind.principalSent,
          transactionType: TransactionType.expense,
          amount: loanAmount,
          balanceDelta: -loanAmount,
          allocationType: PaymentAllocationType.additionalDisbursement,
        );
}

String originationDescription(OriginationMovementKind kind, String? name) {
  final label = switch (kind) {
    OriginationMovementKind.principalReceived => 'Loan received',
    OriginationMovementKind.principalSent => 'Money I Gave',
    OriginationMovementKind.downPaymentPaid => 'Down payment',
  };
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? label : '$label — $trimmed';
}

/// Schedule shape for a new Loan: a one-time loan is one
/// [ScheduleType.oneTime] installment on its due date — never fake monthly
/// rows.
({ScheduleType scheduleType, int installmentCount}) originationScheduleShape(
  LoanRepaymentType repaymentType,
  ScheduleType? installmentFrequency,
  int? installmentCount,
) => repaymentType == LoanRepaymentType.oneTime
    ? (scheduleType: ScheduleType.oneTime, installmentCount: 1)
    : (
        scheduleType: installmentFrequency!,
        installmentCount: installmentCount!,
      );

/// Balance-sheet effect of the origination itself (before any repayment). A
/// card-financed purchase adds no Loan-owned liability — the card owns that
/// exposure, exactly as `UnifiedFinanceAgreement.fromLoan` reports it.
({double accountDelta, double liabilityDelta, double receivableDelta})
originationPrincipalEffect({
  required LoanAgreementKind agreementKind,
  required LoanDirection direction,
  required LoanFundingSource? fundingSource,
  required double loanAmount,
  required double? downPayment,
  required String? movementAccountId,
}) {
  final movement = planOriginationMovement(
    agreementKind: agreementKind,
    direction: direction,
    loanAmount: loanAmount,
    downPayment: downPayment,
    movementAccountId: movementAccountId,
  );
  final accountDelta = movement?.balanceDelta ?? 0.0;
  if (direction == LoanDirection.given) {
    return (
      accountDelta: accountDelta,
      liabilityDelta: 0.0,
      receivableDelta: loanAmount,
    );
  }
  final cardOwned =
      agreementKind == LoanAgreementKind.installmentPurchase &&
      fundingSource == LoanFundingSource.creditCard;
  return (
    accountDelta: accountDelta,
    liabilityDelta: cardOwned ? 0.0 : loanAmount,
    receivableDelta: 0.0,
  );
}

final _originationLoanIdPattern = RegExp(r'^orig_([A-Za-z0-9_-]{8,128})_loan$');

/// The idempotency key a wizard-created Loan was originated with, or null for
/// any other Loan.
String? originationKeyFromLoanId(String loanId) =>
    _originationLoanIdPattern.firstMatch(loanId)?.group(1);

/// Which origination movement a recorded origination Transaction represents.
OriginationMovementKind originationMovementKindOf({
  required TransactionType type,
  required PaymentAllocationType? paymentAllocationType,
}) {
  if (paymentAllocationType == null) {
    return OriginationMovementKind.downPaymentPaid;
  }
  return type == TransactionType.income
      ? OriginationMovementKind.principalReceived
      : OriginationMovementKind.principalSent;
}

final _rupees = NumberFormat('#,##,##0.##', 'en_IN');

/// Indian-grouped rupees without paise when whole ("₹1,50,000"), identical
/// to the web app's `formatOriginationRupees`.
String formatOriginationRupees(double amount) => '₹${_rupees.format(amount)}';

/// Plain-language effect of "Reverse & Delete", shown before confirming.
String originationReversalMessage(
  ({OriginationMovementKind kind, double amount, String accountName})? movement,
) {
  if (movement == null) {
    return 'This will reverse the creation of this agreement and move it to '
        'Trash. No account will change.';
  }
  final amount = formatOriginationRupees(movement.amount);
  return switch (movement.kind) {
    OriginationMovementKind.principalReceived =>
      'This will remove the original $amount received into '
          '${movement.accountName} and reverse the loan creation.',
    OriginationMovementKind.principalSent =>
      'This will restore $amount to ${movement.accountName} and reverse the '
          'amount given.',
    OriginationMovementKind.downPaymentPaid =>
      'This will restore the recorded $amount down payment to '
          '${movement.accountName} and reverse the installment purchase.',
  };
}
