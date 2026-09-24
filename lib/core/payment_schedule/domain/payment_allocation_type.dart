/// Classifies *why* a payment was recorded — computed at record time from
/// the actual amount/date against the schedule, never chosen by the user
/// directly. See `LoanAdvancePaymentRepository.record`'s doc comment for the
/// exact classification rule.
enum PaymentAllocationType {
  /// Amount == what's owed on the currently-due installment(s), paid on/
  /// after the earliest one's due date. No principal change beyond the
  /// normal schedule.
  regularEmi,

  /// Same as [regularEmi] but paid before the earliest touched
  /// installment's due date.
  advanceEmi,

  /// The payment exceeds every installment offered for allocation — the
  /// excess is banked as a principal reduction and (when solvable) triggers
  /// re-amortization of the untouched tail. See
  /// `PrepaymentReamortizationPolicy`.
  principalPrepayment,

  /// A manual increase to the loan/EMI's principal, not a payment at all —
  /// reserved for the future "Additional Disbursement" action; not
  /// produced by `LoanAdvancePaymentRepository.record`.
  additionalDisbursement,
}

extension PaymentAllocationTypeX on PaymentAllocationType {
  /// Old `InstallmentPayment` documents predate this field — absent always
  /// means an ordinary payment, never a prepayment/disbursement, since
  /// those concepts didn't exist yet when such a document was written.
  static PaymentAllocationType fromName(String? name) =>
      PaymentAllocationType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => PaymentAllocationType.regularEmi,
      );
}
