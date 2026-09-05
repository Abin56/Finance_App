/// Which underlying source a [MoneyFlowLine] came from — surfaced in the
/// Money In/Out detail screens so a mixed list (e.g. Money Out combining
/// expense transactions with EMI/Loan/Bill payments) still reads as
/// distinct rows, not a single undifferentiated list.
enum MoneyFlowKind { income, expense, moneyReceived, emi, loan, bill }

extension MoneyFlowKindX on MoneyFlowKind {
  String get label {
    switch (this) {
      case MoneyFlowKind.income:
        return 'Income';
      case MoneyFlowKind.expense:
        return 'Expense';
      case MoneyFlowKind.moneyReceived:
        return 'Money Received';
      case MoneyFlowKind.emi:
        return 'EMI';
      case MoneyFlowKind.loan:
        return 'Loan';
      case MoneyFlowKind.bill:
        return 'Bill';
    }
  }
}

/// One contributing row behind a Money In/Out total — the same shape for
/// every source (a plain income/expense transaction, a split-expense
/// settlement, an EMI/Loan installment payment, or a bill payment) so the
/// detail screen can render a single sorted list regardless of where each
/// line actually came from. Never a new calculation of its own: every field
/// here is read from whichever provider already computes that source's
/// contribution to [cashFlowForRangeProvider], so the detail list's total
/// always equals the summary figure by construction, not by coincidence.
typedef MoneyFlowLine = ({
  MoneyFlowKind kind,
  DateTime date,
  String title,
  double amount,
  String? categoryLabel,
  String? accountLabel,
});

/// One personal-expense transaction contributing to "My Expenses" — always
/// [MyExpenseLine.myShare] of the underlying [Expense]/[Transaction], never
/// the full transaction amount, so a shared expense's line always reads as
/// only the current user's portion. [categoryId] (rather than a resolved
/// label) is kept on the line itself so category grouping/drill-down can key
/// off it directly without re-joining every consumer against the categories
/// stream.
typedef MyExpenseLine = ({
  String transactionId,
  DateTime date,
  String title,
  double myShare,
  double? totalAmount,
  bool isSplit,
  String categoryId,
  String? categoryLabel,
  String? accountLabel,
  String notes,
});
