/// One period's (installment's) split of a payment into principal vs
/// interest, plus the outstanding principal after this period is applied.
/// Purely a value object — never persisted directly; a caller (e.g.
/// Lending's `LoanRepository`) copies the relevant fields onto its own
/// persisted records (`Installment.principalPortion`/`interestPortion`).
class InterestPeriodBreakdown {
  const InterestPeriodBreakdown({
    required this.periodNumber,
    required this.paymentAmount,
    required this.principalPortion,
    required this.interestPortion,
    required this.remainingPrincipal,
  });

  /// 1-based.
  final int periodNumber;

  /// principalPortion + interestPortion, rounded.
  final double paymentAmount;
  final double principalPortion;
  final double interestPortion;

  /// Outstanding principal after this period's principalPortion is applied.
  final double remainingPrincipal;
}

/// Full amortization result for a [principal] repaid over
/// `periods.length` installments (a single entry for a one-time repayment).
class InterestBreakdown {
  const InterestBreakdown({
    required this.principal,
    required this.totalInterest,
    required this.periods,
  });

  final double principal;
  final double totalInterest;
  final List<InterestPeriodBreakdown> periods;

  double get totalPayable => principal + totalInterest;
}
