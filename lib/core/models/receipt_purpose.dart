/// What kind of target a [ReceiptPurpose] settles against — determines
/// which optional reference `ReceiptClassificationRouter.classify` requires
/// (a person, a loan/EMI installment, or a savings goal), independent of
/// the purpose's plain-language label. Purposes that don't settle anything
/// beyond "money arrived in an account" use [none].
enum ReceiptTargetKind { person, loanInstallment, emiInstallment, savingsGoal, splitExpenseParticipant, none }

/// Why money was received — shown to the user in plain language (per this
/// app's Plain Language UX Rule) and used by `ReceiptClassificationRouter`
/// to decide which existing module(s) to update. Adding a new purpose here
/// is the only change needed to teach the whole app about it; no feature
/// should hand-roll its own "why did I get this money" picker.
enum ReceiptPurpose {
  loanRepayment,
  emiPayment,
  advanceEmiPayment,
  savingsDeposit,
  walletDeposit,
  personalLoanReceived,
  friendReturnedMoney,
  splitExpenseSettlement,
  gift,
  salary,
  refund,
  cashback,
  investmentReturn,
  interestReceived,
  tip,
  other,
}

extension ReceiptPurposeX on ReceiptPurpose {
  static ReceiptPurpose fromName(String name) =>
      ReceiptPurpose.values.firstWhere((p) => p.name == name, orElse: () => ReceiptPurpose.other);

  String get label {
    switch (this) {
      case ReceiptPurpose.loanRepayment:
        return 'Loan payment';
      case ReceiptPurpose.emiPayment:
        return 'Monthly EMI payment';
      case ReceiptPurpose.advanceEmiPayment:
        return 'Monthly EMI paid early';
      case ReceiptPurpose.savingsDeposit:
        return 'Savings deposit';
      case ReceiptPurpose.walletDeposit:
        return 'Wallet deposit';
      case ReceiptPurpose.personalLoanReceived:
        return 'Personal loan received';
      case ReceiptPurpose.friendReturnedMoney:
        return 'Friend returned money';
      case ReceiptPurpose.splitExpenseSettlement:
        return 'Shared expense paid';
      case ReceiptPurpose.gift:
        return 'Gift';
      case ReceiptPurpose.salary:
        return 'Salary';
      case ReceiptPurpose.refund:
        return 'Refund';
      case ReceiptPurpose.cashback:
        return 'Cashback';
      case ReceiptPurpose.investmentReturn:
        return 'Investment return';
      case ReceiptPurpose.interestReceived:
        return 'Interest received';
      case ReceiptPurpose.tip:
        return 'Tip';
      case ReceiptPurpose.other:
        return 'Other';
    }
  }

  /// Which optional target reference this purpose needs — see
  /// [ReceiptTargetKind].
  ReceiptTargetKind get targetKind {
    switch (this) {
      case ReceiptPurpose.loanRepayment:
        return ReceiptTargetKind.loanInstallment;
      case ReceiptPurpose.emiPayment:
      case ReceiptPurpose.advanceEmiPayment:
        return ReceiptTargetKind.emiInstallment;
      case ReceiptPurpose.savingsDeposit:
        return ReceiptTargetKind.savingsGoal;
      case ReceiptPurpose.friendReturnedMoney:
        return ReceiptTargetKind.person;
      case ReceiptPurpose.splitExpenseSettlement:
        return ReceiptTargetKind.splitExpenseParticipant;
      case ReceiptPurpose.walletDeposit:
      case ReceiptPurpose.personalLoanReceived:
      case ReceiptPurpose.gift:
      case ReceiptPurpose.salary:
      case ReceiptPurpose.refund:
      case ReceiptPurpose.cashback:
      case ReceiptPurpose.investmentReturn:
      case ReceiptPurpose.interestReceived:
      case ReceiptPurpose.tip:
      case ReceiptPurpose.other:
        return ReceiptTargetKind.none;
    }
  }
}
