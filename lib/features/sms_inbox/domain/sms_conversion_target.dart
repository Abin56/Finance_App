import 'package:flutter/material.dart';

/// The 11 choices on the "What does this transaction represent?" convert
/// sheet. Every value routes through an *existing* FlowFi screen/sheet and
/// repository — see `SmsConversionRouter` — this enum only carries the
/// beginner-friendly copy shown to the user.
enum SmsConversionTarget {
  myExpense,
  myIncome,
  splitExpense,
  paidForSomeoneElse,
  someonePaidMe,
  loanPayment,
  emiPayment,
  billPayment,
  creditCardPurchase,
  transferBetweenAccounts,
  ignore,
}

extension SmsConversionTargetX on SmsConversionTarget {
  String get label {
    switch (this) {
      case SmsConversionTarget.myExpense:
        return 'My Expense';
      case SmsConversionTarget.myIncome:
        return 'My Income';
      case SmsConversionTarget.splitExpense:
        return 'Split Expense';
      case SmsConversionTarget.paidForSomeoneElse:
        return 'Paid for Someone Else';
      case SmsConversionTarget.someonePaidMe:
        return 'Someone Paid Me';
      case SmsConversionTarget.loanPayment:
        return 'Loan Payment';
      case SmsConversionTarget.emiPayment:
        return 'EMI Payment';
      case SmsConversionTarget.billPayment:
        return 'Bill Payment';
      case SmsConversionTarget.creditCardPurchase:
        return 'Credit Card Purchase';
      case SmsConversionTarget.transferBetweenAccounts:
        return 'Transfer Between My Accounts';
      case SmsConversionTarget.ignore:
        return 'Ignore';
    }
  }

  String get description {
    switch (this) {
      case SmsConversionTarget.myExpense:
        return 'Money I spent on myself';
      case SmsConversionTarget.myIncome:
        return 'Money I earned or received for myself';
      case SmsConversionTarget.splitExpense:
        return 'An expense shared with other people';
      case SmsConversionTarget.paidForSomeoneElse:
        return 'I paid this on someone else\'s behalf';
      case SmsConversionTarget.someonePaidMe:
        return 'Someone paid me back or sent me money';
      case SmsConversionTarget.loanPayment:
        return 'A payment against a loan';
      case SmsConversionTarget.emiPayment:
        return 'A payment against an EMI';
      case SmsConversionTarget.billPayment:
        return 'A payment against a bill';
      case SmsConversionTarget.creditCardPurchase:
        return 'A purchase made on a credit card';
      case SmsConversionTarget.transferBetweenAccounts:
        return 'Money moved between my own accounts';
      case SmsConversionTarget.ignore:
        return 'Not a transaction I want to track';
    }
  }

  IconData get icon {
    switch (this) {
      case SmsConversionTarget.myExpense:
        return Icons.arrow_upward_rounded;
      case SmsConversionTarget.myIncome:
        return Icons.arrow_downward_rounded;
      case SmsConversionTarget.splitExpense:
        return Icons.call_split_rounded;
      case SmsConversionTarget.paidForSomeoneElse:
        return Icons.person_outline_rounded;
      case SmsConversionTarget.someonePaidMe:
        return Icons.call_received_rounded;
      case SmsConversionTarget.loanPayment:
        return Icons.handshake_outlined;
      case SmsConversionTarget.emiPayment:
        return Icons.calendar_month_outlined;
      case SmsConversionTarget.billPayment:
        return Icons.bolt_rounded;
      case SmsConversionTarget.creditCardPurchase:
        return Icons.credit_card_rounded;
      case SmsConversionTarget.transferBetweenAccounts:
        return Icons.swap_horiz_rounded;
      case SmsConversionTarget.ignore:
        return Icons.visibility_off_outlined;
    }
  }
}
