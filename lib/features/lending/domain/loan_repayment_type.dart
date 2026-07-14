/// How a [Loan] is repaid — chosen at creation, immutable thereafter (see
/// [Loan.repaymentType]).
enum LoanRepaymentType { oneTime, installment }

extension LoanRepaymentTypeX on LoanRepaymentType {
  static LoanRepaymentType fromName(String name) =>
      LoanRepaymentType.values.firstWhere((t) => t.name == name, orElse: () => LoanRepaymentType.oneTime);

  String get label => this == LoanRepaymentType.oneTime ? 'One-time repayment' : 'Monthly Payments (EMI)';
}
