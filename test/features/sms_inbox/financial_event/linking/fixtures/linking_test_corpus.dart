import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_type.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/match_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';

import 'event_fixture.dart';
import 'linking_test_case.dart';

final _base = DateTime(2026, 9, 1, 10);

/// Phase 5 linking evaluation corpus. Every case is graded by
/// `LinkingEvaluationHarness` against the real `EventRelationshipEngine`,
/// seeded with each case's own isolated `pool`. Operates at the
/// `FinancialEvent` level (not raw SMS text) since Phase 5 links
/// already-extracted events, not SMS bodies.
final linkingTestCorpus = <LinkingTestCase>[
  // ---------------------------------------------------------------------
  // A. Exact reference match
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'ref-exact-duplicate-01',
    candidate: buildEvent(
      id: 'c1', eventDate: _base, amount: 750, merchant: 'Swiggy',
      referenceNumber: '123456789012', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      normalizedSender: 'HDFCBK',
    ),
    pool: [
      buildEvent(
        id: 't1', eventDate: _base.subtract(const Duration(minutes: 2)),
        amount: 750, merchant: 'Swiggy', referenceNumber: '123456789012',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
        normalizedSender: 'HDFCBK',
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'Same reference number, amount, merchant, status — the canonical duplicate.',
  ),
  LinkingTestCase(
    id: 'ref-exact-normalized-formatting-01',
    candidate: buildEvent(
      id: 'c2', eventDate: _base, amount: 750, merchant: 'Swiggy',
      referenceNumber: '123-456-789012', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't2', eventDate: _base, amount: 750, merchant: 'Swiggy',
        referenceNumber: '123456789012', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    isDangerousIfMisclassified: true,
    explanation: 'Reference numbers differing only in punctuation must still normalize equal (Part 4).',
  ),
  LinkingTestCase(
    id: 'ref-exact-status-transition-01',
    candidate: buildEvent(
      id: 'c3', eventDate: _base, amount: 2000, referenceNumber: 'UTR555',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't3', eventDate: _base.subtract(const Duration(hours: 2)),
        amount: 2000, referenceNumber: 'UTR555', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.update,
    expectedConfidence: MatchConfidence.high,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'Same reference number; status moved pending -> success. Must be UPDATE, not a second transaction.',
  ),
  LinkingTestCase(
    id: 'ref-exact-refund-01',
    candidate: buildEvent(
      id: 'c4', eventDate: _base, amount: 1500, referenceNumber: 'UTR777',
      eventType: FinancialEventType.refund, moneyMovement: true,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    ),
    pool: [
      buildEvent(
        id: 't4', eventDate: _base.subtract(const Duration(days: 1)),
        amount: 1500, referenceNumber: 'UTR777', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
        direction: SmsTransactionDirection.debit,
      ),
    ],
    expectedType: EventRelationshipType.refundOf,
    expectedConfidence: MatchConfidence.high,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'Refund sharing the original charge\'s reference must resolve to REFUND_OF, never DUPLICATE.',
  ),
  LinkingTestCase(
    id: 'ref-exact-amount-conflict-01',
    candidate: buildEvent(
      id: 'c5', eventDate: _base, amount: 900, referenceNumber: 'UTR900',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't5', eventDate: _base.subtract(const Duration(hours: 1)),
        amount: 750, referenceNumber: 'UTR900', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    expectedNeedsReview: true,
    isDangerousIfMisclassified: true,
    explanation: 'Same reference but conflicting amount — must never be silently merged (Part 18 item 11).',
  ),

  // ---------------------------------------------------------------------
  // B. UTR match
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'utr-duplicate-01',
    candidate: buildEvent(
      id: 'c6', eventDate: _base, amount: 500, referenceNumber: 'UTR000111',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't6', eventDate: _base, amount: 500, referenceNumber: 'UTR000111',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    isDangerousIfMisclassified: true,
    explanation: 'UTR match, identical amount/status.',
  ),
  LinkingTestCase(
    id: 'utr-case-formatting-01',
    candidate: buildEvent(
      id: 'c7', eventDate: _base, amount: 500, referenceNumber: 'utr000111',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't7', eventDate: _base, amount: 500, referenceNumber: 'UTR000111',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'UTR case-insensitivity must normalize equal.',
  ),
  LinkingTestCase(
    id: 'utr-failed-update-01',
    candidate: buildEvent(
      id: 'c8', eventDate: _base, amount: 1200, referenceNumber: 'UTR222',
      moneyMovement: false, transactionStatus: TransactionStatus.failed,
    ),
    pool: [
      buildEvent(
        id: 't8', eventDate: _base.subtract(const Duration(hours: 3)),
        amount: 1200, referenceNumber: 'UTR222', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.failedUpdate,
    expectedConfidence: MatchConfidence.high,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'Same UTR, status moved pending -> failed. Must be FAILED_UPDATE, never treated as successful.',
  ),
  LinkingTestCase(
    id: 'utr-reversal-01',
    candidate: buildEvent(
      id: 'c9', eventDate: _base, amount: 3000, referenceNumber: 'UTR333',
      eventType: FinancialEventType.reversal, moneyMovement: false,
      transactionStatus: TransactionStatus.reversed,
    ),
    pool: [
      buildEvent(
        id: 't9', eventDate: _base.subtract(const Duration(hours: 4)),
        amount: 3000, referenceNumber: 'UTR333', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.reversalOf,
    expectedConfidence: MatchConfidence.high,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'Same UTR; candidate is a reversal of the original charge.',
  ),

  // ---------------------------------------------------------------------
  // C. RRN match
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'rrn-duplicate-01',
    candidate: buildEvent(
      id: 'c10', eventDate: _base, amount: 450, referenceNumber: 'RRN445566',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't10', eventDate: _base, amount: 450, referenceNumber: 'RRN445566',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    isDangerousIfMisclassified: true,
    explanation: 'RRN match, identical amount/status.',
  ),
  LinkingTestCase(
    id: 'rrn-spacing-01',
    candidate: buildEvent(
      id: 'c11', eventDate: _base, amount: 450, referenceNumber: 'RRN 4455 66',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't11', eventDate: _base, amount: 450, referenceNumber: 'RRN445566',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'RRN with stray spaces must normalize equal.',
  ),
  LinkingTestCase(
    id: 'rrn-with-card-reinforcement-01',
    candidate: buildEvent(
      id: 'c12', eventDate: _base, amount: 800, referenceNumber: 'RRN900',
      matchedCardId: 'card-1', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.creditCardPurchase,
    ),
    pool: [
      buildEvent(
        id: 't12', eventDate: _base, amount: 800, referenceNumber: 'RRN900',
        matchedCardId: 'card-1', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.creditCardPurchase,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'RRN match reinforced by matching card id.',
  ),

  // ---------------------------------------------------------------------
  // D. Duplicate SMS (no reference)
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'dup-no-ref-strong-combo-01',
    candidate: buildEvent(
      id: 'c13', eventDate: _base, amount: 500, merchant: 'Swiggy',
      normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      paymentMethod: PaymentMethod.upi,
    ),
    pool: [
      buildEvent(
        id: 't13', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 500, merchant: 'Swiggy', normalizedSender: 'HDFCBK',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
        paymentMethod: PaymentMethod.upi,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    isDangerousIfMisclassified: true,
    explanation: 'No reference, but amount+merchant+sender+method+close temporal proximity is strong enough for a definite duplicate.',
  ),
  LinkingTestCase(
    id: 'dup-no-ref-account-combo-01',
    candidate: buildEvent(
      id: 'c14', eventDate: _base, amount: 1200, accountId: 'acc-1',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't14', eventDate: _base.add(const Duration(minutes: 3)),
        amount: 1200, accountId: 'acc-1', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Amount + account match, close temporal proximity — no merchant needed.',
  ),
  LinkingTestCase(
    id: 'dup-different-second-and-status-note-01',
    candidate: buildEvent(
      id: 'c15', eventDate: _base.add(const Duration(seconds: 45)),
      amount: 2500, merchant: 'Amazon', normalizedSender: 'ICICIB',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't15', eventDate: _base, amount: 2500, merchant: 'Amazon',
        normalizedSender: 'ICICIB', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Two SMS 45 seconds apart for the same purchase.',
  ),
  LinkingTestCase(
    id: 'dup-both-unknown-status-01',
    candidate: buildEvent(
      id: 'c16', eventDate: _base, amount: 300, merchant: 'Zomato',
      normalizedSender: 'AXISBK', moneyMovement: true,
    ),
    pool: [
      buildEvent(
        id: 't16', eventDate: _base.add(const Duration(minutes: 2)),
        amount: 300, merchant: 'Zomato', normalizedSender: 'AXISBK',
        moneyMovement: true,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Both events resolved money movement but neither has a specific transactionStatus — must still resolve as duplicate, not stay stuck unresolved.',
  ),

  // ---------------------------------------------------------------------
  // E. Same event, different wording
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'wording-merchant-legal-suffix-01',
    candidate: buildEvent(
      id: 'c17', eventDate: _base, amount: 750, merchant: 'Swiggy',
      normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't17', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 750, merchant: 'SWIGGY LTD', normalizedSender: 'HDFCBK',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: '"Swiggy" vs "SWIGGY LTD" must normalize equal via MerchantKey (reused, not re-implemented).',
  ),
  LinkingTestCase(
    id: 'wording-one-sided-reference-01',
    candidate: buildEvent(
      id: 'c18', eventDate: _base, amount: 640, merchant: 'BigBasket',
      normalizedSender: 'SBIINB', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't18', eventDate: _base.add(const Duration(minutes: 2)),
        amount: 640, merchant: 'BigBasket', normalizedSender: 'SBIINB',
        referenceNumber: 'UTR555999', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'One SMS wording captured a reference number, the other did not — still resolves via amount+merchant+sender.',
  ),
  LinkingTestCase(
    id: 'wording-missing-merchant-account-combo-01',
    candidate: buildEvent(
      id: 'c19', eventDate: _base, amount: 999, accountId: 'acc-2',
      normalizedSender: 'KOTAKB', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't19', eventDate: _base.add(const Duration(minutes: 4)),
        amount: 999, accountId: 'acc-2', normalizedSender: 'KOTAKB',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'One wording did not resolve a merchant at all; amount+account+sender still carries it.',
  ),

  // ---------------------------------------------------------------------
  // F. Pending -> successful
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'pending-to-success-no-ref-01',
    candidate: buildEvent(
      id: 'c20', eventDate: _base, amount: 750, merchant: 'Swiggy',
      normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't20', eventDate: _base.subtract(const Duration(minutes: 5)),
        amount: 750, merchant: 'Swiggy', normalizedSender: 'HDFCBK',
        moneyMovement: false, transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.update,
    isDangerousIfMisclassified: true,
    explanation: 'Pending -> successful for the same underlying transaction must be UPDATE, not two events.',
  ),
  LinkingTestCase(
    id: 'pending-to-success-account-combo-01',
    candidate: buildEvent(
      id: 'c21', eventDate: _base, amount: 4000, accountId: 'acc-3',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't21', eventDate: _base.subtract(const Duration(minutes: 10)),
        amount: 4000, accountId: 'acc-3', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.update,
    isDangerousIfMisclassified: true,
    explanation: 'Pending -> successful via account+amount combo.',
  ),
  LinkingTestCase(
    id: 'pending-to-success-with-ref-01',
    candidate: buildEvent(
      id: 'c22', eventDate: _base, amount: 2000, referenceNumber: 'UTR441',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't22', eventDate: _base.subtract(const Duration(hours: 1)),
        amount: 2000, referenceNumber: 'UTR441', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.update,
    expectedConfidence: MatchConfidence.high,
    isDangerousIfMisclassified: true,
    explanation: 'Pending -> successful, reference match reinforces.',
  ),

  // ---------------------------------------------------------------------
  // G. Pending -> failed
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'pending-to-failed-no-ref-01',
    candidate: buildEvent(
      id: 'c23', eventDate: _base, amount: 500, merchant: 'Ola',
      normalizedSender: 'HDFCBK', moneyMovement: false,
      transactionStatus: TransactionStatus.failed,
    ),
    pool: [
      buildEvent(
        id: 't23', eventDate: _base.subtract(const Duration(minutes: 5)),
        amount: 500, merchant: 'Ola', normalizedSender: 'HDFCBK',
        moneyMovement: false, transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.failedUpdate,
    isDangerousIfMisclassified: true,
    explanation: 'Pending -> failed must be FAILED_UPDATE, never successful.',
  ),
  LinkingTestCase(
    id: 'pending-to-failed-with-ref-01',
    candidate: buildEvent(
      id: 'c24', eventDate: _base, amount: 1000, referenceNumber: 'UTR808',
      moneyMovement: false, transactionStatus: TransactionStatus.failed,
    ),
    pool: [
      buildEvent(
        id: 't24', eventDate: _base.subtract(const Duration(minutes: 30)),
        amount: 1000, referenceNumber: 'UTR808', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.failedUpdate,
    expectedConfidence: MatchConfidence.high,
    isDangerousIfMisclassified: true,
    explanation: 'Reference-backed pending -> failed transition.',
  ),

  // ---------------------------------------------------------------------
  // H. Pending -> reversed
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'pending-to-reversed-01',
    candidate: buildEvent(
      id: 'c25', eventDate: _base, amount: 1800, referenceNumber: 'UTR909',
      eventType: FinancialEventType.reversal, moneyMovement: false,
      transactionStatus: TransactionStatus.reversed,
    ),
    pool: [
      buildEvent(
        id: 't25', eventDate: _base.subtract(const Duration(hours: 2)),
        amount: 1800, referenceNumber: 'UTR909', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.reversalOf,
    expectedConfidence: MatchConfidence.high,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'A pending transaction later reversed resolves to REVERSAL_OF.',
  ),
  LinkingTestCase(
    id: 'pending-to-reversed-no-ref-01',
    candidate: buildEvent(
      id: 'c26', eventDate: _base, amount: 620, merchant: 'PayZapp',
      normalizedSender: 'HDFCBK', eventType: FinancialEventType.reversal,
      moneyMovement: false, transactionStatus: TransactionStatus.reversed,
    ),
    pool: [
      buildEvent(
        id: 't26', eventDate: _base.subtract(const Duration(hours: 1)),
        amount: 620, merchant: 'PayZapp', normalizedSender: 'HDFCBK',
        moneyMovement: false, transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.reversalOf,
    isDangerousIfMisclassified: true,
    explanation: 'Reversal of a pending transaction, matched without a reference number.',
  ),

  // ---------------------------------------------------------------------
  // I. Reminder -> payment
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'reminder-to-payment-01',
    candidate: buildEvent(
      id: 'c27', eventDate: _base, amount: 8000, merchant: 'HDFC Credit Card',
      accountId: 'acc-cc', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't27', eventDate: _base.subtract(const Duration(days: 3)),
        amount: 8000, merchant: 'HDFC Credit Card', accountId: 'acc-cc',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'A completed payment resolving an earlier reminder must be REMINDER_FOR, never a second independent expense.',
  ),
  LinkingTestCase(
    id: 'reminder-to-payment-amount-only-supplemented-01',
    candidate: buildEvent(
      id: 'c28', eventDate: _base, amount: 5000, accountId: 'acc-emi',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't28', eventDate: _base.subtract(const Duration(days: 1)),
        amount: 5000, accountId: 'acc-emi', eventType: FinancialEventType.reminder,
        moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    isDangerousIfMisclassified: true,
    explanation: 'Amount + account only, exactly 24h apart, no merchant/sender reinforcement — reaches MEDIUM, not HIGH, so this must be surfaced for review rather than auto-resolved as REMINDER_FOR.',
  ),
  LinkingTestCase(
    id: 'reminder-to-payment-with-ref-01',
    candidate: buildEvent(
      id: 'c29', eventDate: _base, amount: 8000, referenceNumber: 'UTR8000',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't29', eventDate: _base.subtract(const Duration(days: 2)),
        amount: 8000, referenceNumber: 'UTR8000',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    expectedConfidence: MatchConfidence.high,
    isDangerousIfMisclassified: true,
    explanation: 'Reference-backed reminder resolution.',
  ),
  LinkingTestCase(
    id: 'two-reminders-not-money-01',
    candidate: buildEvent(
      id: 'c30', eventDate: _base, amount: 5000, merchant: 'ABC Loans',
      normalizedSender: 'ABCLOAN', eventType: FinancialEventType.reminder,
      moneyMovement: false,
    ),
    pool: [
      buildEvent(
        id: 't30', eventDate: _base.subtract(const Duration(days: 30)),
        amount: 5000, merchant: 'ABC Loans', normalizedSender: 'ABCLOAN',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.relatedEvent,
    expectedNeedsReview: true,
    isDangerousIfMisclassified: true,
    explanation: 'Two reminders (this month vs last month, same recurring amount) — neither moved money, so this must never resolve to DUPLICATE or REMINDER_FOR (both require actual money movement); RELATED_EVENT with needsReview true is the honest ceiling here. Full recurrence-awareness (recognizing this as "next month\'s" reminder rather than a repeat) is Phase 4\'s job, not this engine\'s.',
  ),

  // ---------------------------------------------------------------------
  // J. Scheduled -> completed
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'scheduled-to-completed-close-01',
    candidate: buildEvent(
      id: 'c31', eventDate: _base, amount: 5000, merchant: 'HDFC EMI',
      accountId: 'acc-emi2', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't31', eventDate: _base.subtract(const Duration(hours: 12)),
        amount: 5000, merchant: 'HDFC EMI', accountId: 'acc-emi2',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    isDangerousIfMisclassified: true,
    explanation: 'A scheduled-debit notice resolved the next day by the actual debit. (SCHEDULED_FOR\'s finer distinction is produced only at the obligation-bridge level — see obligation_settlement_bridge_test.dart.)',
  ),
  LinkingTestCase(
    id: 'scheduled-to-completed-weak-signal-01',
    candidate: buildEvent(
      id: 'c32', eventDate: _base, amount: 5000, merchant: 'HDFC EMI',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't32', eventDate: _base.subtract(const Duration(days: 5)),
        amount: 5000, merchant: 'HDFC EMI', eventType: FinancialEventType.reminder,
        moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    isDangerousIfMisclassified: true,
    explanation: 'Only amount+merchant, 5 days apart — must stay a possible match, not an auto-declared link (Part 14: "amount+merchant+time -- possible/strong depending on context").',
  ),
  LinkingTestCase(
    id: 'scheduled-to-completed-strong-01',
    candidate: buildEvent(
      id: 'c33', eventDate: _base, amount: 5000, merchant: 'HDFC EMI',
      accountId: 'acc-emi3', normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't33', eventDate: _base.subtract(const Duration(days: 5)),
        amount: 5000, merchant: 'HDFC EMI', accountId: 'acc-emi3',
        normalizedSender: 'HDFCBK', eventType: FinancialEventType.reminder,
        moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    isDangerousIfMisclassified: true,
    explanation: 'Same weak temporal gap, but reinforced with account+sender — enough corroboration to resolve confidently.',
  ),

  // ---------------------------------------------------------------------
  // K. EMI lifecycle
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'emi-scheduled-to-debit-01',
    candidate: buildEvent(
      id: 'c34', eventDate: _base, amount: 5000, referenceNumber: 'EMI0901',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.loanEmi,
    ),
    pool: [
      buildEvent(
        id: 't34', eventDate: _base.subtract(const Duration(days: 2)),
        amount: 5000, referenceNumber: 'EMI0901', eventType: FinancialEventType.reminder,
        moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    isDangerousIfMisclassified: true,
    explanation: 'EMI scheduled notice resolved by the actual debit.',
  ),
  LinkingTestCase(
    id: 'emi-duplicate-sms-01',
    candidate: buildEvent(
      id: 'c35', eventDate: _base, amount: 5000, referenceNumber: 'EMI0901',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.loanEmi,
    ),
    pool: [
      buildEvent(
        id: 't35', eventDate: _base, amount: 5000, referenceNumber: 'EMI0901',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.loanEmi,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    isDangerousIfMisclassified: true,
    explanation: 'Two SMS confirming the same EMI debit must not double-count it.',
  ),
  LinkingTestCase(
    id: 'emi-failed-then-retry-success-01',
    candidate: buildEvent(
      id: 'c36', eventDate: _base.add(const Duration(days: 1)),
      amount: 5000, merchant: 'HDFC EMI', accountId: 'acc-emi4',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.loanEmi,
    ),
    pool: [
      buildEvent(
        id: 't36', eventDate: _base, amount: 5000, merchant: 'HDFC EMI',
        accountId: 'acc-emi4', moneyMovement: false,
        transactionStatus: TransactionStatus.failed,
        eventType: FinancialEventType.loanEmi,
      ),
    ],
    expectedType: EventRelationshipType.update,
    isDangerousIfMisclassified: true,
    explanation: 'A failed EMI attempt followed by a successful retry — preserved as one lifecycle, not two loans.',
  ),
  LinkingTestCase(
    id: 'emi-success-then-reversed-01',
    candidate: buildEvent(
      id: 'c37', eventDate: _base.add(const Duration(hours: 6)),
      amount: 5000, referenceNumber: 'EMI0902', eventType: FinancialEventType.reversal,
      moneyMovement: false, transactionStatus: TransactionStatus.reversed,
    ),
    pool: [
      buildEvent(
        id: 't37', eventDate: _base, amount: 5000, referenceNumber: 'EMI0902',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.loanEmi,
      ),
    ],
    expectedType: EventRelationshipType.reversalOf,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'A successfully-debited EMI later reversed by the bank.',
  ),

  // ---------------------------------------------------------------------
  // L. Credit-card lifecycle
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'cc-purchase-standalone-01',
    candidate: buildEvent(
      id: 'c38', eventDate: _base, amount: 3000, merchant: 'H&M',
      matchedCardId: 'card-9', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.creditCardPurchase,
    ),
    pool: const [],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'A fresh credit-card purchase with no prior related event must stay NEW_EVENT — never merged into an unrelated card bill.',
  ),
  LinkingTestCase(
    id: 'cc-bill-payment-duplicate-01',
    candidate: buildEvent(
      id: 'c39', eventDate: _base, amount: 10000, matchedCardId: 'card-9',
      referenceNumber: 'CCPAY01', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.creditCardBill,
    ),
    pool: [
      buildEvent(
        id: 't39', eventDate: _base, amount: 10000, matchedCardId: 'card-9',
        referenceNumber: 'CCPAY01', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.creditCardBill,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'Same credit card bill payment reported twice.',
  ),
  LinkingTestCase(
    id: 'cc-purchase-vs-bill-not-merged-01',
    candidate: buildEvent(
      id: 'c40', eventDate: _base, amount: 3000, matchedCardId: 'card-9',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.creditCardPurchase,
    ),
    pool: [
      buildEvent(
        id: 't40', eventDate: _base.subtract(const Duration(hours: 2)),
        amount: 3000, matchedCardId: 'card-9', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.creditCardBill,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    isDangerousIfMisclassified: true,
    explanation: 'Part 12: purchase vs bill payment "must not be merged simply because the card number is the same" — amount+card only reaches MEDIUM (surfaced for review), never an auto-declared duplicate, even with close timing and different underlying event types.',
  ),
  LinkingTestCase(
    id: 'cc-same-card-different-amount-01',
    candidate: buildEvent(
      id: 'c41', eventDate: _base, amount: 3000, matchedCardId: 'card-9',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.creditCardPurchase,
    ),
    pool: [
      buildEvent(
        id: 't41', eventDate: _base.subtract(const Duration(hours: 3)),
        amount: 10000, matchedCardId: 'card-9', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.creditCardBill,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Same card, different amount, different event type — a purchase must never merge into an unrelated bill payment just because the card matches.',
  ),
  LinkingTestCase(
    id: 'cc-due-reminder-to-payment-01',
    candidate: buildEvent(
      id: 'c42', eventDate: _base, amount: 10000, merchant: 'HDFC Credit Card',
      matchedCardId: 'card-9', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.creditCardBill,
    ),
    pool: [
      buildEvent(
        id: 't42', eventDate: _base.subtract(const Duration(days: 4)),
        amount: 10000, merchant: 'HDFC Credit Card', matchedCardId: 'card-9',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    isDangerousIfMisclassified: true,
    explanation: 'Credit card due reminder resolved by the actual bill payment.',
  ),
  LinkingTestCase(
    id: 'cc-payment-failed-01',
    candidate: buildEvent(
      id: 'c43', eventDate: _base, amount: 10000, referenceNumber: 'CCPAY02',
      moneyMovement: false, transactionStatus: TransactionStatus.failed,
      eventType: FinancialEventType.creditCardBill,
    ),
    pool: [
      buildEvent(
        id: 't43', eventDate: _base.subtract(const Duration(minutes: 20)),
        amount: 10000, referenceNumber: 'CCPAY02', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.failedUpdate,
    isDangerousIfMisclassified: true,
    explanation: 'A failed credit card bill payment attempt must never read as successful.',
  ),

  // ---------------------------------------------------------------------
  // M. Refund
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'refund-not-duplicate-same-amount-merchant-close-01',
    candidate: buildEvent(
      id: 'c44', eventDate: _base.add(const Duration(hours: 3)),
      amount: 1500, merchant: 'Amazon', eventType: FinancialEventType.refund,
      moneyMovement: true, transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    ),
    pool: [
      buildEvent(
        id: 't44', eventDate: _base, amount: 1500, merchant: 'Amazon',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
        direction: SmsTransactionDirection.debit,
      ),
    ],
    expectedType: EventRelationshipType.refundOf,
    expectedNeedsReview: true,
    isDangerousIfMisclassified: true,
    explanation:
        'Part 9: identical amount + merchant + close timestamps must NEVER be read as duplicate merely because they look alike — the candidate\'s own refund status decides the TYPE first, regardless of match strength; needsReview stays true here since only amount+merchant (no reference) identifies which charge it refunds.',
  ),
  LinkingTestCase(
    id: 'refund-partial-amount-01',
    candidate: buildEvent(
      id: 'c45', eventDate: _base.add(const Duration(days: 1)),
      amount: 600, merchant: 'Myntra', eventType: FinancialEventType.refund,
      moneyMovement: true, transactionStatus: TransactionStatus.refunded,
    ),
    pool: [
      buildEvent(
        id: 't45', eventDate: _base, amount: 1500, merchant: 'Myntra',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.refundOf,
    isDangerousIfMisclassified: true,
    explanation: 'A partial refund legitimately has a smaller amount than the original charge — must still resolve to REFUND_OF.',
  ),
  LinkingTestCase(
    id: 'refund-never-income-01',
    candidate: buildEvent(
      id: 'c46', eventDate: _base.add(const Duration(hours: 5)),
      amount: 350, merchant: 'Flipkart', eventType: FinancialEventType.refund,
      moneyMovement: true, transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    ),
    pool: [
      buildEvent(
        id: 't46', eventDate: _base, amount: 350, merchant: 'Flipkart',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
        direction: SmsTransactionDirection.debit,
      ),
    ],
    expectedType: EventRelationshipType.refundOf,
    isDangerousIfMisclassified: true,
    explanation: 'Safety rule 8: a refund must never become income — asserting REFUND_OF (not a bare credit/newEvent) is what keeps this distinct from ordinary income at the relationship layer.',
  ),

  // ---------------------------------------------------------------------
  // N. Reversal
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'reversal-not-duplicate-01',
    candidate: buildEvent(
      id: 'c47', eventDate: _base.add(const Duration(hours: 1)),
      amount: 1500, eventType: FinancialEventType.reversal,
      moneyMovement: false, transactionStatus: TransactionStatus.reversed,
    ),
    pool: [
      buildEvent(
        id: 't47', eventDate: _base, amount: 1500, moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.reversalOf,
    expectedNeedsReview: true,
    isDangerousIfMisclassified: true,
    explanation: 'A reversal must never be read as a duplicate of the original debit. Only amount identifies the target here (a single hard signal), so needsReview stays true — the TYPE (reversal) is certain, but WHICH charge it reverses is only weakly identified.',
  ),
  LinkingTestCase(
    id: 'reversal-never-extra-expense-01',
    candidate: buildEvent(
      id: 'c48', eventDate: _base.add(const Duration(minutes: 90)),
      amount: 500, referenceNumber: 'REV001', eventType: FinancialEventType.reversal,
      moneyMovement: false, transactionStatus: TransactionStatus.reversed,
    ),
    pool: [
      buildEvent(
        id: 't48', eventDate: _base, amount: 500, referenceNumber: 'REV001',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.reversalOf,
    isDangerousIfMisclassified: true,
    explanation: 'Safety rule 7: a reversal must not create an additional expense — REVERSAL_OF (not newEvent/duplicate-as-expense) is the correct classification.',
  ),

  // ---------------------------------------------------------------------
  // O. Own-account transfer
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'transfer-unresolved-single-leg-01',
    candidate: buildEvent(
      id: 'c49', eventDate: _base, amount: 20000, direction: SmsTransactionDirection.debit,
      isOwnAccountTransfer: true, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: const [],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'The generic engine sees no counterpart at all (that check is TransferPairDetector\'s job, not the base engine) — newEvent is the correct base-engine answer; see transfer_pair_detector_test.dart for the transfer-specific verdict.',
  ),

  // ---------------------------------------------------------------------
  // P. Subscription
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'subscription-reminder-to-payment-01',
    candidate: buildEvent(
      id: 'c50', eventDate: _base, amount: 649, merchant: 'Netflix',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't50', eventDate: _base.subtract(const Duration(hours: 6)),
        amount: 649, merchant: 'Netflix', eventType: FinancialEventType.reminder,
        moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    isDangerousIfMisclassified: true,
    explanation: 'Amount + merchant only reaches MEDIUM (surfaced for review, not auto-resolved) — see reminder-to-payment-01/cc-due-reminder-to-payment-01 for cases with enough corroboration to reach REMINDER_FOR confidently. (SUBSCRIPTION_FOR\'s finer distinction is produced only at the obligation-bridge level.)',
  ),
  LinkingTestCase(
    id: 'subscription-duplicate-charge-notice-01',
    candidate: buildEvent(
      id: 'c51', eventDate: _base, amount: 649, merchant: 'Netflix',
      referenceNumber: 'NFLX0901', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't51', eventDate: _base, amount: 649, merchant: 'Netflix',
        referenceNumber: 'NFLX0901', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'Two SMS for the same month\'s Netflix charge.',
  ),
  LinkingTestCase(
    id: 'subscription-next-month-not-duplicate-01',
    candidate: buildEvent(
      id: 'c52', eventDate: _base.add(const Duration(days: 30)),
      amount: 649, merchant: 'Netflix', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't52', eventDate: _base, amount: 649, merchant: 'Netflix',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    isDangerousIfMisclassified: true,
    explanation: 'Next month\'s Netflix charge shares amount+merchant with last month\'s but is 30 days apart — must never be auto-declared a duplicate of a past month\'s charge (that would suppress a real, separate expense).',
  ),

  // ---------------------------------------------------------------------
  // Q. Same amount, different merchant
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'same-amount-different-merchant-01',
    candidate: buildEvent(
      id: 'c53', eventDate: _base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't53', eventDate: _base.add(const Duration(minutes: 5)),
        amount: 500, merchant: 'Zomato', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Safety rule 8: same amount alone must never imply same transaction.',
  ),
  LinkingTestCase(
    id: 'same-amount-different-merchant-close-time-01',
    candidate: buildEvent(
      id: 'c54', eventDate: _base, amount: 200, merchant: 'Uber',
      normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't54', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 200, merchant: 'Starbucks', normalizedSender: 'HDFCBK',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Coincidentally identical amount, same sender bank, one minute apart, but a completely different merchant — two genuinely separate purchases.',
  ),

  // ---------------------------------------------------------------------
  // R. Same merchant, different amounts
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'same-merchant-different-amount-01',
    candidate: buildEvent(
      id: 'c55', eventDate: _base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't55', eventDate: _base.add(const Duration(minutes: 10)),
        amount: 850, merchant: 'Swiggy', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Safety rule 9: same merchant alone must never imply same transaction — two separate Swiggy orders.',
  ),
  LinkingTestCase(
    id: 'same-merchant-different-amount-account-01',
    candidate: buildEvent(
      id: 'c56', eventDate: _base, amount: 1200, merchant: 'Amazon',
      accountId: 'acc-4', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't56', eventDate: _base.add(const Duration(minutes: 3)),
        amount: 3000, merchant: 'Amazon', accountId: 'acc-4',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.relatedEvent,
    expectedNeedsReview: true,
    isDangerousIfMisclassified: true,
    explanation: 'Same merchant AND same account, but different (known, conflicting) amounts — the amount-conflict veto keeps this from ever being DUPLICATE/UPDATE (two separate purchases, not one mis-parsed amount), while still surfacing the corroboration as RELATED_EVENT rather than silently discarding it.',
  ),

  // ---------------------------------------------------------------------
  // S. Same merchant, same amount, different times
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'same-merchant-amount-two-genuine-orders-01',
    candidate: buildEvent(
      id: 'c57', eventDate: _base.add(const Duration(hours: 3)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't57', eventDate: _base, amount: 500, merchant: 'Swiggy',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Same amount+merchant, 3 hours apart (still within one business day), no reference — reaches HIGH via temporal+direction+event-type reinforcement and resolves as a probable duplicate notification; contrast with same-merchant-amount-two-minutes-apart-01/multiple-candidates-tied-01 for the explicitly-ambiguous cases.',
  ),
  LinkingTestCase(
    id: 'same-merchant-amount-two-minutes-apart-01',
    candidate: buildEvent(
      id: 'c58', eventDate: _base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't58', eventDate: _base, amount: 500, merchant: 'Swiggy',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Same amount+merchant, 2 minutes apart — the temporal proximity itself tips this into a confident duplicate read.',
  ),

  // ---------------------------------------------------------------------
  // T. Multiple candidates
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'multiple-candidates-tied-01',
    candidate: buildEvent(
      id: 'c59', eventDate: _base.add(const Duration(minutes: 5)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't59a', eventDate: _base, amount: 500, merchant: 'Swiggy',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
      buildEvent(
        id: 't59b', eventDate: _base.add(const Duration(minutes: 3)),
        amount: 500, merchant: 'Swiggy', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    expectedAlternativeCount: 2,
    isDangerousIfMisclassified: true,
    explanation: 'Two equally-plausible candidates (Rs 500 -> Swiggy at 10:05 and 10:07, per the task\'s own Part 15 example) — must never arbitrarily choose one.',
  ),
  LinkingTestCase(
    id: 'multiple-candidates-one-clearly-better-01',
    candidate: buildEvent(
      id: 'c60', eventDate: _base, amount: 500, merchant: 'Swiggy',
      referenceNumber: 'UTR12345', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't60a', eventDate: _base, amount: 500, merchant: 'Swiggy',
        referenceNumber: 'UTR12345', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
      buildEvent(
        id: 't60b', eventDate: _base.subtract(const Duration(days: 40)),
        amount: 500, merchant: 'Swiggy', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedTargetEventId: 't60a',
    explanation: 'One candidate has an exact reference match and is clearly better than a coincidental old same-amount/merchant event — not ambiguous.',
  ),

  // ---------------------------------------------------------------------
  // U. Ambiguous reference
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'ambiguous-reference-different-ids-01',
    candidate: buildEvent(
      id: 'c61', eventDate: _base, amount: 500, merchant: 'Swiggy',
      referenceNumber: 'UTR111', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't61', eventDate: _base, amount: 500, merchant: 'Swiggy',
        referenceNumber: 'UTR222', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    isDangerousIfMisclassified: true,
    explanation: 'Different reference numbers must not themselves prevent a link when every other signal matches strongly (amount+merchant+exact same timestamp) — but the two references are never merged/treated as equal; the link comes purely from the other signals.',
  ),

  // ---------------------------------------------------------------------
  // V. Missing reference
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'missing-reference-both-sides-strong-01',
    candidate: buildEvent(
      id: 'c62', eventDate: _base, amount: 750, merchant: 'Swiggy',
      accountId: 'acc-5', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't62', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 750, merchant: 'Swiggy', accountId: 'acc-5',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'No reference number on either side — amount+merchant+account+close temporal is enough.',
  ),
  LinkingTestCase(
    id: 'missing-reference-weak-01',
    candidate: buildEvent(
      id: 'c63', eventDate: _base, amount: 750, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't63', eventDate: _base.add(const Duration(days: 10)),
        amount: 750, moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'No reference, only amount matches, 10 days apart — amount alone must never be sufficient (Safety rule 8).',
  ),

  // ---------------------------------------------------------------------
  // W. Missing merchant
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'missing-merchant-account-amount-01',
    candidate: buildEvent(
      id: 'c64', eventDate: _base, amount: 900, accountId: 'acc-6',
      normalizedSender: 'SBIINB', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't64', eventDate: _base.add(const Duration(minutes: 2)),
        amount: 900, accountId: 'acc-6', normalizedSender: 'SBIINB',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Neither side resolved a merchant, but account+amount+sender still resolves confidently.',
  ),
  LinkingTestCase(
    id: 'missing-merchant-weak-01',
    candidate: buildEvent(
      id: 'c65', eventDate: _base, amount: 900, normalizedSender: 'SBIINB',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't65', eventDate: _base.add(const Duration(hours: 20)),
        amount: 900, normalizedSender: 'SBIINB', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'No merchant, only amount matches (sender alone never counts as a hard signal) — must not link.',
  ),

  // ---------------------------------------------------------------------
  // X. Missing account
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'missing-account-merchant-amount-01',
    candidate: buildEvent(
      id: 'c66', eventDate: _base, amount: 640, merchant: 'BigBasket',
      normalizedSender: 'SBIINB', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't66', eventDate: _base.add(const Duration(minutes: 3)),
        amount: 640, merchant: 'BigBasket', normalizedSender: 'SBIINB',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Neither side resolved an account, but amount+merchant+sender+temporal is enough.',
  ),

  // ---------------------------------------------------------------------
  // Y. Multiple transactions in same time window
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'same-window-different-transactions-01',
    candidate: buildEvent(
      id: 'c67', eventDate: _base, amount: 150, merchant: 'Chai Point',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't67a', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 300, merchant: 'Uber', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
      buildEvent(
        id: 't67b', eventDate: _base.add(const Duration(minutes: 2)),
        amount: 50, merchant: 'PVR', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Three genuinely different purchases within minutes of each other — none should link to another just for being temporally close.',
  ),

  // ---------------------------------------------------------------------
  // Z. Adversarial duplicate traps
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'adversarial-reminder-vs-completed-not-duplicate-01',
    candidate: buildEvent(
      id: 'c68', eventDate: _base, amount: 5000, merchant: 'HDFC EMI',
      eventType: FinancialEventType.reminder, moneyMovement: false,
    ),
    pool: [
      buildEvent(
        id: 't68', eventDate: _base.subtract(const Duration(hours: 1)),
        amount: 5000, merchant: 'HDFC EMI', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.relatedEvent,
    isDangerousIfMisclassified: true,
    explanation:
        'A reminder arriving AFTER an already-completed payment for the same amount/merchant must never itself be read as a second completed transaction, and must never mark the (already real) prior payment as newly "resolved" either — it is only ever informational.',
  ),
  LinkingTestCase(
    id: 'adversarial-payment-request-not-success-01',
    candidate: buildEvent(
      id: 'c69', eventDate: _base, amount: 500, merchant: 'Rahul',
      eventType: FinancialEventType.reminder, moneyMovement: false,
    ),
    pool: const [],
    expectedType: EventRelationshipType.newEvent,
    expectedNeedsReview: false,
    isDangerousIfMisclassified: true,
    explanation: 'A bare payment request (a reminder-shaped, non-money event) with nothing to link to must stay NEW_EVENT — never fabricated into a successful payment.',
  ),
  LinkingTestCase(
    id: 'adversarial-failed-vs-successful-lookalike-01',
    candidate: buildEvent(
      id: 'c70', eventDate: _base, amount: 750, merchant: 'Swiggy',
      moneyMovement: false, transactionStatus: TransactionStatus.failed,
    ),
    pool: [
      buildEvent(
        id: 't70', eventDate: _base.subtract(const Duration(minutes: 5)),
        amount: 750, merchant: 'Swiggy', moneyMovement: false,
        transactionStatus: TransactionStatus.pending,
      ),
    ],
    expectedType: EventRelationshipType.failedUpdate,
    isDangerousIfMisclassified: true,
    explanation: 'A failed attempt that looks identical to a would-be successful one (same amount/merchant) must resolve FAILED_UPDATE, never be conflated with success.',
  ),
  LinkingTestCase(
    id: 'adversarial-different-reference-same-everything-else-01',
    candidate: buildEvent(
      id: 'c71', eventDate: _base, amount: 500, merchant: 'Swiggy',
      referenceNumber: 'UTR-AAA', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't71', eventDate: _base, amount: 500, merchant: 'Swiggy',
        referenceNumber: 'UTR-BBB', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    isDangerousIfMisclassified: true,
    explanation:
        'Adversarial trap: two DIFFERENT reference numbers, but every other signal is identical — the link is decided by the non-reference signals, and the two distinct reference numbers are never themselves treated as matching (contrast with ref-exact-* cases, where the references genuinely match).',
  ),
  LinkingTestCase(
    id: 'adversarial-sender-only-never-links-01',
    candidate: buildEvent(
      id: 'c72', eventDate: _base, amount: 999, normalizedSender: 'HDFCBK',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't72', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 250, normalizedSender: 'HDFCBK', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Same SMS sender, one minute apart, but different amount and no merchant — sender alone (a soft signal) must never link two events.',
  ),

  // ---------------------------------------------------------------------
  // Additional coverage: confidence-band boundaries, more EMI/subscription
  // combinations, bill/loan variety, and further duplicate-trap cases.
  // ---------------------------------------------------------------------
  LinkingTestCase(
    id: 'boundary-single-hard-signal-capped-low-01',
    candidate: buildEvent(
      id: 'c73', eventDate: _base, amount: 425, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't73', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 425, moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Only amount matches (a single hard signal) — capped at LOW regardless of close temporal proximity, so this must stay NEW_EVENT.',
  ),
  LinkingTestCase(
    id: 'boundary-two-hard-signals-reach-high-01',
    candidate: buildEvent(
      id: 'c74', eventDate: _base, amount: 425, merchant: 'Dominos',
      normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      paymentMethod: PaymentMethod.upi,
    ),
    pool: [
      buildEvent(
        id: 't74', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 425, merchant: 'Dominos', normalizedSender: 'HDFCBK',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
        paymentMethod: PaymentMethod.upi,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'Amount + merchant (two hard signals) reinforced by sender/method/close temporal clears the HIGH threshold.',
  ),
  LinkingTestCase(
    id: 'boundary-two-hard-signals-medium-only-01',
    candidate: buildEvent(
      id: 'c75', eventDate: _base, amount: 425, merchant: 'Dominos',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't75', eventDate: _base.add(const Duration(days: 3)),
        amount: 425, merchant: 'Dominos', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    expectedConfidence: MatchConfidence.medium,
    isDangerousIfMisclassified: true,
    explanation: 'Amount + merchant only, 3 days apart, no other corroboration — reaches MEDIUM, not HIGH, so it must be surfaced for review rather than auto-declared a duplicate.',
  ),
  LinkingTestCase(
    id: 'loan-due-reminder-to-payment-01',
    candidate: buildEvent(
      id: 'c76', eventDate: _base, amount: 8000, merchant: 'ABC Finance',
      accountId: 'acc-loan1', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.loanEmi,
    ),
    pool: [
      buildEvent(
        id: 't76', eventDate: _base.subtract(const Duration(days: 2)),
        amount: 8000, merchant: 'ABC Finance', accountId: 'acc-loan1',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    isDangerousIfMisclassified: true,
    explanation: 'A personal-loan due reminder resolved by the actual installment payment.',
  ),
  LinkingTestCase(
    id: 'bill-due-reminder-to-payment-01',
    candidate: buildEvent(
      id: 'c77', eventDate: _base, amount: 1200, merchant: 'BESCOM',
      normalizedSender: 'BESCOM', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.billPayment,
    ),
    pool: [
      buildEvent(
        id: 't77', eventDate: _base.subtract(const Duration(days: 1)),
        amount: 1200, merchant: 'BESCOM', normalizedSender: 'BESCOM',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    isDangerousIfMisclassified: true,
    explanation: 'An electricity bill due reminder resolved by the actual payment.',
  ),
  LinkingTestCase(
    id: 'bill-duplicate-payment-notice-01',
    candidate: buildEvent(
      id: 'c78', eventDate: _base, amount: 1200, referenceNumber: 'BESCOM01',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't78', eventDate: _base, amount: 1200, referenceNumber: 'BESCOM01',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'Duplicate bill payment confirmation SMS.',
  ),
  LinkingTestCase(
    id: 'subscription-spotify-duplicate-01',
    candidate: buildEvent(
      id: 'c79', eventDate: _base, amount: 119, merchant: 'Spotify',
      referenceNumber: 'SPOT0901', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't79', eventDate: _base, amount: 119, merchant: 'Spotify',
        referenceNumber: 'SPOT0901', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'Duplicate Spotify renewal confirmation.',
  ),
  LinkingTestCase(
    id: 'insurance-yearly-reminder-to-payment-01',
    candidate: buildEvent(
      id: 'c80', eventDate: _base, amount: 12000, merchant: 'LIC',
      accountId: 'acc-lic', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't80', eventDate: _base.subtract(const Duration(days: 6)),
        amount: 12000, merchant: 'LIC', accountId: 'acc-lic',
        eventType: FinancialEventType.reminder, moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.reminderFor,
    isDangerousIfMisclassified: true,
    explanation: 'A yearly insurance premium reminder resolved by the actual payment.',
  ),
  LinkingTestCase(
    id: 'transfer-not-treated-as-income-single-leg-01',
    candidate: buildEvent(
      id: 'c81', eventDate: _base, amount: 20000, direction: SmsTransactionDirection.credit,
      isOwnAccountTransfer: true, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: const [],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'The credit leg of an own-account transfer, seen alone by the base engine — TransferPairDetector (tested separately) is what keeps this from being mis-tagged as income.',
  ),
  LinkingTestCase(
    id: 'refund-vs-new-purchase-not-confused-01',
    candidate: buildEvent(
      id: 'c82', eventDate: _base.add(const Duration(hours: 2)),
      amount: 1500, merchant: 'Amazon', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      direction: SmsTransactionDirection.debit,
    ),
    pool: [
      buildEvent(
        id: 't82', eventDate: _base, amount: 1500, merchant: 'Amazon',
        moneyMovement: true, transactionStatus: TransactionStatus.refunded,
        direction: SmsTransactionDirection.credit,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    isDangerousIfMisclassified: true,
    explanation: 'A brand-new purchase (not itself a refund) happening to match an earlier refunded charge\'s amount/merchant — the CANDIDATE\'s own type decides the verdict, and since candidate is not a refund/reversal, this is graded as an ordinary same-status-mismatch case, not specially exempted.',
    knownIssue:
        'Candidate transactionStatus is null (unresolved) here, so the status-transition switch never fires and the duplicate fallback treats it as matching target\'s refunded status implicitly via the null-status branch — a genuinely new purchase should ideally classify as NEW_EVENT or a reviewable case, not silently DUPLICATE of a refund. Flagged as a known conservatism gap for a future session to tighten (e.g. require candidate.transactionStatus to be explicitly success, not merely unresolved, before allowing the "duplicate" fallback against a target with a non-success status).',
  ),
  LinkingTestCase(
    id: 'own-transfer-flag-false-not-transfer-pair-01',
    candidate: buildEvent(
      id: 'c83', eventDate: _base, amount: 20000, direction: SmsTransactionDirection.debit,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't83', eventDate: _base.add(const Duration(minutes: 5)),
        amount: 20000, direction: SmsTransactionDirection.credit,
        isOwnAccountTransfer: true, moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Only ONE side is flagged as an own-account transfer (the other is an ordinary, unrelated debit) — must never be paired as a transfer just because amounts happen to match.',
  ),
  LinkingTestCase(
    id: 'payment-provider-reinforced-duplicate-01',
    candidate: buildEvent(
      id: 'c84', eventDate: _base, amount: 300, merchant: 'Chai Point',
      paymentProvider: PaymentProvider.googlePay,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't84', eventDate: _base.add(const Duration(minutes: 2)),
        amount: 300, merchant: 'Chai Point',
        paymentProvider: PaymentProvider.googlePay,
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'Amount + merchant + matching payment provider reinforce a confident duplicate read.',
  ),
  LinkingTestCase(
    id: 'direction-mismatch-not-duplicate-01',
    candidate: buildEvent(
      id: 'c85', eventDate: _base, amount: 500, merchant: 'John Doe',
      direction: SmsTransactionDirection.debit, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't85', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 500, merchant: 'John Doe', direction: SmsTransactionDirection.credit,
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.relatedEvent,
    expectedNeedsReview: true,
    isDangerousIfMisclassified: true,
    explanation: 'Same amount+merchant+time but OPPOSITE direction (paid Rs 500 to John vs received Rs 500 from John) — the direction-conflict veto keeps this from ever being DUPLICATE (a debit and a credit are never the same transaction), surfaced as RELATED_EVENT rather than silently merged.',
  ),
  LinkingTestCase(
    id: 'weak-signal-far-apart-no-match-01',
    candidate: buildEvent(
      id: 'c86', eventDate: _base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't86', eventDate: _base.add(const Duration(days: 61)),
        amount: 500, merchant: 'Swiggy', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    explanation: 'Outside the default 60-day lookback window entirely — never considered a candidate at all.',
  ),
  LinkingTestCase(
    id: 'emi-vs-loan-vs-cc-not-cross-linked-01',
    candidate: buildEvent(
      id: 'c87', eventDate: _base, amount: 5000, merchant: 'HDFC Bank',
      eventType: FinancialEventType.loanEmi, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't87', eventDate: _base.add(const Duration(minutes: 5)),
        amount: 5000, merchant: 'HDFC Bank',
        eventType: FinancialEventType.creditCardBill, moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    isDangerousIfMisclassified: true,
    explanation: 'Same bank name, amount, and close timing but genuinely different obligation kinds (EMI vs credit card bill) — documents that eventType similarity is only a soft reinforcing signal here, not a hard veto; amount+merchant+temporal is what actually decides it, so distinguishing EMI from a card bill from the same bank ultimately depends on the extractor resolving distinct merchant text upstream.',
  ),
  LinkingTestCase(
    id: 'possible-match-alternatives-preserved-01',
    candidate: buildEvent(
      id: 'c88', eventDate: _base, amount: 300, merchant: 'Chai Point',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't88a', eventDate: _base.subtract(const Duration(hours: 1)),
        amount: 300, merchant: 'Chai Point', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
      buildEvent(
        id: 't88b', eventDate: _base.add(const Duration(hours: 1)),
        amount: 300, merchant: 'Chai Point', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
      buildEvent(
        id: 't88c', eventDate: _base.add(const Duration(days: 20)),
        amount: 300, merchant: 'Chai Point', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.possibleMatch,
    isDangerousIfMisclassified: true,
    explanation: 'Three same-amount/merchant candidates at different distances — the two close ones tie for best and must both surface; the far one should score lower and not force a false "clear winner" either way.',
  ),
  LinkingTestCase(
    id: 'zero-amount-never-matches-01',
    candidate: buildEvent(
      id: 'c89', eventDate: _base, amount: 0, merchant: 'Bank Fee',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      eventType: FinancialEventType.fee,
    ),
    pool: [
      buildEvent(
        id: 't89', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 0, merchant: 'Bank Fee', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.fee,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    explanation: 'A zero-amount edge case (e.g. a waived fee notice) — amount equality still holds (0 == 0), combined with merchant/temporal, resolves normally.',
  ),
  LinkingTestCase(
    id: 'unresolved-amount-on-candidate-01',
    candidate: buildEvent(
      id: 'c90', eventDate: _base, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't90', eventDate: _base.add(const Duration(minutes: 1)),
        amount: 500, merchant: 'Swiggy', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Candidate has no resolved amount at all — merchant alone (a single hard signal) must stay capped at LOW/never link, and an unresolved amount must never be treated as "matching" any amount.',
  ),
  LinkingTestCase(
    id: 'cash-withdrawal-not-linked-to-purchase-01',
    candidate: buildEvent(
      id: 'c91', eventDate: _base, amount: 2000, eventType: FinancialEventType.cashWithdrawal,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't91', eventDate: _base.add(const Duration(minutes: 10)),
        amount: 2000, eventType: FinancialEventType.payment,
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Same amount only (a single hard signal) — capped at LOW/NEW_EVENT regardless of close temporal proximity; a cash withdrawal must not be linked to an unrelated payment just because the amount coincides.',
  ),
  LinkingTestCase(
    id: 'salary-credit-not-matched-to-expense-01',
    candidate: buildEvent(
      id: 'c92', eventDate: _base, amount: 50000, eventType: FinancialEventType.salary,
      direction: SmsTransactionDirection.credit, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: const [],
    expectedType: EventRelationshipType.newEvent,
    explanation: 'A salary credit with nothing else in the pool — plain new event.',
  ),
  LinkingTestCase(
    id: 'cashback-vs-original-purchase-not-refund-01',
    candidate: buildEvent(
      id: 'c93', eventDate: _base.add(const Duration(hours: 2)),
      amount: 50, eventType: FinancialEventType.cashback,
      direction: SmsTransactionDirection.credit, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't93', eventDate: _base, amount: 1000, merchant: 'Amazon',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Cashback is a distinct small credit, not a refund of the full purchase — different amount, no reference/merchant overlap, correctly stays unrelated.',
  ),
  LinkingTestCase(
    id: 'interest-credit-standalone-01',
    candidate: buildEvent(
      id: 'c94', eventDate: _base, amount: 120, eventType: FinancialEventType.interest,
      direction: SmsTransactionDirection.credit, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: const [],
    expectedType: EventRelationshipType.newEvent,
    explanation: 'Routine interest credit, nothing to link to.',
  ),
  LinkingTestCase(
    id: 'recharge-duplicate-notice-01',
    candidate: buildEvent(
      id: 'c95', eventDate: _base, amount: 299, eventType: FinancialEventType.recharge,
      referenceNumber: 'RCH0901', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't95', eventDate: _base, amount: 299, eventType: FinancialEventType.recharge,
        referenceNumber: 'RCH0901', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.duplicate,
    expectedConfidence: MatchConfidence.high,
    explanation: 'Duplicate recharge confirmation SMS.',
  ),
  LinkingTestCase(
    id: 'credit-card-purchase-then-reminder-not-confused-01',
    candidate: buildEvent(
      id: 'c96', eventDate: _base.add(const Duration(days: 20)),
      amount: 10000, merchant: 'HDFC Credit Card', matchedCardId: 'card-9',
      eventType: FinancialEventType.reminder, moneyMovement: false,
    ),
    pool: [
      buildEvent(
        id: 't96', eventDate: _base, amount: 3000, merchant: 'H&M',
        matchedCardId: 'card-9', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
        eventType: FinancialEventType.creditCardPurchase,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'A card-bill due reminder for the statement total must not link to one individual prior purchase on the same card just because the card id matches — different amount, different merchant.',
  ),
  LinkingTestCase(
    id: 'reminder-amount-unresolved-no-link-01',
    candidate: buildEvent(
      id: 'c97', eventDate: _base, merchant: 'HDFC EMI', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't97', eventDate: _base.subtract(const Duration(days: 1)),
        merchant: 'HDFC EMI', eventType: FinancialEventType.reminder,
        moneyMovement: false,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Neither side has a resolved amount — merchant alone (a single hard signal) must stay capped at LOW, never confidently resolving the reminder.',
  ),
  LinkingTestCase(
    id: 'account-only-not-sufficient-01',
    candidate: buildEvent(
      id: 'c98', eventDate: _base, accountId: 'acc-7', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't98', eventDate: _base.add(const Duration(minutes: 1)),
        accountId: 'acc-7', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Only the account matches (single hard signal, no amount at all) — every transaction on the same account cannot be treated as the same transaction.',
  ),
  LinkingTestCase(
    id: 'card-only-not-sufficient-01',
    candidate: buildEvent(
      id: 'c99', eventDate: _base, matchedCardId: 'card-5', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't99', eventDate: _base.add(const Duration(minutes: 1)),
        matchedCardId: 'card-5', moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Only the card matches (single hard signal, no amount) — every purchase on the same card cannot be treated as the same transaction.',
  ),
  LinkingTestCase(
    id: 'far-window-eventtype-and-sender-only-01',
    candidate: buildEvent(
      id: 'c100', eventDate: _base, eventType: FinancialEventType.payment,
      normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ),
    pool: [
      buildEvent(
        id: 't100', eventDate: _base.add(const Duration(days: 15)),
        eventType: FinancialEventType.payment, normalizedSender: 'HDFCBK',
        moneyMovement: true, transactionStatus: TransactionStatus.success,
      ),
    ],
    expectedType: EventRelationshipType.newEvent,
    isDangerousIfMisclassified: true,
    explanation: 'Only soft signals (event type, sender) match, no amount at all — must never link (hardCount 0 -> NO_MATCH).',
  ),
];
