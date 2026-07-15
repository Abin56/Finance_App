/// The kind of financial event a detected SMS appears to describe. Drives
/// which `SmsConversionTarget` is suggested first in the convert sheet and
/// which existing FlowFi category is pre-filled — it never restricts which
/// option the user can actually pick, since the parser is a best guess and
/// the user always has final say (see FEATURE spec: "Never automatically
/// create ... records from SMS").
enum SmsTransactionCategory {
  upiPayment,
  upiReceive,
  bankDebit,
  bankCredit,
  atmWithdrawal,
  cardPurchase,
  creditCardPurchase,
  impsNeftRtgs,
  walletPayment,
  salaryCredit,
  refund,
  cashDeposit,
  loanEmiDebit,
  billPayment,
  autoDebit,
  unknown,
}

extension SmsTransactionCategoryX on SmsTransactionCategory {
  static SmsTransactionCategory fromName(String? name) {
    if (name == null) return SmsTransactionCategory.unknown;
    return SmsTransactionCategory.values.firstWhere(
      (c) => c.name == name,
      orElse: () => SmsTransactionCategory.unknown,
    );
  }

  String get label {
    switch (this) {
      case SmsTransactionCategory.upiPayment:
        return 'UPI payment';
      case SmsTransactionCategory.upiReceive:
        return 'UPI received';
      case SmsTransactionCategory.bankDebit:
        return 'Bank debit';
      case SmsTransactionCategory.bankCredit:
        return 'Bank credit';
      case SmsTransactionCategory.atmWithdrawal:
        return 'ATM withdrawal';
      case SmsTransactionCategory.cardPurchase:
        return 'Card purchase';
      case SmsTransactionCategory.creditCardPurchase:
        return 'Credit card purchase';
      case SmsTransactionCategory.impsNeftRtgs:
        return 'IMPS / NEFT / RTGS';
      case SmsTransactionCategory.walletPayment:
        return 'Wallet payment';
      case SmsTransactionCategory.salaryCredit:
        return 'Salary credit';
      case SmsTransactionCategory.refund:
        return 'Refund';
      case SmsTransactionCategory.cashDeposit:
        return 'Cash deposit';
      case SmsTransactionCategory.loanEmiDebit:
        return 'Loan / EMI debit';
      case SmsTransactionCategory.billPayment:
        return 'Bill payment';
      case SmsTransactionCategory.autoDebit:
        return 'Auto debit';
      case SmsTransactionCategory.unknown:
        return 'Transaction';
    }
  }
}
