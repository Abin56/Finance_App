import '../sms_transaction_category.dart';
import 'financial_event_role.dart';
import 'financial_event_type.dart';
import 'payment_method.dart';

/// The deterministic `SmsTransactionCategory` → [FinancialEventType]/
/// [PaymentMethod]/[FinancialEventRole] mapping used whenever the AI
/// provider abstained (offline, disabled, or the call failed) — see
/// `FinancialEventExtractor`. This is what keeps the pipeline "adequate
/// without AI" (SMS AI rebuild plan §26): coarser than what the AI can
/// infer from free text (it can't distinguish a credit-card *purchase* from
/// a credit-card *bill payment* the way the AI's semantic read can — both
/// fall back to [FinancialEventType.payment] here), but never wrong in a way
/// that would misfile money.
abstract class FinancialEventTypeMapper {
  FinancialEventTypeMapper._();

  static FinancialEventType eventTypeFor(SmsTransactionCategory category) {
    switch (category) {
      case SmsTransactionCategory.upiPayment:
      case SmsTransactionCategory.bankDebit:
      case SmsTransactionCategory.cardPurchase:
      case SmsTransactionCategory.creditCardPurchase:
      case SmsTransactionCategory.walletPayment:
      case SmsTransactionCategory.autoDebit:
        return FinancialEventType.payment;
      case SmsTransactionCategory.billPayment:
        return FinancialEventType.billPayment;
      case SmsTransactionCategory.recharge:
        return FinancialEventType.recharge;
      case SmsTransactionCategory.bankFee:
        return FinancialEventType.fee;
      case SmsTransactionCategory.upiReceive:
      case SmsTransactionCategory.bankCredit:
        return FinancialEventType.receipt;
      case SmsTransactionCategory.salaryCredit:
        return FinancialEventType.salary;
      case SmsTransactionCategory.interestCredit:
        return FinancialEventType.interest;
      case SmsTransactionCategory.cashback:
        return FinancialEventType.cashback;
      case SmsTransactionCategory.impsNeftRtgs:
        return FinancialEventType.transfer;
      case SmsTransactionCategory.refund:
        return FinancialEventType.refund;
      case SmsTransactionCategory.atmWithdrawal:
        return FinancialEventType.cashWithdrawal;
      case SmsTransactionCategory.cashDeposit:
        return FinancialEventType.cashDeposit;
      case SmsTransactionCategory.loanEmiDebit:
        return FinancialEventType.loanEmi;
      case SmsTransactionCategory.unknown:
        return FinancialEventType.unknown;
    }
  }

  static PaymentMethod paymentMethodFor(SmsTransactionCategory category) {
    switch (category) {
      case SmsTransactionCategory.upiPayment:
      case SmsTransactionCategory.upiReceive:
        return PaymentMethod.upi;
      case SmsTransactionCategory.cardPurchase:
        return PaymentMethod.debitCard;
      case SmsTransactionCategory.creditCardPurchase:
        return PaymentMethod.creditCard;
      case SmsTransactionCategory.impsNeftRtgs:
        return PaymentMethod.neftRtgsImps;
      case SmsTransactionCategory.walletPayment:
        return PaymentMethod.wallet;
      case SmsTransactionCategory.atmWithdrawal:
        return PaymentMethod.atm;
      case SmsTransactionCategory.cashDeposit:
        return PaymentMethod.cash;
      case SmsTransactionCategory.bankDebit:
      case SmsTransactionCategory.bankCredit:
      case SmsTransactionCategory.salaryCredit:
      case SmsTransactionCategory.refund:
      case SmsTransactionCategory.loanEmiDebit:
      case SmsTransactionCategory.billPayment:
      case SmsTransactionCategory.autoDebit:
      case SmsTransactionCategory.cashback:
      case SmsTransactionCategory.interestCredit:
      case SmsTransactionCategory.bankFee:
      case SmsTransactionCategory.recharge:
      case SmsTransactionCategory.unknown:
        return PaymentMethod.unknown;
    }
  }

  /// Only [SmsTransactionCategory.creditCardPurchase] is confidently a
  /// [FinancialEventRole.originalCharge] without the AI's semantic read —
  /// everything else defaults to [FinancialEventRole.standalone], letting
  /// the AI (when available) upgrade it to `originalCharge`/`linkedSettlement`
  /// via its own `role` field.
  static FinancialEventRole roleFor(SmsTransactionCategory category) {
    if (category == SmsTransactionCategory.creditCardPurchase)
      return FinancialEventRole.originalCharge;
    return FinancialEventRole.standalone;
  }
}
