import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_semantic_bucket.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_type.dart';

import 'obligation_test_case.dart';

/// Phase 4 obligation evaluation corpus. Every case is graded by
/// `ObligationEvaluationHarness` against the real `ObligationClassifier` /
/// `ObligationBuilder`. Cases marked `isDangerousIfMisclassified: true` are
/// the safety-critical ones enumerated in the task: money-shaped language
/// ("debited", "credited", "payment") that must never be read as a
/// completed transaction when it describes an obligation, and vice versa.
///
/// Reference date for every case (unless overridden): Tue 1 Sep 2026, 10:00
/// — see `ObligationEvaluationHarness._defaultReceivedAt`.
final obligationTestCorpus = <ObligationTestCase>[
  // ---------------------------------------------------------------------
  // A. EMI reminders
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'emi-future-tense-01',
    body: 'Your EMI of Rs 5,000 will be debited tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Classic future-tense EMI notice — contains "debited" but money has not moved yet.',
  ),
  const ObligationTestCase(
    id: 'emi-due-date-01',
    body: 'Your EMI of Rs 12,000 is due on 5th September.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateEquals: null,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Explicit EMI due-date notice, no money movement.',
  ),
  const ObligationTestCase(
    id: 'emi-reminder-generic-01',
    body: 'Reminder: Your loan EMI payment is pending.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Generic EMI reminder — "EMI" keyword should win over the bare "loan" keyword for subtype.',
  ),
  const ObligationTestCase(
    id: 'emi-completed-not-reminder-01',
    body: 'Your EMI of Rs 5,000 has been debited from account XX1234.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Completed EMI debit — must never be treated as an outstanding obligation.',
  ),
  const ObligationTestCase(
    id: 'emi-multiple-dates-01',
    body:
        'Reminder: Your EMI due on 5 Sep. Last EMI of Rs 5,000 was Rs 5,000 as usual.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'The upcoming due date must be resolved even when an unrelated past amount is also mentioned.',
  ),

  // ---------------------------------------------------------------------
  // B. Loan reminders
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'loan-due-01',
    body: 'Your loan installment of Rs 8,000 is due on 10 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.loanObligation,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Explicit loan due-date notice.',
  ),
  const ObligationTestCase(
    id: 'loan-future-tense-01',
    body: 'Your personal loan payment will be debited on 15 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.loanObligation,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Future-tense loan debit notice.',
  ),
  const ObligationTestCase(
    id: 'loan-reminder-01',
    body: 'Kindly pay your loan installment at the earliest.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.loanObligation,
      isOutstanding: true,
      dueDateIsKnown: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Generic loan reminder with no date at all — the date must stay unknown, never guessed.',
  ),
  const ObligationTestCase(
    id: 'loan-completed-01',
    body: 'Your loan EMI has been successfully paid.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Completed loan payment must not become an obligation.',
  ),

  // ---------------------------------------------------------------------
  // C. Credit-card due reminders
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'cc-due-01',
    body: 'Your HDFC credit card payment of Rs 10,000 is due on 5 Sep 2026.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
      dueDateEquals: null,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Explicit credit card due-date notice with an explicit year.',
  ),
  const ObligationTestCase(
    id: 'cc-reminder-due-01',
    body: 'Payment reminder: Your credit card bill of Rs 4,500 is due.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
      dueDateIsKnown: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Reminder phrasing combined with a bare "is due" marker (no concrete date) — still resolves to the due bucket, with the date honestly left unknown.',
  ),
  const ObligationTestCase(
    id: 'cc-upcoming-01',
    body: 'Your credit card payment of Rs 6,000 will be auto-debited on 8 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Future-tense scheduled credit card auto-debit.',
  ),
  const ObligationTestCase(
    id: 'cc-minimum-due-01',
    body: 'Minimum amount due on your credit card is Rs 2,000, due date 5 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Minimum-amount-due credit card statement notice.',
  ),
  const ObligationTestCase(
    id: 'cc-completed-01',
    body: 'Rs 10,000 paid towards your HDFC credit card successfully.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Completed credit card payment must not become an obligation.',
  ),

  // ---------------------------------------------------------------------
  // D. Bill reminders
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'bill-electricity-due-01',
    body: 'Your electricity bill of Rs 1,200 is due on 7 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.billDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Explicit utility bill due-date notice.',
  ),
  const ObligationTestCase(
    id: 'bill-water-reminder-01',
    body: 'Reminder: Please pay your water bill before it becomes overdue.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.billDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Generic bill reminder with no concrete date.',
  ),
  const ObligationTestCase(
    id: 'bill-broadband-upcoming-01',
    body: 'Your broadband bill will be auto-debited on 12 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.billDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Future-tense scheduled bill auto-debit.',
  ),
  const ObligationTestCase(
    id: 'bill-completed-01',
    body: 'Your electricity bill payment of Rs 1,200 was successful.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Completed bill payment must not become an obligation.',
  ),

  // ---------------------------------------------------------------------
  // E. Subscription reminders
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'sub-netflix-due-01',
    body: 'Your Netflix subscription renewal of Rs 649 is due on 3 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.subscriptionRenewal,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Explicit subscription renewal due-date notice.',
  ),
  const ObligationTestCase(
    id: 'sub-spotify-upcoming-01',
    body: 'Your Spotify subscription will be charged tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.subscriptionRenewal,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Future-tense scheduled subscription charge.',
  ),
  const ObligationTestCase(
    id: 'sub-prime-reminder-01',
    body:
        'Reminder: Your Amazon Prime subscription is expiring soon, renew now.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.subscriptionRenewal,
      isOutstanding: true,
      dueDateIsKnown: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Subscription-expiry reminder with no concrete date — must stay unknown, not guessed.',
  ),
  const ObligationTestCase(
    id: 'sub-completed-01',
    body: 'Rs 649 charged for your Netflix subscription.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'When the pipeline has already confirmed money moved, that hard fact must win over the neutral wording.',
  ),

  // ---------------------------------------------------------------------
  // F. Scheduled debits / standing instructions
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'si-tomorrow-01',
    body: 'Your standing instruction of Rs 3,000 is scheduled for tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.upcomingDebit,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateKind: ObligationDateKindExpectation.scheduledDebitDate,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Standing instruction scheduled for a future date.',
  ),
  const ObligationTestCase(
    id: 'si-within-48h-01',
    body: 'Your account will be auto-debited Rs 1,500 within 48 hours.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateKind: ObligationDateKindExpectation.paymentDeadline,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Relative "within N hours" scheduling window.',
  ),
  const ObligationTestCase(
    id: 'si-scheduled-in-days-01',
    body: 'Your EMI is scheduled to be debited in 3 days.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateKind: ObligationDateKindExpectation.scheduledDebitDate,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Relative "in N days" scheduling window.',
  ),
  const ObligationTestCase(
    id: 'si-completed-01',
    body: 'Rs 3,000 debited via standing instruction.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Completed standing-instruction debit must not become an obligation.',
  ),

  // ---------------------------------------------------------------------
  // G. Payment requests
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'req-please-pay-01',
    body: 'Please pay Rs 2,000 before 10 Sep to avoid late fee.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.paymentReminder,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateKind: ObligationDateKindExpectation.paymentDeadline,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Explicit payment request with a deadline phrased as "before".',
  ),
  const ObligationTestCase(
    id: 'req-kindly-pay-01',
    body:
        'Kindly pay the pending amount of Rs 500 at your earliest convenience.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.paymentReminder,
      isOutstanding: true,
      dueDateIsKnown: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Generic payment request with no date at all.',
  ),
  const ObligationTestCase(
    id: 'req-payment-received-01',
    body: 'Payment of Rs 2,000 received, thank you.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'A confirmed receipt must never be read as a pending request.',
  ),

  // ---------------------------------------------------------------------
  // H. Actual completed transactions (sanity checks)
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'done-debit-01',
    body: 'Rs 500 debited from your account for Swiggy.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'An ordinary completed debit must never spawn an obligation.',
  ),
  const ObligationTestCase(
    id: 'done-credit-01',
    body: 'Rs 15,000 credited to your account as salary.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'An ordinary completed credit must never spawn an obligation.',
  ),
  const ObligationTestCase(
    id: 'done-no-hardfacts-01',
    body: 'Your account was debited Rs 500 for Amazon purchase.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.unknown,
      isOutstanding: false,
    ),
    explanation:
        'Design boundary: with no reconciled transactionStatus/moneyMovement supplied, the classifier '
        'never guesses "completed" from text alone — it can only rule OUT reminder-ness (via the shared '
        'ReminderSignals completion-override check) and lands honestly on "unknown", not "completed".',
  ),
  const ObligationTestCase(
    id: 'done-emi-with-hardfacts-01',
    body: 'Rs 3,200 debited towards your loan EMI.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Completed EMI debit with hard facts supplied must be "completed".',
  ),

  // ---------------------------------------------------------------------
  // I. Pending transactions
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'pending-upi-01',
    body: 'Your UPI payment of Rs 500 is pending confirmation.',
    transactionStatus: TransactionStatus.pending,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.pending,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'A pending transaction is neither completed nor an outstanding obligation.',
  ),
  const ObligationTestCase(
    id: 'pending-zomato-01',
    body: 'Transaction pending: Rs 1,000 to Zomato.',
    transactionStatus: TransactionStatus.pending,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.pending,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'A pending transaction must not be read as completed.',
  ),
  const ObligationTestCase(
    id: 'pending-neft-01',
    body: 'Your NEFT transfer of Rs 10,000 is being processed.',
    transactionStatus: TransactionStatus.pending,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.pending,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'A pending transaction must not be read as an obligation either.',
  ),

  // ---------------------------------------------------------------------
  // J. Failed transactions
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'failed-retry-01',
    body: 'Your payment of Rs 750 has failed. Please retry.',
    transactionStatus: TransactionStatus.failed,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.failed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'A failed transaction must never be read as completed or successful.',
  ),
  const ObligationTestCase(
    id: 'failed-declined-01',
    body: 'UPI transaction declined due to insufficient balance.',
    transactionStatus: TransactionStatus.failed,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.failed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'A declined transaction is a failure, not a reminder.',
  ),
  const ObligationTestCase(
    id: 'failed-emi-01',
    body: 'Your EMI auto-debit attempt failed due to insufficient funds.',
    transactionStatus: TransactionStatus.failed,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.failed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'A failed EMI attempt is not the same as an EMI still being due.',
  ),

  // ---------------------------------------------------------------------
  // K. Reversed transactions
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'reversed-01',
    body: 'Your payment of Rs 2,000 was reversed and credited back.',
    transactionStatus: TransactionStatus.reversed,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reversed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'A reversal must not be read as a new expense or a fresh obligation.',
  ),
  const ObligationTestCase(
    id: 'reversed-02',
    body: 'Transaction reversal: Rs 500 credited back to your account.',
    transactionStatus: TransactionStatus.reversed,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reversed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'A reversal is a resolution, not an obligation.',
  ),

  // ---------------------------------------------------------------------
  // L. Refunds
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'refund-01',
    body: 'Refund of Rs 1,200 credited to your account.',
    transactionStatus: TransactionStatus.refunded,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.refund,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'A refund must never be treated as income or a new obligation.',
  ),
  const ObligationTestCase(
    id: 'refund-02',
    body: 'Amount refunded: Rs 350 for your cancelled order.',
    transactionStatus: TransactionStatus.refunded,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.refund,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'A refund is a resolution, not an obligation.',
  ),

  // ---------------------------------------------------------------------
  // M. Relative dates
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'date-tomorrow-01',
    body: 'Payment due tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateEquals: null,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Bare "tomorrow" must resolve to a concrete date, not the SMS receipt date.',
  ),
  const ObligationTestCase(
    id: 'date-day-after-tomorrow-01',
    body: 'Reminder: Your bill is due day after tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.billDue,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: '"Day after tomorrow" must resolve to receivedAt + 2 days.',
  ),
  const ObligationTestCase(
    id: 'date-next-monday-01',
    body: 'Reminder: Loan EMI due next Monday.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        '"Next Monday" must resolve to a concrete future date — exact weekday arithmetic is covered separately in obligation_date_resolver_test.dart.',
  ),
  const ObligationTestCase(
    id: 'date-due-in-days-01',
    body: 'Reminder: Your credit card bill is due in 5 days.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateEquals: null,
    ),
    isDangerousIfMisclassified: true,
    explanation: '"Due in 5 days" must resolve to receivedAt + 5 days.',
  ),
  const ObligationTestCase(
    id: 'date-within-hours-01',
    body: 'Please pay Rs 800 within 24 hours to avoid late fee.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.paymentReminder,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateKind: ObligationDateKindExpectation.paymentDeadline,
    ),
    isDangerousIfMisclassified: true,
    explanation: '"Within 24 hours" must resolve to receivedAt + 24 hours.',
  ),

  // ---------------------------------------------------------------------
  // N. Absolute dates
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'date-absolute-with-year-01',
    body: 'Your loan EMI of Rs 5,000 is due on 5 September 2026.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Full month name + explicit year must resolve correctly.',
  ),
  const ObligationTestCase(
    id: 'date-absolute-rollover-01',
    receivedAt: null,
    body: 'Your credit card payment is due on 5 Jan.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Year-rollover behavior for a bare day+month is covered precisely in obligation_date_resolver_test.dart; this case only checks the classifier path still resolves a date.',
  ),
  const ObligationTestCase(
    id: 'date-absolute-ordinal-01',
    body: 'Bill payment due on 3rd Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.billDue,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Ordinal suffix ("3rd") must not break date parsing.',
  ),
  const ObligationTestCase(
    id: 'date-absolute-short-month-01',
    body: 'Reminder: EMI due on 10 Oct.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'Abbreviated month name must resolve correctly.',
  ),

  // ---------------------------------------------------------------------
  // O. Multiple dates in one SMS
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'multi-date-due-vs-paid-01',
    body:
        "Reminder: Your EMI due on 5 Sep. Previous EMI amount was Rs 5,000 as usual.",
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'The earlier ("5 Sep") upcoming due date must be picked over an unrelated past amount mention in the same message.',
  ),
  const ObligationTestCase(
    id: 'multi-date-two-obligations-01',
    body: 'Your subscription renews on 5 Sep, and your bill is due on 10 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.subscriptionRenewal,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Two distinct obligations named in one SMS — the resolver must pick the first concrete date rather than failing.',
  ),

  // ---------------------------------------------------------------------
  // P. Multiple amounts in one SMS
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'multi-amount-emi-01',
    body: 'Your EMI of Rs 5,000 (previous: Rs 4,800) is due on 5 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Bucket/type classification must not be confused by a second amount.',
  ),
  const ObligationTestCase(
    id: 'multi-amount-cc-01',
    body:
        'Reminder: Minimum amount due on your credit card is Rs 2,000, out of total outstanding Rs 25,000, due on 5 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Two amounts (minimum vs total) must not confuse the classification.',
  ),

  // ---------------------------------------------------------------------
  // Q. Reminder + previous transaction in same SMS
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'reminder-with-prior-txn-01',
    body:
        'Reminder: Your EMI of Rs 5,000 is due on 5 Sep. Your last EMI amount was Rs 5,000.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'A reminder that also references a past amount (without a past-tense completion verb) must still classify as an outstanding due obligation.',
  ),
  const ObligationTestCase(
    id: 'reminder-with-completion-phrase-known-issue-01',
    body: 'Your EMI due on 5 Sep. Previous EMI was paid on 3 Aug.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.unknown,
      isOutstanding: false,
    ),
    knownIssue:
        'The shared upstream ReminderSignals.looksLikeReminder() (owned by the parallel Phase 2/3 session, not modified here) treats any "was paid/debited/credited" phrase anywhere in the message as a completion marker that overrides reminder detection entirely — so a genuine upcoming due date combined with a mention of a past payment is currently not detected as a reminder at all. Flagging as a known gap for the owning session rather than working around it by touching reminder_signals.dart.',
    explanation:
        'Documents a real limitation inherited from the shared reminder-detection layer — see knownIssue.',
  ),

  // ---------------------------------------------------------------------
  // R. Duplicate reminders
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'dup-reminder-electricity-01',
    body: 'Your electricity bill of Rs 1,200 is due on 7 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.billDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Identical body to bill-electricity-due-01 — classification must be deterministic across repeated observations (dedup itself is handled by the caller via sourceEventIds, not this classifier).',
  ),

  // ---------------------------------------------------------------------
  // S. Reminder followed by actual payment (each message graded individually)
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'seq-reminder-msg-01',
    body: 'Your credit card payment of Rs 8,000 is due on 5 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'First message in a reminder-then-payment sequence — see obligation_linker_test.dart for the resolution half.',
  ),
  const ObligationTestCase(
    id: 'seq-payment-msg-01',
    body: 'Payment of Rs 8,000 made towards your HDFC credit card.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Second message in the sequence — the actual completed payment.',
  ),

  // ---------------------------------------------------------------------
  // T. Same merchant, different obligation types
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'same-merchant-emi-01',
    body: 'HDFC Bank: Your EMI of Rs 5,000 is due on 5 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Obligation type must come from message content, not sender identity.',
  ),
  const ObligationTestCase(
    id: 'same-merchant-cc-01',
    body: 'HDFC Bank: Your credit card payment of Rs 5,000 is due on 5 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Same sender text as same-merchant-emi-01 but a different obligation type, purely from content.',
  ),

  // ---------------------------------------------------------------------
  // U. Adversarial: contains "debited"/"credited"/"due" but no money moved
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'adversarial-will-be-debited-01',
    body: '₹8,500 will be debited towards your EMI tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.emiObligation,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'The task\'s own canonical adversarial example.',
  ),
  const ObligationTestCase(
    id: 'adversarial-is-due-01',
    body: 'Your account balance is low. Card payment is due today.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Contains "payment" and "account" but describes an unpaid due amount, not a transaction.',
  ),
  const ObligationTestCase(
    id: 'adversarial-scheduled-01',
    body:
        'A payment of Rs 2,500 is scheduled for debit on 6 Sep from your account.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Contains "debit" and "account" but is a future-scheduled action.',
  ),
  const ObligationTestCase(
    id: 'adversarial-avoid-late-fee-01',
    body:
        'Avoid late fee — pay your outstanding credit card amount of Rs 3,000 by 5 Sep.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.reminder,
      obligationType: ObligationType.creditCardDue,
      isOutstanding: true,
      dueDateIsKnown: true,
      dueDateKind: ObligationDateKindExpectation.paymentDeadline,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Contains "credit card" and an amount but is purely a pay-by-deadline notice.',
  ),

  // ---------------------------------------------------------------------
  // V. "will be debited" messages
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'will-be-debited-utility-01',
    body: 'Your DTH recharge amount of Rs 300 will be debited tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.upcomingDebit,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Future-tense recharge debit with no specific obligation-subtype keyword.',
  ),

  // ---------------------------------------------------------------------
  // W. "has been debited"/"has been credited" (contrast — must be completed)
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'has-been-debited-01',
    body: 'Rs 5,000 has been debited from your account towards EMI.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Past-tense "has been debited" describes money that already moved.',
  ),
  const ObligationTestCase(
    id: 'has-been-credited-01',
    body: 'Rs 15,000 has been credited to your account.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Past-tense "has been credited" describes money that already moved.',
  ),

  // ---------------------------------------------------------------------
  // X. "payment due" vs "payment made"
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'payment-due-01',
    body: 'Payment due: Rs 1,500 for your gas bill.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      obligationType: ObligationType.billDue,
      isOutstanding: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: '"Payment due" is an obligation, not a transaction.',
  ),
  const ObligationTestCase(
    id: 'payment-made-01',
    body: 'Payment made: Rs 1,500 towards your gas bill.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation: '"Payment made" is a completed transaction.',
  ),

  // ---------------------------------------------------------------------
  // Y. "payment request" vs "payment received"
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'payment-request-01',
    body: 'Payment request of Rs 500 from Rahul via UPI.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.unknown,
      isOutstanding: false,
    ),
    explanation:
        'A bare UPI collect-request notice matches none of the shared ReminderSignals reminder/future-tense patterns, so the classifier honestly reports "unknown" rather than inventing an obligation subtype — modeling UPI collect requests as a first-class obligation type is out of scope for this Phase 4 foundation.',
  ),
  const ObligationTestCase(
    id: 'payment-received-01',
    body: 'Payment received: Rs 500 from Rahul via UPI.',
    transactionStatus: TransactionStatus.success,
    moneyMovement: true,
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.completed,
      isOutstanding: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'Contrast with payment-request-01 — this is a confirmed receipt.',
  ),

  // ---------------------------------------------------------------------
  // Z. Recurring / subscription patterns
  // ---------------------------------------------------------------------
  const ObligationTestCase(
    id: 'recurring-netflix-monthly-01',
    body: 'Your Netflix subscription of Rs 649 will be charged tomorrow.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.upcoming,
      obligationType: ObligationType.subscriptionRenewal,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        'One observation of a monthly subscription charge — recurrence itself must not be inferred from this single message (see obligation_recurrence_test.dart).',
  ),
  const ObligationTestCase(
    id: 'recurring-rent-vague-date-01',
    body:
        'Reminder: Your rent payment of Rs 20,000 is due on 1st of every month.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      isOutstanding: true,
      dueDateIsKnown: false,
    ),
    isDangerousIfMisclassified: true,
    explanation:
        '"1st of every month" names no concrete calendar date — the resolver must not guess one (Safety rule 11).',
  ),
  const ObligationTestCase(
    id: 'recurring-insurance-yearly-01',
    body: 'Your insurance premium of Rs 12,000 is due on 15 Sep 2026.',
    expected: ExpectedObligationClassification(
      bucket: ObligationSemanticBucket.due,
      isOutstanding: true,
      dueDateIsKnown: true,
    ),
    isDangerousIfMisclassified: true,
    explanation: 'A yearly obligation with a concrete resolved date.',
  ),
];
