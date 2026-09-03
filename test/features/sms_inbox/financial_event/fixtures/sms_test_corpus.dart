import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';

import 'sms_test_case.dart';

/// A large, structured corpus of real-world-shaped SMS messages used to
/// evaluate FlowFi's SMS financial-classification pipeline end to end
/// (candidate filter -> parser -> [FinancialEventExtractor]) for *semantic*
/// understanding rather than mere regex/template matching.
///
/// Organized into sections; each section's cases are appended to
/// [smsTestCorpus]. Add new cases to the relevant section (or a new one)
/// rather than creating parallel corpora — the evaluation harness
/// (`sms_evaluation_harness.dart`) and its test
/// (`sms_corpus_evaluation_test.dart`) iterate this single list.
final List<SmsTestCase> smsTestCorpus = [
  ..._realDebits,
  ..._realCredits,
  ..._reminders,
  ..._failedOrPending,
  ..._refundsAndReversals,
  ..._cashbackSalaryInterestFee,
  ..._loanAndCreditCard,
  ..._rechargeAndBills,
  ..._ownAccountTransfers,
  ..._upiAppVariety,
  ..._formattingVariety,
  ..._merchantAndVpaEdgeCases,
  ..._nonFinancialNoise,
  ..._dangerousFalsePositiveTraps,
  ..._duplicateAndLinkingSeeds,
  ..._merchantVariations,
  ..._paymentProviderVsMerchant,
  ..._categoryVariations,
  ..._creditCardSemanticsExpanded,
  ..._reminderSafetyExpanded,
  ..._failedPendingExpanded,
  ..._reversalRefundExpanded,
  ..._unknownMerchantSafety,
  ..._merchantFromXExtraction,
  ..._providerWithoutMerchant,
  ..._providerVsCategoryAdversarial,
  ..._normalizationPreservesContext,
  ..._statusCombinations,
  ..._phase5RealisticCorpus,
];

/// Ids evaluated by the category-testing bespoke group in
/// `sms_corpus_evaluation_test.dart` (needs a real `categories` list + a
/// `CategoryResolver`-equipped extractor to mean anything — the generic
/// sweep runs with `categories: const []` and no category resolver at all).
final List<String> categoryVariationIds = [
  ..._categoryVariations.map((c) => c.id),
  ..._providerVsCategoryAndNormalizationCategoryIds,
];

// ---------------------------------------------------------------------------
// 1. Real, completed debits — the baseline: must always register as money
//    movement with the correct amount and direction.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _realDebits = [
  const SmsTestCase(
    id: 'debit-upi-swiggy-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs 500.00 debited from a/c XX1234 for UPI/Swiggy/1234567890 on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldPassFilter: true,
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      amount: 500.0,
    ),
    explanation:
        'Canonical completed UPI debit — must never be missed. transactionStatus is '
        'intentionally not asserted: plain "debited from" wording (as opposed to '
        '"was debited"/"successfully") has no explicit status keyword, which '
        'TransactionStatusSignals correctly reads as unknown rather than a forced guess.',
  ),
  const SmsTestCase(
    id: 'debit-plain-purchase-01',
    sender: 'AD-ICICIB',
    body: 'Your account has been debited by INR 1,250.75 towards a purchase.',
    expected: ExpectedFinancialClassification(
      shouldPassFilter: true,
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      amount: 1250.75,
    ),
    explanation: 'INR-prefixed amount with comma+decimal must parse correctly.',
  ),
  const SmsTestCase(
    id: 'debit-natural-language-01',
    sender: 'VK-AXISBK',
    body: 'You have paid Rs.500 to a merchant via UPI. Ref no 456789123456.',
    expected: ExpectedFinancialClassification(
      shouldPassFilter: true,
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      amount: 500.0,
    ),
    explanation:
        '"paid ... to" is semantically a debit even without the word "debited".',
  ),
  const SmsTestCase(
    id: 'debit-vpa-sent-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.350 sent to 9876543210@oksbi via UPI from A/c XX5678.',
    expected: ExpectedFinancialClassification(
      shouldPassFilter: true,
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      amount: 350.0,
    ),
    explanation:
        '"sent to <vpa>" phrasing, common from UPI apps rather than bank templates.',
  ),
];

// ---------------------------------------------------------------------------
// 2. Real, completed credits.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _realCredits = [
  const SmsTestCase(
    id: 'credit-plain-01',
    sender: 'VM-HDFCBK',
    body: '₹500 credited to your account XX1234 on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldPassFilter: true,
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.credit,
      amount: 500.0,
    ),
    explanation: 'Canonical completed credit.',
  ),
  const SmsTestCase(
    id: 'credit-received-01',
    sender: 'VK-KOTAKB',
    body: 'Amount of ₹500 received in your account from a friend via UPI.',
    expected: ExpectedFinancialClassification(
      shouldPassFilter: true,
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.credit,
      amount: 500.0,
    ),
    explanation: '"received in your account" is semantically a credit.',
  ),
];

// ---------------------------------------------------------------------------
// 3. Reminders — never a transaction, even when phrased with a completed-
//    transaction verb and a valid amount. The single most important category
//    for catching false positives.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _reminders = [
  const SmsTestCase(
    id: 'reminder-emi-due-01',
    sender: 'VM-HDFCBK',
    body: 'Your EMI of Rs.8,500 is due tomorrow.',
    expected: ExpectedFinancialClassification(
      moneyMovement: false,
      eventType: FinancialEventType.reminder,
    ),
    explanation: 'Plain future-due-date reminder, no ambiguous verb.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-will-be-debited-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.8,500 will be debited towards your EMI tomorrow.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      eventType: FinancialEventType.reminder,
    ),
    explanation:
        'Contains "debited" (the word a naive regex-only pipeline would treat as a completed debit) but is future-tense — the exact false-positive case this system exists to catch.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-payment-due-01',
    sender: 'VK-AXISBK',
    body:
        'Your payment of Rs.8,500 is due tomorrow. Kindly pay to avoid late fee.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation:
        '"is due" + imperative "kindly pay" must never register as spent.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-bill-due-01',
    sender: 'VM-SBIBNK',
    body:
        'Your bill of Rs.2,000 is due tomorrow. Please pay before the due date.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation: 'A bill reminder is not a bill payment.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-credit-card-due-01',
    sender: 'VK-ICICIB',
    body:
        'Your credit card bill of Rs.15,430 is due on 20-07-26. Minimum due Rs.1,500.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation:
        'Credit card bill reminder with a "minimum due" figure must not be read as a payment.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-autopay-upcoming-01',
    sender: 'VM-HDFCBK',
    body:
        'Reminder: Your auto-debit of Rs.999 for Netflix will be processed on 18-07-26. Ensure sufficient balance.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation:
        'Upcoming auto-debit notice, not a completed one — "will be processed" is future tense.',
    isDangerousIfMisclassified: true,
  ),
];

// ---------------------------------------------------------------------------
// 4. Failed / pending — described money movement that did not actually
//    complete.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _failedOrPending = [
  const SmsTestCase(
    id: 'failed-insufficient-balance-01',
    sender: 'VM-HDFCBK',
    body: 'Your payment of Rs.8,500 failed due to insufficient balance.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: 'A failed transaction never implies money moved.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-upi-retry-01',
    sender: 'VK-PAYTM',
    body: 'UPI payment of Rs.500 has failed. Please try again.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation:
        'Failed UPI attempt via a wallet/app sender rather than a bank.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'pending-confirmation-01',
    sender: 'VM-SBIBNK',
    body: 'Your payment of Rs.500 is pending confirmation from the bank.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.pending,
    ),
    explanation: 'Pending is not completed — must not be treated as spent yet.',
    isDangerousIfMisclassified: true,
  ),
];

// ---------------------------------------------------------------------------
// 5. Refunds and reversals — real (inverse) money movements in their own
//    right, must not be conflated with a reminder or suppressed.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _refundsAndReversals = [
  const SmsTestCase(
    id: 'refund-swiggy-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 refunded to your account by Swiggy.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.refund,
    ),
    explanation:
        'A refund is a genuine inverse money movement — must count as true.',
  ),
  const SmsTestCase(
    id: 'reversal-failed-debit-01',
    sender: 'VK-AXISBK',
    body: 'Rs.500 debited on 10-Jul has been reversed to your account XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
    ),
    explanation:
        'A reversal is real money movement (money came back), not a no-op.',
  ),
];

// ---------------------------------------------------------------------------
// 6. Cashback, salary, interest, fee.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _cashbackSalaryInterestFee = [
  const SmsTestCase(
    id: 'cashback-01',
    sender: 'VK-PAYTM',
    body: 'Rs.25 cashback credited to your account for your recent purchase.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.cashback,
      moneyMovement: true,
    ),
    explanation: 'Cashback is a real, if small, credit.',
  ),
  const SmsTestCase(
    id: 'salary-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs.50,000.00 credited to a/c XX1234 via NEFT. Info: SALARY for July.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.salary,
      moneyMovement: true,
      direction: SmsTransactionDirection.credit,
    ),
    explanation: 'Large NEFT credit with SALARY narration.',
  ),
  const SmsTestCase(
    id: 'interest-01',
    sender: 'VM-SBIBNK',
    body: 'Interest of Rs.145.32 credited to your savings account for Q2.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.interest,
      moneyMovement: true,
    ),
    explanation: 'Quarterly interest credit.',
  ),
  const SmsTestCase(
    id: 'fee-annual-01',
    sender: 'VK-ICICIB',
    body:
        'Rs.500 annual fee has been debited from your credit card ending 1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.fee,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
    ),
    explanation:
        'Annual card fee is a real debit, not a reminder despite being a recurring charge.',
  ),
];

// ---------------------------------------------------------------------------
// 7. Loan EMI (actually debited) and credit-card purchase/bill payment.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _loanAndCreditCard = [
  const SmsTestCase(
    id: 'loan-emi-debited-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.8,500 debited towards your loan EMI on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.loanEmi,
      moneyMovement: true,
    ),
    explanation:
        'A completed EMI debit — contrast with reminder-emi-due-01/reminder-will-be-debited-01, same amount, opposite verdict.',
  ),
  const SmsTestCase(
    id: 'credit-card-purchase-01',
    sender: 'VK-ICICIB',
    body: 'Your credit card ending 4821 was charged Rs.2,500 at a merchant.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardPurchase,
      paymentMethod: PaymentMethod.creditCard,
      moneyMovement: true,
    ),
    explanation:
        'FIXED (Phase 3): CreditCardSemantics deterministically resolves a charge '
        '*to* the card as creditCardPurchase — previously the coarse mapper only '
        'had a generic `payment` type here.',
  ),
  const SmsTestCase(
    id: 'credit-card-bill-payment-01',
    sender: 'VM-HDFCBK',
    body: 'Credit card payment of Rs.5,000 received. Thank you.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardBill,
      moneyMovement: true,
    ),
    explanation:
        'FIXED (Phase 3): the Phase 2 limitation this case was tracking is now closed — '
        'CreditCardSemantics distinguishes "payment ... received" (paid *toward* the '
        'card) from credit-card-purchase-01\'s "was charged" (money spent *on* the '
        'card) without needing AI.',
  ),
];

// ---------------------------------------------------------------------------
// 8. Recharge and bill payment (completed).
// ---------------------------------------------------------------------------
final List<SmsTestCase> _rechargeAndBills = [
  const SmsTestCase(
    id: 'recharge-01',
    sender: 'VK-JIOIO',
    body: 'Rs.199 debited for mobile recharge on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.recharge,
      moneyMovement: true,
    ),
    explanation: 'Completed recharge debit.',
  ),
  const SmsTestCase(
    id: 'bill-payment-completed-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.2,000 bill payment successful for your electricity connection.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.billPayment,
      moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    explanation: 'Completed utility bill payment.',
  ),
];

// ---------------------------------------------------------------------------
// 9. Transfers between the user's own accounts — must be flagged, but only
//    when the destination last-4 genuinely matches a known account/card.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _ownAccountTransfers = [
  const SmsTestCase(
    id: 'own-account-transfer-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.5,000 transferred to A/c 9876 via NEFT from a/c XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      isOwnAccountTransfer: true,
      eventType: FinancialEventType.transfer,
      categoryIsNull: true,
    ),
    explanation:
        'PHASE 5 (Part 7): destination last-4 (9876) must be checked by the harness against a matcher configured with that account — see sms_evaluation_harness usage. A confirmed own-account transfer must resolve to eventType.transfer (never a generic payment/receipt) and get no spending category at all — it is neither an expense nor income.',
  ),
  const SmsTestCase(
    id: 'external-transfer-not-own-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.5,000 transferred to A/c 4321 via NEFT from a/c XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      isOwnAccountTransfer: false,
    ),
    explanation:
        'Destination last-4 does not belong to any of the user\'s accounts — must not be flagged as own-account.',
  ),
];

// ---------------------------------------------------------------------------
// 10. UPI app variety — PhonePe/GPay/Paytm-style sender IDs and phrasing,
//     since production traffic isn't only bank-template SMS.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _upiAppVariety = [
  const SmsTestCase(
    id: 'upi-app-phonepe-01',
    sender: 'VM-PHONPE',
    body: 'Payment of Rs.240 to Zomato was successful. UPI Ref 998877665544.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      amount: 240.0,
    ),
    explanation:
        'App-originated confirmation SMS rather than a bank debit template.',
  ),
  const SmsTestCase(
    id: 'upi-app-gpay-01',
    sender: 'AD-GOOGLP',
    body: 'You paid Rs.120 to Rohit Kumar using Google Pay.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      amount: 120.0,
    ),
    explanation:
        'Peer-to-peer payment via a UPI app, addressed to a person\'s name rather than a business.',
  ),
];

// ---------------------------------------------------------------------------
// 11. Formatting variety — currency notation, separators, decimals.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _formattingVariety = [
  const SmsTestCase(
    id: 'format-inr-prefix-01',
    sender: 'VM-HDFCBK',
    body: 'INR 500 debited from your account for UPI payment to Swiggy.',
    expected: ExpectedFinancialClassification(shouldParse: true, amount: 500.0),
    explanation: 'INR prefix instead of Rs./₹.',
  ),
  const SmsTestCase(
    id: 'format-symbol-prefix-01',
    sender: 'VM-HDFCBK',
    body: 'UPI payment of ₹500 to ABC completed.',
    expected: ExpectedFinancialClassification(shouldParse: true, amount: 500.0),
    explanation: '₹ unicode symbol.',
  ),
  const SmsTestCase(
    id: 'format-large-comma-decimal-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,23,456.78 debited from a/c XX1234 towards a purchase.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      amount: 123456.78,
    ),
    explanation: 'Indian-style lakh comma grouping with decimal paise.',
  ),
  const SmsTestCase(
    id: 'format-multiple-amounts-balance-vs-debit-01',
    sender: 'VM-HDFCBK',
    body:
        'Avl Bal Rs.45,230.00. Rs.500.00 debited from a/c XX1234 on 15-07-26.',
    expected: ExpectedFinancialClassification(shouldParse: true, amount: 500.0),
    explanation:
        'The transacted amount must win over the (much larger) balance figure.',
    isDangerousIfMisclassified: true,
  ),
];

// ---------------------------------------------------------------------------
// 12. Merchant/VPA resolution edge cases — must never invent a name.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _merchantAndVpaEdgeCases = [
  const SmsTestCase(
    id: 'merchant-missing-not-invented-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantIsNull: true,
    ),
    explanation:
        'No merchant/payee text present at all — must stay unresolved rather than guessed.',
  ),
  const SmsTestCase(
    id: 'merchant-unknown-vpa-stays-vpa-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.350 sent to 9876543210@oksbi via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: '9876543210@oksbi',
    ),
    explanation:
        'An unrecognized VPA must remain the raw VPA string, never inflated into an invented business name.',
  ),
  const SmsTestCase(
    id: 'merchant-reference-not-mistaken-for-merchant-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 to Swiggy on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantContains: 'Swiggy',
      referenceNumberIsNull: true,
    ),
    explanation:
        'Missing reference number must not prevent classification, and must not be confused with the merchant.',
  ),
];

// ---------------------------------------------------------------------------
// 13. Non-financial noise — must be rejected before parsing/AI, never
//     produce a FinancialEvent at all.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _nonFinancialNoise = [
  const SmsTestCase(
    id: 'noise-otp-01',
    sender: 'VM-HDFCBK',
    body: 'Your OTP for login is 482913. Do not share with anyone.',
    expected: ExpectedFinancialClassification(shouldPassFilter: false),
    explanation: 'OTP messages must never enter the financial pipeline.',
  ),
  const SmsTestCase(
    id: 'noise-promo-discount-01',
    sender: 'AD-SHOPZY',
    body: 'Flat 50% off on your next order! Shop now.',
    expected: ExpectedFinancialClassification(shouldPassFilter: false),
    explanation:
        'Promotional discount SMS with no actual amount tied to the user\'s account.',
  ),
  const SmsTestCase(
    id: 'noise-shipping-01',
    sender: 'AD-AMAZON',
    body: 'Your order has been shipped and is out for delivery.',
    expected: ExpectedFinancialClassification(shouldPassFilter: false),
    explanation: 'Logistics notification, no money movement language.',
  ),
  const SmsTestCase(
    id: 'noise-promo-cashback-offer-01',
    sender: 'VK-PAYTM',
    body: 'Recharge now and get cashback offers on your next recharge!',
    expected: ExpectedFinancialClassification(shouldPassFilter: false),
    explanation:
        'Contains "cashback" and "recharge" — words that legitimately appear in real transaction SMS elsewhere in this corpus (see cashback-01, recharge-01) — but this is a marketing offer with no amount debited/credited to the user, and must be filtered out despite the keyword overlap.',
  ),
  const SmsTestCase(
    id: 'noise-promo-amount-mentioned-01',
    sender: 'AD-BIGBZR',
    body: 'Get Rs.500 off on purchases above Rs.2000 this weekend only!',
    expected: ExpectedFinancialClassification(shouldPassFilter: false),
    explanation:
        'FIXED: a bare-rupee-amount "off" pattern was missing from '
        '`SmsFinancialFilter._softNonFinancialPatterns` (only "% off" and '
        '"sale...shop/buy/store" were covered) — this corpus case caught it. Added '
        'r\'(rs|inr|₹)\\.?\\s?[\\d,]+\\s*off\\b\' to close the gap; this promo is now '
        'correctly rejected by the candidate filter before ever reaching a parser.',
  ),
];

// ---------------------------------------------------------------------------
// 14. Dangerous false-positive traps — deliberately adversarial phrasing
//     designed to fool a naive keyword/regex-only classifier. Every case
//     here is marked isDangerousIfMisclassified.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _dangerousFalsePositiveTraps = [
  const SmsTestCase(
    id: 'trap-conditional-debit-01',
    sender: 'VM-HDFCBK',
    body: 'If you do not pay Rs.8,500 by 20-07-26, a late fee will be debited.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation:
        'Conditional/future debit contingent on non-payment — nothing has moved yet.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'trap-standing-instruction-notice-01',
    sender: 'VM-ICICIB',
    body:
        'As per your standing instruction, Rs.3,000 will be debited from a/c XX1234 on 01-08-26 for SIP.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation:
        'A standing-instruction pre-notice for a future date, not a completed SIP debit.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'trap-request-not-payment-01',
    sender: 'VK-PAYTM',
    body:
        'Rohit Kumar has requested Rs.500 from you via UPI. Approve in the app to pay.',
    expected: ExpectedFinancialClassification(moneyMovement: false),
    explanation:
        'A collect/payment *request* mentions an amount and a payer/payee but nothing has been paid until the user approves it — must not be treated as a completed debit.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'trap-reversed-but-original-still-shown-01',
    sender: 'VM-SBIBNK',
    body:
        'Rs.500 debited from a/c XX1234 on 14-07-26 towards POS purchase which was later declined and reversed same day.',
    expected: ExpectedFinancialClassification(shouldParse: true),
    explanation:
        'A single message narrating both a debit and its same-day reversal — net effect is no real spend; harness only checks parseability here since the correct net-amount resolution across the compound sentence is a known hard case, not asserted strictly.',
  ),
];

// ---------------------------------------------------------------------------
// 15. Duplicate / linking seeds — pairs of messages sharing a reference
//     number or sender+amount+time window, intended to be run together with
//     TransactionMatcher (see sms_evaluation_harness.dart) rather than only
//     through the extractor. Kept here so the corpus is the single source of
//     truth for "what a matching real-world SMS pair looks like."
// ---------------------------------------------------------------------------
final List<SmsTestCase> _duplicateAndLinkingSeeds = [
  const SmsTestCase(
    id: 'dup-same-reference-01a',
    sender: 'VM-HDFCBK',
    body:
        'Rs.500 debited from a/c XX1234 for UPI/Amazon/RRN445566778899 on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      amount: 500.0,
    ),
    explanation:
        'First half of a duplicate-detection pair — same reference number as dup-same-reference-01b, same amount, must resolve to the same underlying event when matched via TransactionMatcher.',
  ),
  const SmsTestCase(
    id: 'dup-same-reference-01b',
    sender: 'VM-HDFCBK',
    body: 'Payment of Rs.500 via UPI RRN445566778899 to Amazon successful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      amount: 500.0,
    ),
    explanation:
        'Second, app-style confirmation of the same underlying transaction as dup-same-reference-01a (shared RRN) — a naive pipeline would double-count this as a second spend.',
  ),
];

// ---------------------------------------------------------------------------
// 16. Merchant variations — the same underlying question ("who was paid")
//     phrased/formatted a dozen different real-world ways. Never invents an
//     identity when the evidence is genuinely absent.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _merchantVariations = [
  const SmsTestCase(
    id: 'merchant-var-explicit-narration-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.450 debited from a/c XX1234 to Zomato on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Zomato',
      merchantType: MerchantType.business,
    ),
    explanation: 'Merchant name explicitly stated in bank narration.',
  ),
  const SmsTestCase(
    id: 'merchant-var-vpa-01',
    sender: 'VM-ICICIB',
    body: 'Rs.850 paid to swiggy@icici via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Swiggy',
      merchantType: MerchantType.business,
      paymentProviderIsNull: true,
    ),
    explanation:
        'Merchant name only present inside the VPA local part — must resolve via the catalog and upgrade to the canonical spelling, not stay as the raw VPA string.',
  ),
  const SmsTestCase(
    id: 'merchant-var-narration-context-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.320 spent at ABC Bakery on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'ABC Bakery',
      merchantTypeIsNull: true,
    ),
    explanation:
        'A human-shaped name not in the catalog is kept as explicit text (never discarded), but its type is honestly left unresolved rather than guessed as "business".',
  ),
  const SmsTestCase(
    id: 'merchant-var-uppercase-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,200 debited from a/c XX1234 to AMAZON on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Amazon',
      merchantType: MerchantType.business,
    ),
    explanation:
        'All-caps merchant text must still resolve to the catalog\'s canonical "Amazon" spelling.',
  ),
  const SmsTestCase(
    id: 'merchant-var-lowercase-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.640 debited from a/c XX1234 to amazon on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Amazon',
      merchantType: MerchantType.business,
    ),
    explanation:
        'Lowercase merchant text, same catalog-normalization outcome as the uppercase case.',
  ),
  const SmsTestCase(
    id: 'merchant-var-punctuation-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.600 debited from a/c XX1234 to Amazon.in on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Amazon',
      merchantType: MerchantType.business,
    ),
    explanation:
        'Merchant text with punctuation ("Amazon.in") — a registered catalog alias.',
  ),
  const SmsTestCase(
    id: 'merchant-var-legal-suffix-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.780 debited from a/c XX1234 to Avenue Supermarts on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'DMart',
      merchantType: MerchantType.business,
    ),
    explanation:
        'A merchant\'s registered/legal name ("Avenue Supermarts", DMart\'s parent company) resolves to the same catalog entry as its brand name.',
  ),
  const SmsTestCase(
    id: 'merchant-var-provider-plus-merchant-01',
    sender: 'VM-ICICIB',
    body: 'Rs.850 paid to swiggy@icici using PhonePe via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Swiggy',
      merchantType: MerchantType.business,
      paymentProvider: PaymentProvider.phonePe,
    ),
    explanation:
        'Merchant name and payment provider both present — must resolve as two separate fields, never conflated.',
  ),
  const SmsTestCase(
    id: 'merchant-var-unknown-vpa-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.900 transferred to abc123@oksbi via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'abc123@oksbi',
      merchantTypeIsNull: true,
    ),
    explanation:
        'An uncatalogued VPA must remain the raw VPA string, never inflated into an invented business name — the "@oksbi" handle is still a weak provider hint (see PaymentProviderResolver), independent of merchant identity.',
  ),
  const SmsTestCase(
    id: 'merchant-var-ambiguous-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 to XX9876 on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'XX9876',
      merchantTypeIsNull: true,
      paymentProviderIsNull: true,
    ),
    explanation:
        'An ambiguous, masked-account-shaped "merchant" (likely a mistyped/garbled counterparty reference) — the plain merchant field preserves the raw text verbatim (still useful shown to a reviewer), but identity resolution correctly refuses to treat it as a real, typed entity.',
  ),
];

// ---------------------------------------------------------------------------
// 17. Payment provider vs merchant — the rail/app that moved the money is a
//     separate concept from who was paid; neither may ever stand in for the
//     other, and neither may ever be confused with the SMS sender's bank.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _paymentProviderVsMerchant = [
  const SmsTestCase(
    id: 'provider-phonepe-01',
    sender: 'VM-PHONPE',
    body: 'Rs.800 paid to swiggy@upi using PhonePe via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Swiggy',
      paymentProvider: PaymentProvider.phonePe,
    ),
    explanation: 'PhonePe is the provider; Swiggy is the merchant.',
  ),
  const SmsTestCase(
    id: 'provider-googlepay-01',
    sender: 'AD-GOOGLP',
    body: 'Rs.500 paid to amazon@upi using Google Pay via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Amazon',
      paymentProvider: PaymentProvider.googlePay,
    ),
    explanation:
        'Google Pay is the provider; Amazon is the merchant — never swapped.',
  ),
  const SmsTestCase(
    id: 'provider-paytm-01',
    sender: 'VK-PAYTM',
    body: 'Rs.300 paid to zomato@paytm using Paytm via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Zomato',
      paymentProvider: PaymentProvider.paytm,
    ),
    explanation:
        'Explicit "using Paytm" phrasing, reinforced (not overridden) by the @paytm handle.',
  ),
  const SmsTestCase(
    id: 'provider-amazonpay-01',
    sender: 'AD-AMAZNP',
    body: 'Rs.450 paid to bigbasket@upi using Amazon Pay via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'BigBasket',
      paymentProvider: PaymentProvider.amazonPay,
    ),
    explanation:
        'Deliberately picks a merchant unrelated to Amazon (BigBasket) paid via the Amazon Pay app — the provider\'s own brand name must never leak into the merchant field just because it superficially resembles a well-known merchant name.',
  ),
  const SmsTestCase(
    id: 'provider-bhim-01',
    sender: 'VM-BHIMUP',
    body: 'Rs.220 paid to zepto@upi using BHIM via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Zepto',
      paymentProvider: PaymentProvider.bhim,
    ),
    explanation: 'BHIM as the explicit provider.',
  ),
  const SmsTestCase(
    id: 'provider-cred-01',
    sender: 'VK-CREDAP',
    body: 'Rs.5,000 paid using CRED for credit card bill payment.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardBill,
      role: FinancialEventRole.linkedSettlement,
      paymentProvider: PaymentProvider.cred,
      merchantIsNull: true,
    ),
    explanation:
        'CRED is commonly used specifically for credit-card bill payments — no counterparty merchant is named at all, only the provider and the credit-card-bill semantics.',
  ),
  const SmsTestCase(
    id: 'provider-whatsapppay-01',
    sender: 'VK-WHATSP',
    body: 'Rs.150 paid to zomato@upi using WhatsApp Pay via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Zomato',
      paymentProvider: PaymentProvider.whatsappPay,
    ),
    explanation: 'WhatsApp Pay as the explicit provider.',
  ),
  const SmsTestCase(
    id: 'provider-bank-upi-no-app-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.500 paid to xyz@sbi via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'xyz@sbi',
      paymentProviderIsNull: true,
    ),
    explanation:
        'A plain bank-rail UPI VPA with no third-party app named and no recognized handle hint — the honest answer is "unknown", not a guessed app.',
  ),
  const SmsTestCase(
    id: 'provider-critical-never-merchant-01',
    sender: 'VM-PHONPE',
    body: 'Rs.500 paid using PhonePe.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantIsNull: true,
      paymentProvider: PaymentProvider.phonePe,
    ),
    explanation:
        'CRITICAL: no counterparty is named at all — PhonePe must resolve only as the provider, and must never be substituted in as the merchant just because it is the only proper noun in the message.',
    isDangerousIfMisclassified: false,
  ),
  const SmsTestCase(
    id: 'provider-received-via-01',
    sender: 'AD-GOOGLP',
    body: 'Rs.300 received from Rohit using Google Pay.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'Rohit',
      merchantTypeIsNull: true,
      paymentProvider: PaymentProvider.googlePay,
    ),
    explanation:
        'FIXED (Phase 4): the merchant regex now recognizes "received from X" phrasing (see SmsRegexUtils._merchantFromPattern), so the sender\'s name resolves correctly, cleanly separated from the trailing "using Google Pay" provider clause.',
  ),
];

// ---------------------------------------------------------------------------
// 18. Category variations — the same/similar merchant resolving to different
//     categories depending on context. Evaluated by a bespoke group in
//     sms_corpus_evaluation_test.dart with a real `categories` list and a
//     `CategoryResolver`-equipped extractor (the generic sweep runs with no
//     category resolver at all, so these would be meaningless there).
// ---------------------------------------------------------------------------
final List<SmsTestCase> _categoryVariations = [
  const SmsTestCase(
    id: 'category-var-amazon-shopping-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,200 debited from a/c XX1234 to Amazon on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Shopping',
    ),
    explanation:
        'A plain Amazon purchase resolves to Shopping via the seed catalog.',
  ),
  const SmsTestCase(
    id: 'category-var-amazon-prime-subscription-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,499 debited from a/c XX1234 to Amazon Prime on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Entertainment',
    ),
    explanation:
        'FIXED (Phase 4): added a dedicated "amazon prime" seed-catalog key (distinct from plain "amazon") mapping to Entertainment/Subscriptions/Shopping — a Prime subscription renewal now resolves correctly instead of getting no suggestion at all.',
  ),
  const SmsTestCase(
    id: 'category-var-amazon-grocery-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs.850 debited from a/c XX1234 to Amazon on 15-07-26 towards a grocery order.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Shopping',
    ),
    explanation:
        'KNOWN LIMITATION (category resolution): category is resolved purely from the merchant name ("Amazon" -> Shopping) — the narration\'s own "grocery order" context is not considered, so this still resolves to Shopping rather than Groceries.',
  ),
  const SmsTestCase(
    id: 'category-var-swiggy-food-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.450 debited from a/c XX1234 to Swiggy on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Food & Dining',
    ),
    explanation: 'A plain Swiggy food order resolves to Food & Dining.',
  ),
  const SmsTestCase(
    id: 'category-var-swiggy-instamart-groceries-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.650 debited from a/c XX1234 to Swiggy Instamart on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Swiggy',
      categoryNameEquals: 'Groceries',
    ),
    explanation:
        'FIXED (Phase 4): identity normalization (Swiggy Instamart -> "Swiggy" as the *display* name) no longer destroys the category signal — FinancialEventExtractor._merchantTextForCategoryLookup now feeds CategoryResolver the un-collapsed "Swiggy Instamart" text, and a dedicated seed-catalog key for it resolves to Groceries, correctly distinct from a plain Swiggy food order.',
  ),
  const SmsTestCase(
    id: 'category-var-indianoil-fuel-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.2,000 debited from a/c XX1234 to Indian Oil on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Fuel',
    ),
    explanation: 'A fuel-station merchant resolves to the Fuel category.',
  ),
  const SmsTestCase(
    id: 'category-var-restaurant-payment-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs.900 debited from a/c XX1234 to Spice Route Restaurant on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Food & Dining',
    ),
    explanation:
        'FIXED (Phase 4): CategoryResolver now has a narrow, deterministic contextual-keyword tier — a merchant name literally containing "Restaurant"/"Cafe"/etc. is itself strong local evidence, resolved against the user\'s real categories exactly like every other tier (never invents one that doesn\'t exist). Kept local to CategoryResolver (not the shared MerchantCategorySuggester) so it never affects the separate merchant_intelligence module\'s own confidence grading.',
  ),
  const SmsTestCase(
    id: 'category-var-telecom-jio-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.399 debited from a/c XX1234 to Jio on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Bills & Utilities',
    ),
    explanation: 'A telecom provider resolves to Bills & Utilities.',
  ),
  const SmsTestCase(
    id: 'category-var-airtel-recharge-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs.199 debited from a/c XX1234 to Airtel for mobile recharge on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Bills & Utilities',
    ),
    explanation:
        'Category is driven by the merchant (Airtel), not by the payment provider/rail or narration — "recharge" wording does not change the result.',
  ),
  const SmsTestCase(
    id: 'category-var-unknown-merchant-upi-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.500 paid to xyz123@oksbi via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryIsNull: true,
    ),
    explanation:
        'FIXED (Phase 4): a payment over UPI to a completely unresolved VPA no longer gets a "Shopping" suggestion purely from the payment rail — MerchantCategorySuggester._fromSmsCategory no longer maps upiPayment/cardPurchase/creditCardPurchase to Shopping at all (see Part 9 of the Phase 4 spec: "the payment mechanism is not the expense category"). Category correctly stays unresolved.',
  ),
];

// ---------------------------------------------------------------------------
// 19. Credit-card semantics — purchase vs bill payment vs reminder vs
//     payment request vs reversal, using the specific verb shapes
//     CreditCardSemantics looks for (a bare "card" mention isn't enough —
//     the literal phrase "credit card" plus a purchase/bill-payment verb
//     shape is what triggers deterministic resolution).
// ---------------------------------------------------------------------------
final List<SmsTestCase> _creditCardSemanticsExpanded = [
  const SmsTestCase(
    id: 'cc-purchase-var-01',
    sender: 'VK-ICICIB',
    body: 'Your credit card ending 7788 has been charged Rs.3,200 at Flipkart.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardPurchase,
      role: FinancialEventRole.originalCharge,
      paymentMethod: PaymentMethod.creditCard,
      moneyMovement: true,
    ),
    explanation:
        'A charge *to* the card — "has been charged" purchase phrasing.',
  ),
  const SmsTestCase(
    id: 'cc-purchase-var-02',
    sender: 'VK-ICICIB',
    body: 'Rs.999 spent on credit card ending 1122 at Dominos.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardPurchase,
      role: FinancialEventRole.originalCharge,
      merchantEquals: "Domino's",
      merchantType: MerchantType.business,
    ),
    explanation:
        'Casual "spent on credit card" phrasing, lowercase merchant alias.',
  ),
  const SmsTestCase(
    id: 'cc-bill-var-01',
    sender: 'VM-HDFCBK',
    body:
        'Your credit card bill payment of Rs.7,500 has been received. Thank you.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardBill,
      role: FinancialEventRole.linkedSettlement,
      moneyMovement: true,
    ),
    explanation:
        'A payment made *toward* the card\'s balance — "bill payment ... received" phrasing. Direction intentionally not asserted: this reads as a credit from the card\'s own perspective, a known ambiguity shared with the original credit-card-bill-payment-01 case.',
  ),
  const SmsTestCase(
    id: 'cc-bill-var-02',
    sender: 'VM-HDFCBK',
    body: 'Rs.4,000 paid towards your credit card bill. Payment successful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardBill,
      role: FinancialEventRole.linkedSettlement,
      direction: SmsTransactionDirection.debit,
      moneyMovement: true,
    ),
    explanation:
        '"paid towards ... bill" phrasing, unambiguous debit direction this time.',
  ),
  const SmsTestCase(
    id: 'cc-reminder-01',
    sender: 'VK-ICICIB',
    body: 'Your credit card bill of Rs.5,000 will be auto-debited tomorrow.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      eventType: FinancialEventType.reminder,
    ),
    explanation: 'A credit-card bill reminder — nothing has been paid yet.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'cc-payment-request-01',
    sender: 'VK-ICICIB',
    body:
        'Please pay your credit card bill of Rs.5,000 before it is auto-debited to avoid late fee.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'An imperative payment request, not a completed payment.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'cc-reversal-01',
    sender: 'VK-ICICIB',
    body: 'Rs.5,000 credit card transaction has been reversed.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      // "transaction" (a debit-pattern word) appears before "reversed" (a
      // credit-pattern word) — SmsRegexUtils.extractDirection breaks a
      // debit/credit tie by trusting whichever keyword appears first, so
      // this resolves to debit despite the net effect reading as money
      // coming back.
      direction: SmsTransactionDirection.debit,
      moneyMovement: true,
    ),
    explanation:
        'A reversed credit-card transaction — neither "charged" nor a bill-payment shape, so CreditCardSemantics reports ambiguous, and the separate reversed-status fallback correctly takes over.',
  ),
  const SmsTestCase(
    id: 'cc-ambiguous-no-transaction-verb-01',
    sender: 'VK-ICICIB',
    body: 'Your credit card ending 4455 has an available limit of Rs.50,000.',
    expected: ExpectedFinancialClassification(shouldParse: false),
    explanation:
        'Purely informational credit-limit notice with no debit/credit/status verb at all — correctly fails to parse rather than being guessed at as any kind of transaction.',
  ),
  const SmsTestCase(
    id: 'cc-purchase-future-tense-not-transaction-01',
    sender: 'VK-ICICIB',
    body:
        'Your credit card ending 9911 will be charged Rs.2,000 for annual fee renewal next month.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      eventType: FinancialEventType.reminder,
    ),
    explanation:
        'CreditCardSemantics\' purchase-verb pattern ("charged" near "credit card") does not know about tense — the reminder safety gate (future-tense "will be charged") must still win and suppress this from ever reading as a completed purchase.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'cc-bill-due-not-paid-01',
    sender: 'VM-HDFCBK',
    body:
        'Your credit card payment of Rs.3,500 will be debited on 20-07-26 if not paid before the due date.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'A due-payment notice, not a completed bill payment.',
    isDangerousIfMisclassified: true,
  ),
];

// ---------------------------------------------------------------------------
// 20. Reminder safety — expanded with more varied real-world phrasing, plus
//     a contrasting pair of genuinely completed transactions that share
//     surface-level words ("debited", "due") with the reminder cases above.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _reminderSafetyExpanded = [
  const SmsTestCase(
    id: 'reminder-var-future-inr-01',
    sender: 'VM-HDFCBK',
    body: 'INR 2,000 will be debited tomorrow towards your EMI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'INR-prefixed future-tense EMI notice.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-var-symbol-01',
    sender: 'VM-HDFCBK',
    body: '₹2,000 will be deducted on 5th September towards your subscription.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation:
        '₹ symbol, "will be deducted" future-tense subscription notice.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-var-standing-instruction-01',
    sender: 'VM-HDFCBK',
    body:
        'As per standing instruction, Rs.999 will be auto-debited for your Netflix subscription tomorrow.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'Standing-instruction auto-debit notice, future tense.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-var-subscription-scheduled-01',
    sender: 'VM-HDFCBK',
    body:
        'Your subscription payment of Rs.499 is scheduled for tomorrow and will be charged to your card.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: '"is scheduled for" future-tense phrasing.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-var-emi-abbreviation-01',
    sender: 'VM-HDFCBK',
    body:
        'EMI of Rs.3,200 is due tomorrow and will be debited automatically. Kindly ensure sufficient balance.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'Abbreviated "EMI" wording, explicit "is due tomorrow".',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-var-bill-abbreviated-01',
    sender: 'VM-SBIBNK',
    body:
        'Bill Rs.1,500 due date 20-07-26. It will be auto-debited if unpaid. Please pay before due date to avoid late fee.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'Terse "Bill Rs.X due date ..." bank-shorthand phrasing.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-var-loan-installment-01',
    sender: 'VM-HDFCBK',
    body:
        'Your upcoming EMI installment of Rs.4,500 will be charged on 25-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation:
        '"upcoming EMI installment" plus future-tense "will be charged".',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-var-comma-lakh-01',
    sender: 'VM-HDFCBK',
    body:
        'Your EMI of Rs.1,23,456 will be debited tomorrow. Please pay in advance to avoid penalty.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      amount: 123456.0,
    ),
    explanation: 'Indian lakh comma-grouping combined with reminder wording.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'reminder-contrast-completed-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.2,000 has been debited towards your EMI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.loanEmi,
    ),
    explanation:
        'Contrast case: "has been debited" is an explicit completion marker that always overrides reminder-shaped wording elsewhere in the message — this is a genuinely completed EMI debit, not a reminder.',
  ),
  const SmsTestCase(
    id: 'reminder-contrast-completed-02',
    sender: 'VK-AXISBK',
    body: 'EMI payment of Rs.2,000 successful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      direction: SmsTransactionDirection.debit,
    ),
    explanation:
        'Contrast case: "payment ... successful" is a completion marker, not a reminder.',
  ),
];

// ---------------------------------------------------------------------------
// 21. Failed / pending — expanded, including the explicit "debited" negation
//     trap Part 6 calls out (a failure message that still contains the word
//     "debited" while explicitly saying no money moved).
// ---------------------------------------------------------------------------
final List<SmsTestCase> _failedPendingExpanded = [
  const SmsTestCase(
    id: 'failed-var-has-failed-01',
    sender: 'VM-HDFCBK',
    body: 'Your payment of Rs.500 has failed.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: 'Plain "has failed" status wording.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-var-upi-pending-01',
    sender: 'VK-PAYTM',
    body: 'UPI transaction of Rs.500 is pending.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.pending,
      direction: SmsTransactionDirection.debit,
    ),
    explanation: 'UPI-app-style pending confirmation.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-var-explicit-no-amount-debited-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 transaction failed. No amount has been debited.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation:
        'The exact adversarial trap: the word "debited" appears in the sentence, but the sentence explicitly negates it ("No amount has been debited") — the failed-status check must win regardless of that word\'s mere presence.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-var-successful-contrast-01',
    sender: 'VK-PAYTM',
    body: 'Rs.500 transaction successful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      direction: SmsTransactionDirection.debit,
    ),
    explanation: 'Contrast case: a genuinely completed transaction.',
  ),
  const SmsTestCase(
    id: 'failed-var-debited-successfully-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 has been debited successfully.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      direction: SmsTransactionDirection.debit,
    ),
    explanation:
        'Contrast case: "debited" AND "successfully" — genuinely completed.',
  ),
  const SmsTestCase(
    id: 'failed-var-declined-01',
    sender: 'VK-AXISBK',
    body:
        'Your card transaction of Rs.1,200 was declined due to insufficient funds.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation:
        '"declined" + "insufficient funds" — doubly-confirmed failure.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-var-could-not-be-processed-01',
    sender: 'VM-SBIBNK',
    body: 'Your payment of Rs.750 could not be processed. Please retry.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: '"could not be processed" failure phrasing.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-var-unsuccessful-01',
    sender: 'VK-PAYTM',
    body: 'UPI payment of Rs.300 was unsuccessful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: '"unsuccessful" failure wording via a UPI app sender.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-var-pending-confirmation-neft-01',
    sender: 'VM-SBIBNK',
    body:
        'Your NEFT transfer of Rs.10,000 is pending confirmation from the beneficiary bank.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.pending,
    ),
    explanation: 'NEFT transfer awaiting confirmation — not yet complete.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'failed-var-under-process-01',
    sender: 'VK-PAYTM',
    body: 'Rs.600 UPI payment is under process. Processing your request.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.pending,
    ),
    explanation: '"under process" / "processing" pending wording.',
    isDangerousIfMisclassified: true,
  ),
];

// ---------------------------------------------------------------------------
// 22. Reversal / refund — expanded, including compound sentences and the
//     "declined and reversed" collision where TransactionStatusSignals'
//     failed-checked-before-reversed priority order matters.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _reversalRefundExpanded = [
  const SmsTestCase(
    id: 'reversal-var-later-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited and later reversed to your account.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.debit,
    ),
    explanation:
        'Compound debit-then-reversal sentence, resolves cleanly to reversed.',
  ),
  const SmsTestCase(
    id: 'reversal-var-plain-01',
    sender: 'VK-AXISBK',
    body: 'Rs.500 transaction has been reversed to your account.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.debit,
    ),
    explanation: 'Plain reversal notice.',
  ),
  const SmsTestCase(
    id: 'refund-var-generic-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 refunded to your account for a cancelled order.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.refund,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    ),
    explanation:
        'A cancelled-order refund is a real, if inverse, money movement.',
  ),
  const SmsTestCase(
    id: 'refund-var-received-from-merchant-01',
    sender: 'VM-HDFCBK',
    body: 'Refund of Rs.500 received from Amazon.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.refund,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'Amazon',
      merchantType: MerchantType.business,
    ),
    explanation:
        'FIXED (Phase 4): the merchant regex now recognizes "received from X" phrasing, so "Amazon" resolves correctly (and normalizes via the catalog) instead of staying unresolved.',
  ),
  const SmsTestCase(
    id: 'refund-var-previous-debit-reversed-01',
    sender: 'VK-AXISBK',
    body: 'Previous debit of Rs.500 has been reversed to your account.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.credit,
    ),
    explanation:
        '"debit" as a noun (not the verb "debited") does not compete with "reversed" for direction.',
  ),
  const SmsTestCase(
    id: 'reversal-var-pos-technical-error-01',
    sender: 'VM-SBIBNK',
    body:
        'Rs.800 debited for POS purchase at a store which was later reversed due to a technical error.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.debit,
    ),
    explanation:
        'A compound debit+reversal sentence without a competing "declined"/"failed" word resolves correctly and safely — contrast with reversal-var-declined-then-reversed-01 below, where "declined" changes the outcome.',
  ),
  const SmsTestCase(
    id: 'reversal-var-declined-then-reversed-01',
    sender: 'VM-SBIBNK',
    body:
        'Rs.500 debited for a purchase which was declined and reversed same day.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation:
        'INVESTIGATED (Phase 4 Part 8), NOT a bug: TransactionStatusSignals checks "declined"/failed wording before "reversed" wording, resolving this to failed rather than reversed. On reflection this is the semantically CORRECT (and safer) reading, not a limitation to fix: "declined" means the charge was never actually captured — a same-day "reversal" in that context almost always describes an authorization hold being released, not a real debit-then-refund. Treating this as reversed would flip moneyMovement to true (reversed is not a blocking status), which would be LESS safe than the current failed/moneyMovement=false outcome. Precedence is intentionally left unchanged; see the Phase 4 report for the full analysis.',
  ),
  const SmsTestCase(
    id: 'refund-var-cashback-not-confused-01',
    sender: 'VK-PAYTM',
    body: 'Rs.30 cashback refunded to your wallet for your recent order.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.cashback,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    ),
    explanation:
        'Both "cashback" and "refunded" appear — category resolution prioritizes "cashback" (checked first in guessCategory), while the status layer independently and correctly still reads "refunded" — the two are not in conflict, just answering different questions.',
  ),
  const SmsTestCase(
    id: 'reversal-var-vpa-context-01',
    sender: 'VM-ICICIB',
    body: 'Rs.500 paid to swiggy@icici via UPI has been reversed.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.debit,
      merchantEquals: 'Swiggy',
      merchantType: MerchantType.business,
    ),
    explanation:
        'Merchant identity resolves correctly even through a reversal-status message.',
  ),
  const SmsTestCase(
    id: 'refund-var-due-to-not-a-reminder-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 refunded for your order due to cancellation.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.refund,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    ),
    explanation:
        'Guards against a false reminder suppression: "due to cancellation" contains the word "due" but is not reminder-shaped wording ("due date"/"is due tomorrow"/etc.) — a genuine refund must not be hidden because of this substring.',
    isDangerousIfMisclassified: true,
  ),
];

// ---------------------------------------------------------------------------
// 23. Unknown merchant safety — bare VPAs/phone numbers/masked tokens that a
//     naive or AI-assisted pipeline might be tempted to inflate into an
//     invented person or business name. Unknown is always the correct
//     answer here.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _unknownMerchantSafety = [
  const SmsTestCase(
    id: 'unknown-merchant-var-oksbi-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.500 paid to 9876543210@oksbi via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: '9876543210@oksbi',
      merchantTypeIsNull: true,
    ),
    explanation:
        'A bare phone-number VPA — must never be inflated into a person\'s name.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-okaxis-text-01',
    sender: 'VM-AXISBK',
    body: 'Rs.700 transferred to xyz@okaxis via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'xyz@okaxis',
      merchantTypeIsNull: true,
    ),
    explanation: 'A short, meaningless VPA local part — stays exactly as-is.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-numeric-okaxis-01',
    sender: 'VM-AXISBK',
    body: 'Rs.1,000 paid to 12345@okaxis via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: '12345@okaxis',
      merchantTypeIsNull: true,
    ),
    explanation: 'A numeric VPA local part with no catalog match.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-ybl-01',
    sender: 'VM-PHONPE',
    body: 'Rs.250 sent to random9988@ybl via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'random9988@ybl',
      merchantTypeIsNull: true,
      paymentProvider: PaymentProvider.phonePe,
    ),
    explanation:
        'The "@ybl" handle is a weak PhonePe hint (provider), independent of the still-unresolved merchant identity.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-no-handle-hint-01',
    sender: 'VM-ICICIB',
    body: 'Rs.180 paid to unknownuser@icici via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'unknownuser@icici',
      merchantTypeIsNull: true,
      paymentProviderIsNull: true,
    ),
    explanation:
        'Neither the merchant nor the provider can be determined here — both stay honestly unknown.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-plain-numeric-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 to 9876543210 on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: '9876543210',
      merchantTypeIsNull: true,
      paymentProviderIsNull: true,
    ),
    explanation:
        'A bare phone number, not even VPA-shaped — no identity, no provider.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-masked-token-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.300 debited from a/c XX1234 to XXXX5678 on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'XXXX5678',
      merchantTypeIsNull: true,
    ),
    explanation:
        'A masked-account-shaped counterparty reference — kept verbatim, never typed as a real entity.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-never-becomes-person-01',
    sender: 'VK-PAYTM',
    body: 'Rs.500 paid to 9876543210 for dinner with Rahul.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: '9876543210',
      merchantTypeIsNull: true,
    ),
    explanation:
        'CRITICAL: the message mentions a person\'s name ("Rahul") in unrelated narration text — the resolved merchant must stay the raw phone number the payment actually went "to", and must never become "Rahul" just because that name appears somewhere in the sentence.',
    isDangerousIfMisclassified: false,
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-never-abc-store-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.500 paid to xyz987@oksbi for groceries near ABC Store via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'xyz987@oksbi',
      merchantTypeIsNull: true,
    ),
    explanation:
        'CRITICAL: "ABC Store" appears in unrelated narration text — the VPA the message actually paid ("xyz987@oksbi") must win, and "ABC Store" must never be substituted in as the resolved merchant.',
  ),
  const SmsTestCase(
    id: 'unknown-merchant-var-never-invented-company-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.900 debited from a/c XX1234 to xyz@upibank on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'xyz@upibank',
      merchantTypeIsNull: true,
      paymentProviderIsNull: true,
    ),
    explanation:
        'An unrecognized VPA handle — must never be inflated into a guessed company name.',
  ),
];

// ---------------------------------------------------------------------------
// 24. Merchant "from X" extraction (Phase 4 Part 4) — the credit-side
//     counterpart to "to X"/"at X", including the explicit guard against
//     turning a generic noun phrase ("your employer", "a friend") into a
//     fake merchant.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _merchantFromXExtraction = [
  const SmsTestCase(
    id: 'from-x-basic-amazon-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1000 received from Amazon.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'Amazon',
      merchantType: MerchantType.business,
    ),
    explanation: 'Basic "received from X" credit-side merchant extraction.',
  ),
  const SmsTestCase(
    id: 'from-x-person-01',
    sender: 'VK-PAYTM',
    body: 'Rs.500 received from Rahul.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'Rahul',
      merchantTypeIsNull: true,
    ),
    explanation:
        'A person\'s name via "received from" — explicit text, never typed without evidence.',
  ),
  const SmsTestCase(
    id: 'from-x-transfer-received-01',
    sender: 'VM-ICICIB',
    body: 'Rs.2000 transfer received from ABC Pvt Ltd.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'ABC Pvt Ltd',
      merchantTypeIsNull: true,
    ),
    explanation: '"transfer received from X" phrasing.',
  ),
  const SmsTestCase(
    id: 'from-x-money-received-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.750 money received from Zomato.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'Zomato',
      merchantType: MerchantType.business,
    ),
    explanation: '"money received from X" phrasing.',
  ),
  const SmsTestCase(
    id: 'from-x-received-payment-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.400 received payment from Flipkart.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'Flipkart',
      merchantType: MerchantType.business,
    ),
    explanation: '"received payment from X" phrasing.',
  ),
  const SmsTestCase(
    id: 'from-x-generic-employer-guard-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.50,000 payment received from your employer.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      amount: 50000.0,
      merchantIsNull: true,
    ),
    explanation:
        'GUARD: "your employer" is a generic noun phrase, not a merchant name — the negative lookahead after "from" must keep this unresolved rather than inventing "Your Employer" as a business.',
  ),
  const SmsTestCase(
    id: 'from-x-generic-friend-guard-01',
    sender: 'VK-PAYTM',
    body: 'Rs.500 received from a friend.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantIsNull: true,
    ),
    explanation:
        'GUARD: "a friend" is generic, never turned into a fake merchant.',
  ),
  const SmsTestCase(
    id: 'from-x-provider-trailing-01',
    sender: 'AD-GOOGLP',
    // Reuses PhonePe here deliberately (via GOOGLP sender is irrelevant —
    // the sender header doesn't gate which provider phrase can appear in
    // the body) to exercise the boundary logic against a *different*
    // trailing-clause word ("via") than provider-received-via-01's "using".
    body: 'Rs.450 received from Priya via PhonePe.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantEquals: 'Priya',
      merchantTypeIsNull: true,
      paymentProvider: PaymentProvider.phonePe,
    ),
    explanation:
        'Merchant and provider both resolve correctly, cleanly separated at the "via" boundary.',
  ),
  const SmsTestCase(
    id: 'from-x-support-email-guard-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs.500 debited from a/c XX1234. For help, mail us at support@hdfcbank.com.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.debit,
      merchantIsNull: true,
    ),
    explanation:
        'GUARD: neither "from a/c XX1234" (the negative lookahead blocks the bare word "a") nor the support email address (no "to"/"at"/"from" clause reaches it, and "@" is outside the capture character class) is ever mistaken for a merchant.',
  ),
  const SmsTestCase(
    id: 'from-x-formatting-variety-01',
    sender: 'VM-ICICIB',
    body: '₹1,200 transfer received from XYZ Enterprises.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      amount: 1200.0,
      merchantEquals: 'XYZ Enterprises',
      merchantTypeIsNull: true,
    ),
    explanation:
        '₹ symbol formatting combined with "transfer received from X".',
  ),
];

// ---------------------------------------------------------------------------
// 25. Payment provider present, no merchant named at all — the provider must
//     never fill in as a stand-in merchant.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _providerWithoutMerchant = [
  const SmsTestCase(
    id: 'provider-no-merchant-phonepe-01',
    sender: 'VM-PHONPE',
    body: 'Rs.700 paid using PhonePe.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantIsNull: true,
      paymentProvider: PaymentProvider.phonePe,
    ),
    explanation:
        'No counterparty named — PhonePe is the provider, never substituted as the merchant.',
  ),
  const SmsTestCase(
    id: 'provider-no-merchant-googlepay-01',
    sender: 'AD-GOOGLP',
    body: 'Rs.300 received via Google Pay.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.credit,
      merchantIsNull: true,
      paymentProvider: PaymentProvider.googlePay,
    ),
    explanation: 'Credit-side provider-only message.',
  ),
  const SmsTestCase(
    id: 'provider-no-merchant-paytm-01',
    sender: 'VK-PAYTM',
    body: 'Rs.150 paid using Paytm.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantIsNull: true,
      paymentProvider: PaymentProvider.paytm,
    ),
    explanation: 'Paytm-only message, no merchant.',
  ),
  const SmsTestCase(
    id: 'provider-no-merchant-bhim-01',
    sender: 'VM-BHIMUP',
    body: 'Rs.999 sent using BHIM.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      direction: SmsTransactionDirection.debit,
      merchantIsNull: true,
      paymentProvider: PaymentProvider.bhim,
    ),
    explanation: 'BHIM-only message, no merchant.',
  ),
  const SmsTestCase(
    id: 'provider-no-merchant-cred-01',
    sender: 'VK-CREDAP',
    body: 'Rs.5,000 paid using CRED.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantIsNull: true,
      paymentProvider: PaymentProvider.cred,
    ),
    explanation: 'CRED-only message, no merchant.',
  ),
];

// ---------------------------------------------------------------------------
// 26. Provider vs. category adversarial — the payment rail/app must never
//     imply a spending category. Evaluated by the category-testing bespoke
//     group in sms_corpus_evaluation_test.dart (see categoryVariationIds).
// ---------------------------------------------------------------------------
final List<SmsTestCase> _providerVsCategoryAdversarial = [
  const SmsTestCase(
    id: 'provider-category-phonepe-not-shopping-01',
    sender: 'VM-PHONPE',
    body: 'Rs.500 paid using PhonePe.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryIsNull: true,
    ),
    explanation:
        'PhonePe alone must never imply Shopping — no merchant/category evidence exists here.',
  ),
  const SmsTestCase(
    id: 'provider-category-googlepay-not-shopping-01',
    sender: 'AD-GOOGLP',
    body: 'Rs.2,000 paid using Google Pay.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryIsNull: true,
    ),
    explanation: 'Google Pay alone must never imply Shopping.',
  ),
  const SmsTestCase(
    id: 'provider-category-merchant-wins-01',
    sender: 'VM-PHONPE',
    body: 'Paid Rs.500 using PhonePe to Swiggy.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Food & Dining',
    ),
    explanation:
        'The merchant (Swiggy) drives the category, not the provider (PhonePe).',
  ),
  const SmsTestCase(
    id: 'provider-category-indianoil-wins-01',
    sender: 'AD-GOOGLP',
    body: 'Paid Rs.2,000 using Google Pay to Indian Oil.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryNameEquals: 'Fuel',
    ),
    explanation:
        'The merchant (Indian Oil) drives the category, not the provider (Google Pay).',
  ),
  const SmsTestCase(
    id: 'provider-category-card-not-shopping-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.800 spent using card.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      categoryIsNull: true,
    ),
    explanation:
        'A bare card-rail mention with no merchant must never resolve to Shopping — same rail-implies-category anti-pattern as UPI, now also closed for the "card" wording.',
  ),
];

// ---------------------------------------------------------------------------
// 27. Normalization preserves context — catalog display-name normalization
//     (Swiggy Instamart -> "Swiggy", a display concern) must not destroy
//     the category-relevant distinction the un-collapsed variant text
//     carries. Category assertions here are evaluated by the bespoke
//     category-testing group.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _normalizationPreservesContext = [
  const SmsTestCase(
    id: 'normalization-swiggy-instamart-upper-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 to SWIGGY INSTAMART on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Swiggy',
      categoryNameEquals: 'Groceries',
    ),
    explanation:
        'All-caps "Swiggy Instamart" still normalizes its *display* name to "Swiggy" while the category resolver still sees the un-collapsed variant and correctly resolves Groceries, not Food & Dining.',
  ),
  const SmsTestCase(
    id: 'normalization-swiggy-instamart-lower-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 to swiggy instamart on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Swiggy',
      categoryNameEquals: 'Groceries',
    ),
    explanation: 'Lowercase variant, same outcome as the all-caps case.',
  ),
  const SmsTestCase(
    id: 'normalization-swiggy-plain-contrast-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 to SWIGGY on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Swiggy',
    ),
    explanation:
        'Contrast: plain "Swiggy" (no Instamart) normalizes its display name the same way, but — evaluated in the bespoke category group — resolves to Food & Dining, not Groceries. See category-var-swiggy-food-01.',
  ),
  const SmsTestCase(
    id: 'normalization-amazon-prime-upper-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,499 debited from a/c XX1234 to AMAZON PRIME on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      // "Amazon Prime" is not a merchantCatalog alias (only plain "Amazon"
      // is), so this resolves via the explicitText tier — which, unlike
      // the catalog tiers, never normalizes spelling — so the raw
      // all-caps text is preserved verbatim as the display value.
      merchantEquals: 'AMAZON PRIME',
      categoryNameEquals: 'Entertainment',
    ),
    explanation:
        'A merchant variant with no catalog entry of its own keeps its own raw text (case included) as both the display value and the category-lookup key — correctly distinct from plain "Amazon".',
  ),
  const SmsTestCase(
    id: 'normalization-amazon-prime-lower-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,499 debited from a/c XX1234 to amazon prime on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'amazon prime',
      categoryNameEquals: 'Entertainment',
    ),
    explanation: 'Lowercase variant, same outcome.',
  ),
];

/// Ids evaluated by the category-testing bespoke group — see
/// [categoryVariationIds]'s own doc comment.
final List<String> _providerVsCategoryAndNormalizationCategoryIds = [
  ..._providerVsCategoryAdversarial.map((c) => c.id),
  'normalization-swiggy-instamart-upper-01',
  'normalization-swiggy-instamart-lower-01',
  'normalization-amazon-prime-upper-01',
  'normalization-amazon-prime-lower-01',
];

// ---------------------------------------------------------------------------
// 28. Status combinations (Phase 4 Part 8) — investigating whether
//     "declined"/"failed" wording taking priority over "reversed" wording is
//     a bug or the intentionally safer reading. See
//     reversal-var-declined-then-reversed-01 (section 22) for the first,
//     most direct case of this; these extend the combination coverage per
//     the Phase 4 spec's explicit list.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _statusCombinations = [
  const SmsTestCase(
    id: 'status-declined-alone-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 payment declined.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
      direction: SmsTransactionDirection.debit,
    ),
    explanation: 'A plain decline, no reversal wording at all — unambiguous.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'status-reversed-alone-01',
    sender: 'VK-AXISBK',
    body: 'Rs.500 transaction reversed.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.debit,
    ),
    explanation:
        'A plain reversal, no failure/decline wording at all — unambiguous, real money movement.',
  ),
  const SmsTestCase(
    id: 'status-failed-and-reversed-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 payment failed and reversed.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
      direction: SmsTransactionDirection.credit,
    ),
    explanation:
        'Same "failed wins" priority as "declined and reversed" — INVESTIGATED, intentional: a failed payment never completed, so any accompanying "reversed" wording most plausibly describes an authorization hold being released, not a real debit-then-refund. Treating this as a completed reversal would be the less safe reading.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'status-payment-failed-but-reversed-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.500 payment failed but the amount was reversed.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
      direction: SmsTransactionDirection.credit,
    ),
    explanation:
        'The explicit "failed" verdict still wins even when the sentence explicitly says "the amount was reversed" — the conservative (no completed movement) reading is preserved.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'status-transaction-reversed-after-decline-01',
    sender: 'VK-AXISBK',
    body: 'Rs.500 transaction reversed after a decline.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.debit,
    ),
    explanation:
        'BOUNDARY CASE (documented, not fixed): "decline" (a bare noun) does not match any `_failedPatterns` word (which requires the literal past-tense "declined") — so this phrasing genuinely has no failed/pending signal at all, and correctly resolves via the reversed-status fallback to a real, completed reversal. This is precedence-sensitive to the exact word form used, which is itself worth knowing about rather than silently relying on.',
  ),
];

// ---------------------------------------------------------------------------
// 29. Phase 5 realistic corpus — ~50 additional cases spanning UPI, cards,
//     ATM, bank transfers, refunds, reversals, EMI, loans, subscriptions,
//     self-transfers, merchant/provider ambiguity, unknown VPAs, compound
//     messages, reminders, and failed/pending, with deliberately varied
//     real-world wording rather than one template repeated with a new
//     merchant substituted in.
// ---------------------------------------------------------------------------
final List<SmsTestCase> _phase5RealisticCorpus = [
  // --- UPI (5) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-upi-zomato-vpa-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.320.00 debited via UPI to zomato@icici. UPI Ref 887766554433.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      amount: 320.0,
      merchantEquals: 'Zomato',
      merchantType: MerchantType.business,
    ),
    explanation: 'Standard bank-template UPI debit with a catalog VPA.',
  ),
  const SmsTestCase(
    id: 'p5-upi-collect-request-not-paid-01',
    sender: 'VK-PAYTM',
    body:
        'Amit has requested Rs.250 via UPI. Payment is pending your approval.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'A collect request is not a completed payment until approved.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-upi-self-initiated-app-confirmation-01',
    sender: 'VM-PHONPE',
    body: 'You paid Rs.180 to blinkit@icici via UPI. Transaction successful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
      transactionStatus: TransactionStatus.success,
      merchantEquals: 'Blinkit',
      merchantType: MerchantType.business,
    ),
    explanation: 'App-style confirmation SMS, explicit success wording.',
  ),
  const SmsTestCase(
    id: 'p5-upi-low-value-tip-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.20 paid to swiggy@icici via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      amount: 20.0,
      merchantEquals: 'Swiggy',
    ),
    explanation:
        'A small-value UPI payment (e.g. a delivery tip) still resolves normally.',
  ),
  const SmsTestCase(
    id: 'p5-upi-lakh-value-01',
    sender: 'VM-ICICIB',
    body: 'Rs.2,50,000 debited via UPI to abc@okaxis. UPI Ref 112233445566.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      amount: 250000.0,
      merchantEquals: 'abc@okaxis',
      merchantTypeIsNull: true,
    ),
    explanation:
        'A large lakh-formatted UPI debit to an uncatalogued VPA — stays unresolved, never invented.',
  ),

  // --- Cards (5) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-card-debit-purchase-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.1,850 spent using debit card ending 4455 at Big Bazaar.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.debit,
    ),
    explanation: 'Debit card POS purchase, no "credit card" wording at all.',
  ),
  const SmsTestCase(
    id: 'p5-card-credit-purchase-restaurant-01',
    sender: 'VK-ICICIB',
    body: 'Your credit card ending 2233 was charged Rs.1,200 at a restaurant.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardPurchase,
      role: FinancialEventRole.originalCharge,
    ),
    explanation:
        'Credit card purchase phrasing at a generic (non-catalog) restaurant merchant.',
  ),
  const SmsTestCase(
    id: 'p5-card-declined-insufficient-limit-01',
    sender: 'VK-ICICIB',
    body:
        'Your credit card transaction of Rs.5,000 was declined due to insufficient credit limit.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: 'A declined card transaction never implies money moved.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-card-emi-conversion-not-purchase-01',
    sender: 'VK-ICICIB',
    body:
        'Your credit card purchase of Rs.12,000, charged earlier, has been converted to EMI of Rs.1,000 per month.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardPurchase,
      role: FinancialEventRole.originalCharge,
    ),
    explanation:
        'An EMI-conversion notice for an already-completed purchase — "credit card purchase" itself satisfies CreditCardSemantics\' purchase verb shape, so this resolves as the original charge rather than a fresh/ambiguous event. The EMI-restructuring detail itself is not separately modeled this phase (see the Phase 5 report\'s scoping notes) — only the underlying purchase classification is asserted here.',
  ),
  const SmsTestCase(
    id: 'p5-card-annual-fee-reversed-01',
    sender: 'VK-AXISBK',
    body:
        'Rs.500 annual fee on your credit card has been reversed as a loyalty benefit.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
    ),
    explanation: 'A fee reversal is real (inverse) money movement.',
  ),

  // --- ATM (5) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-atm-withdrawal-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.5,000 withdrawn from ATM using your card ending 7788.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.cashWithdrawal,
      paymentMethod: PaymentMethod.atm,
    ),
    explanation:
        'A plain ATM cash withdrawal — channel is ATM specifically, not generic cash.',
  ),
  const SmsTestCase(
    id: 'p5-atm-withdrawal-failed-01',
    sender: 'VM-SBIBNK',
    body:
        'Your ATM withdrawal of Rs.10,000 has failed. No amount has been debited.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation:
        'A failed ATM attempt, explicit "no amount has been debited" negation.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-atm-cash-deposit-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.8,000 cash deposited to your account XX1234 via ATM.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.cashDeposit,
      direction: SmsTransactionDirection.credit,
    ),
    explanation: 'ATM cash deposit — distinct event type from a withdrawal.',
  ),
  const SmsTestCase(
    id: 'p5-atm-low-balance-warning-not-transaction-01',
    sender: 'VM-SBIBNK',
    body:
        'Your account balance is low. Avoid ATM withdrawal charges by maintaining minimum balance.',
    expected: ExpectedFinancialClassification(shouldParse: false),
    explanation:
        'A generic balance/fee-avoidance advisory, no actual amount transacted — correctly fails to parse.',
  ),
  const SmsTestCase(
    id: 'p5-atm-withdrawal-abroad-01',
    sender: 'VK-AXISBK',
    body:
        'USD 200 (approx Rs.16,600) withdrawn from ATM abroad using card ending 3344.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.cashWithdrawal,
    ),
    explanation:
        'An international ATM withdrawal, INR figure stated in parentheses.',
  ),

  // --- Bank transfers / own-account (5) --------------------------------
  const SmsTestCase(
    id: 'p5-neft-external-transfer-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.15,000 transferred via NEFT to A/c 6677 from a/c XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      isOwnAccountTransfer: false,
    ),
    explanation:
        'A NEFT transfer to an account not among the user\'s known accounts — genuine external transfer.',
  ),
  const SmsTestCase(
    id: 'p5-imps-self-transfer-different-bank-01',
    sender: 'VM-ICICIB',
    body: 'Rs.20,000 transferred via IMPS to A/c 9876 from a/c XX5544.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      isOwnAccountTransfer: true,
      eventType: FinancialEventType.transfer,
    ),
    explanation:
        'IMPS self-transfer between accounts at two different banks — the destination last-4 (9876) is checked against a matcher configured with that account (bespoke group).',
  ),
  const SmsTestCase(
    id: 'p5-upi-self-transfer-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.3,000 sent to 9876@oksbi via UPI from a/c XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
    ),
    explanation:
        'A UPI "self-transfer" scenario — this specific case is not run through the own-account bespoke matcher (see own-account-transfer-01/p5-imps-self-transfer-different-bank-01 for that), so only baseline parsing/movement is asserted here; it exists to document that UPI self-transfers use ordinary VPA phrasing indistinguishable from a regular payment without last-4 matching.',
  ),
  const SmsTestCase(
    id: 'p5-transfer-ambiguous-no-destination-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.5,000 transferred from a/c XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      isOwnAccountTransfer: false,
    ),
    explanation:
        'Ambiguous account information: no destination last-4 is stated at all, so there is nothing to match against the user\'s own accounts — correctly defaults to NOT flagged as an own-account transfer rather than guessing.',
  ),
  const SmsTestCase(
    id: 'p5-rtgs-large-transfer-01',
    sender: 'VK-AXISBK',
    body: 'Rs.5,00,000 transferred via RTGS to A/c 3322 from a/c XX9988.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      amount: 500000.0,
    ),
    explanation: 'A large RTGS transfer, lakh formatting.',
  ),

  // --- Refunds (4) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-refund-flipkart-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,200 refunded to your account for your Flipkart order.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.refund,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    ),
    explanation: 'A standard e-commerce order refund.',
  ),
  const SmsTestCase(
    id: 'p5-refund-partial-amount-01',
    sender: 'VM-ICICIB',
    body: 'Rs.300 partial refund credited for your cancelled item.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.refund,
      direction: SmsTransactionDirection.credit,
    ),
    explanation: 'A partial refund is still a real, distinct financial event.',
  ),
  const SmsTestCase(
    id: 'p5-refund-processing-not-yet-credited-01',
    sender: 'VK-PAYTM',
    body: 'Rs.450 refund is processing and will reflect in 5-7 business days.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.pending,
    ),
    explanation: 'A refund still "being processed" has not actually moved yet.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-refund-then-original-still-separate-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.1,000 refund credited. Ref RRN998877665544.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.refund,
      referenceNumberIsNull: false,
    ),
    explanation:
        'A refund carrying its own reference number — a separate, linkable financial event, not a dedup of the original purchase.',
  ),

  // --- Reversals (3) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-reversal-duplicate-charge-01',
    sender: 'VK-AXISBK',
    body: 'Rs.799 duplicate charge has been reversed to your account.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
      direction: SmsTransactionDirection.credit,
    ),
    explanation:
        'A merchant-side duplicate-charge reversal — real inverse money movement.',
  ),
  const SmsTestCase(
    id: 'p5-reversal-merchant-cancellation-01',
    sender: 'VM-ICICIB',
    body: 'Rs.2,500 has been reversed as the merchant cancelled your order.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
    ),
    explanation: 'Order-cancellation reversal.',
  ),
  const SmsTestCase(
    id: 'p5-reversal-wallet-topup-01',
    sender: 'VK-PAYTM',
    body: 'Rs.100 wallet top-up has been reversed due to a technical issue.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.reversal,
      transactionStatus: TransactionStatus.reversed,
    ),
    explanation: 'A wallet top-up reversal.',
  ),

  // --- EMI / loans (5) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-emi-reminder-01',
    sender: 'VM-HDFCBK',
    body:
        'Your EMI of Rs.5,000 is due tomorrow and will be debited. Please ensure sufficient balance.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'EMI reminder — nothing has been debited yet.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-emi-scheduled-01',
    sender: 'VM-HDFCBK',
    body:
        'Your EMI of Rs.5,000 will be debited on 05-08-26 as per standing instruction.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation:
        'EMI scheduled for a future date — future tense, not completed.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-emi-successful-01',
    sender: 'VM-HDFCBK',
    body: 'EMI of Rs.5,000 debited successfully.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.loanEmi,
      transactionStatus: TransactionStatus.success,
    ),
    explanation:
        'Completed EMI debit — contrast with the reminder/scheduled cases above, same amount shape, opposite verdict.',
  ),
  const SmsTestCase(
    id: 'p5-emi-failed-01',
    sender: 'VM-HDFCBK',
    body:
        'Your EMI payment of Rs.5,000 has failed due to insufficient balance.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: 'A failed EMI attempt never implies money moved.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-loan-disbursement-not-salary-01',
    sender: 'VM-HDFCBK',
    body: 'Loan amount of Rs.50,000 credited to your account XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      direction: SmsTransactionDirection.credit,
      eventType: FinancialEventType.receipt,
    ),
    explanation:
        'PART 9 GUARD: a loan disbursement credit must never resolve to FinancialEventType.salary — it correctly falls through to the generic bankCredit->receipt mapping today (guessCategory only assigns salaryCredit for the literal word "salary", which never appears here). Documented rather than given its own dedicated event type this phase (see the Phase 5 report\'s scoping notes).',
  ),

  // --- Subscriptions (3) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-subscription-renewal-reminder-01',
    sender: 'VK-PAYTM',
    body:
        'Your Netflix subscription renews tomorrow for Rs.499. Amount debited will reflect in your next statement.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation:
        'FIXED (Phase 5 Part 8): ReminderSignals now recognizes subscription-renewal wording ("subscription renews") as an upcoming-obligation signal in its own right, not just future-tense debit verbs.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-subscription-payment-successful-01',
    sender: 'VK-PAYTM',
    body: 'Your subscription payment of Rs.499 was successful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    explanation:
        'Contrast case: a completed subscription payment, not a renewal notice.',
  ),
  const SmsTestCase(
    id: 'p5-subscription-autopay-standing-instruction-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs.999 will be auto-debited tomorrow as per your standing instruction for Amazon Prime membership.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation:
        'Standing-instruction auto-debit notice for a membership renewal — future tense.',
    isDangerousIfMisclassified: true,
  ),

  // --- Merchant / provider ambiguity, unknown VPAs (5) --------------------
  const SmsTestCase(
    id: 'p5-merchant-ambiguous-short-name-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.500 debited from a/c XX1234 to JIO on 15-07-26.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Jio',
      merchantType: MerchantType.business,
    ),
    explanation: 'A short, all-caps brand name resolving via the catalog.',
  ),
  const SmsTestCase(
    id: 'p5-provider-ambiguous-cred-vs-merchant-01',
    sender: 'VK-CREDAP',
    body:
        'Rs.15,000 paid using CRED towards your credit card bill. Payment successful.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      eventType: FinancialEventType.creditCardBill,
      role: FinancialEventRole.linkedSettlement,
      paymentProvider: PaymentProvider.cred,
    ),
    explanation:
        'CRED as the provider for a credit-card bill payment — not a merchant.',
  ),
  const SmsTestCase(
    id: 'p5-unknown-vpa-numeric-handle-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.650 paid to 99887@ybl via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: '99887@ybl',
      merchantTypeIsNull: true,
      paymentProvider: PaymentProvider.phonePe,
    ),
    explanation:
        'An uncatalogued numeric VPA — stays raw, never invented; @ybl is still a weak PhonePe hint.',
  ),
  const SmsTestCase(
    id: 'p5-unknown-vpa-mixed-case-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.410 paid to XyZ99@Oksbi via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'XyZ99@Oksbi',
      merchantTypeIsNull: true,
    ),
    explanation: 'Mixed-case uncatalogued VPA — preserved verbatim.',
  ),
  const SmsTestCase(
    id: 'p5-merchant-vs-provider-both-catalog-shaped-01',
    sender: 'AD-AMAZNP',
    body: 'Paid Rs.900 using Amazon Pay to flipkart@icici via UPI.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      merchantEquals: 'Flipkart',
      paymentProvider: PaymentProvider.amazonPay,
    ),
    explanation:
        'Both merchant (Flipkart) and provider (Amazon Pay) are catalog/provider-shaped names — must never be swapped.',
  ),

  // --- Compound messages (3) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-compound-debit-and-balance-01',
    sender: 'VM-HDFCBK',
    body:
        'Rs.750 debited from a/c XX1234 to Swiggy on 15-07-26. Avl Bal Rs.12,340.50.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      amount: 750.0,
      merchantContains: 'Swiggy',
    ),
    explanation:
        'A trailing available-balance clause must not be mistaken for the transacted amount.',
  ),
  const SmsTestCase(
    id: 'p5-compound-two-amounts-emi-and-fee-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.5,000 EMI debited. A penalty may apply if unpaid next month.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      amount: 5000.0,
      eventType: FinancialEventType.loanEmi,
    ),
    explanation:
        'The primary transacted EMI amount wins over a conditional future late-fee figure mentioned afterward.',
  ),
  const SmsTestCase(
    id: 'p5-compound-refund-and-new-charge-01',
    sender: 'VM-ICICIB',
    body:
        'Rs.500 refunded for cancelled item. A new charge of Rs.500 has been applied for the replacement order.',
    expected: ExpectedFinancialClassification(shouldParse: true),
    explanation:
        'KNOWN LIMITATION: a compound message describing both a refund AND a fresh charge in one SMS has no single correct moneyMovement/eventType verdict from this system\'s per-message model — only parseability is asserted; resolving this properly would need multi-event extraction from one SMS, out of scope this phase.',
  ),

  // --- Reminders, varied wording (4) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-reminder-utility-bill-01',
    sender: 'VM-HDFCBK',
    body:
        'Your electricity bill of Rs.1,850 will be auto-debited on 20-07-26. Pay before due date to avoid disconnection.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation:
        'Utility bill reminder with a disconnection warning — still just a reminder.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-reminder-insurance-premium-01',
    sender: 'VK-AXISBK',
    body:
        'Your insurance premium of Rs.12,000 will be debited this week. Kindly pay to continue your policy.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'Insurance premium reminder.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-reminder-rent-autopay-upcoming-01',
    sender: 'VM-HDFCBK',
    body: 'Rs.25,000 rent will be auto-debited on 01-08-26 from a/c XX1234.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation: 'Upcoming rent auto-debit — future scheduled, not completed.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-reminder-mobile-recharge-upcoming-01',
    sender: 'VK-JIOIO',
    body:
        'Your Jio plan of Rs.299 will be auto-debited tomorrow. Recharge now to avoid service interruption.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
    ),
    explanation:
        'Upcoming recharge auto-debit reminder — despite mentioning "recharge now" imperatively.',
    isDangerousIfMisclassified: true,
  ),

  // --- Failed / pending, varied wording (4) --------------------------------------------------------
  const SmsTestCase(
    id: 'p5-failed-neft-wrong-details-01',
    sender: 'VM-HDFCBK',
    body:
        'Your NEFT transfer of Rs.10,000 has failed due to incorrect beneficiary details.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: 'NEFT failure — never implies money moved.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-pending-imps-processing-01',
    sender: 'VK-AXISBK',
    body:
        'Your IMPS transfer of Rs.7,500 is pending. It will reflect once processed.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.pending,
    ),
    explanation: 'Pending IMPS transfer.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-failed-wallet-topup-01',
    sender: 'VK-PAYTM',
    body: 'Your wallet top-up of Rs.500 was unsuccessful. Please try again.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    explanation: 'Failed wallet top-up.',
    isDangerousIfMisclassified: true,
  ),
  const SmsTestCase(
    id: 'p5-successful-contrast-bill-payment-01',
    sender: 'VM-SBIBNK',
    body: 'Rs.1,850 electricity bill payment successful. Ref REF556677889900.',
    expected: ExpectedFinancialClassification(
      shouldParse: true,
      moneyMovement: true,
      eventType: FinancialEventType.billPayment,
      transactionStatus: TransactionStatus.success,
    ),
    explanation: 'Contrast case: a genuinely completed bill payment.',
  ),
];

/// Ids evaluated by the category-testing bespoke group — the own-account
/// bespoke group needs these three specifically (see
/// sms_corpus_evaluation_test.dart).
final List<String> phase5OwnAccountTransferIds = [
  'p5-imps-self-transfer-different-bank-01',
];
