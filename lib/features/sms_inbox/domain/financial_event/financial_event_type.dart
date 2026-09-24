/// The reconciled real-world event a [FinancialEvent] describes — distinct
/// from `SmsTransactionCategory` (the parser's own coarse guess, still used
/// as regex evidence feeding into reconciliation, see
/// `financial_event_type_mapper.dart`). This is the verdict *after* combining
/// regex evidence with the AI's structured read of the message.
enum FinancialEventType {
  payment,
  receipt,
  transfer,
  refund,
  reversal,

  /// A charge *to* a credit card (money spent) — distinct from
  /// [creditCardBill] (money paid *toward* the card's balance). See
  /// `CreditCardSemantics`.
  creditCardPurchase,
  creditCardBill,
  loanEmi,
  cashWithdrawal,
  cashDeposit,
  cashback,
  salary,
  interest,
  fee,
  recharge,
  billPayment,

  /// An upcoming obligation, not money that has already moved — see
  /// [ReminderDetector]/`FinancialEvent.moneyMovement`. Always paired with
  /// `moneyMovement.value == false`.
  reminder,

  unknown,
}

extension FinancialEventTypeX on FinancialEventType {
  static FinancialEventType fromName(String? name) {
    if (name == null) return FinancialEventType.unknown;
    return FinancialEventType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => FinancialEventType.unknown,
    );
  }

  String get label {
    switch (this) {
      case FinancialEventType.payment:
        return 'Payment';
      case FinancialEventType.receipt:
        return 'Money received';
      case FinancialEventType.transfer:
        return 'Transfer';
      case FinancialEventType.refund:
        return 'Refund';
      case FinancialEventType.reversal:
        return 'Reversal';
      case FinancialEventType.creditCardPurchase:
        return 'Credit card purchase';
      case FinancialEventType.creditCardBill:
        return 'Credit card bill payment';
      case FinancialEventType.loanEmi:
        return 'Loan / EMI';
      case FinancialEventType.cashWithdrawal:
        return 'Cash withdrawal';
      case FinancialEventType.cashDeposit:
        return 'Cash deposit';
      case FinancialEventType.cashback:
        return 'Cashback';
      case FinancialEventType.salary:
        return 'Salary';
      case FinancialEventType.interest:
        return 'Interest';
      case FinancialEventType.fee:
        return 'Bank fee';
      case FinancialEventType.recharge:
        return 'Recharge';
      case FinancialEventType.billPayment:
        return 'Bill payment';
      case FinancialEventType.reminder:
        return 'Payment reminder';
      case FinancialEventType.unknown:
        return 'Transaction';
    }
  }
}
