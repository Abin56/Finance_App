/// Plain per-installment amount + optional principal/interest split,
/// supplied by a caller (e.g. Lending's `LoanRepository`, after running
/// `InterestCalculator`) that has already computed exact figures — keeps
/// `InstallmentRepository` ignorant of *why* the amounts are what they are.
class PrecomputedInstallmentAmount {
  const PrecomputedInstallmentAmount({
    required this.amountDue,
    this.principalPortion,
    this.interestPortion,
  });

  final double amountDue;
  final double? principalPortion;
  final double? interestPortion;
}
