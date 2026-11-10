/// What a financial SMS actually describes, decided by `SmsCandidateVerifier`
/// from the whole message. This is the single answer to "did money move,
/// and how?" that both Android and FlowFi Web act on — serialized by its
/// Dart `.name` into the cloud candidate's `eventClass` field and mirrored
/// one-for-one by the web's `SmsCandidateEventClass`.
///
/// Spec names (2026-11 detection plan) → value:
/// ACTUAL_CREDIT → [actualCredit], ACTUAL_DEBIT → [actualDebit],
/// SCHEDULED_CREDIT → [scheduledCredit], SCHEDULED_DEBIT → [scheduledDebit],
/// CREDIT_CARD_PURCHASE → [creditCardPurchase], CREDIT_CARD_REFUND →
/// [creditCardRefund], CARD_BILL_PAYMENT → [cardBillPayment], EMI_REMINDER →
/// [emiReminder], EMI_DEBITED → [emiDebited], FAILED_TRANSACTION →
/// [failedTransaction], (added) PENDING → [pendingTransaction], REVERSAL →
/// [reversal], BALANCE_ALERT → [balanceAlert], THIRD_PARTY_EVENT →
/// [thirdPartyEvent], INFORMATIONAL → [informational], UNKNOWN → [unknown].
enum SmsEventClass {
  actualCredit,
  actualDebit,
  scheduledCredit,
  scheduledDebit,
  creditCardPurchase,
  creditCardRefund,
  cardBillPayment,
  emiReminder,
  emiDebited,
  failedTransaction,
  pendingTransaction,
  reversal,
  balanceAlert,
  thirdPartyEvent,
  informational,
  unknown,
}

extension SmsEventClassX on SmsEventClass {
  static SmsEventClass? fromName(String? name) {
    if (name == null) return null;
    for (final value in SmsEventClass.values) {
      if (value.name == name) return value;
    }
    // A value from a newer app version: the conservative reading.
    return SmsEventClass.unknown;
  }

  /// Money actually moved, so importing it may change a balance (after the
  /// other checks pass). Everything else — reminders, scheduled, failed,
  /// pending, balance alerts, third-party, informational, unknown — must
  /// never affect a balance.
  bool get movesMoney => switch (this) {
    SmsEventClass.actualCredit ||
    SmsEventClass.actualDebit ||
    SmsEventClass.creditCardPurchase ||
    SmsEventClass.creditCardRefund ||
    SmsEventClass.cardBillPayment ||
    SmsEventClass.emiDebited ||
    SmsEventClass.reversal => true,
    _ => false,
  };

  /// A money-moving class that needs no extra look on its own account. The
  /// others (refunds, reversals, card bill payments — usually linked to an
  /// earlier transaction or a transfer between the user's own accounts)
  /// always go to individual review.
  bool get isRoutine => switch (this) {
    SmsEventClass.actualCredit ||
    SmsEventClass.actualDebit ||
    SmsEventClass.creditCardPurchase ||
    SmsEventClass.emiDebited => true,
    _ => false,
  };

  /// Shown verbatim as a review reason.
  String get reviewReason => switch (this) {
    SmsEventClass.actualCredit || SmsEventClass.actualDebit => '',
    SmsEventClass.creditCardPurchase => '',
    SmsEventClass.emiDebited => '',
    SmsEventClass.scheduledCredit =>
      'Scheduled credit — the money has not arrived yet.',
    SmsEventClass.scheduledDebit =>
      'Scheduled or due payment — no money has moved yet.',
    SmsEventClass.emiReminder => 'EMI reminder — not a payment.',
    SmsEventClass.failedTransaction => 'Failed transaction — no money moved.',
    SmsEventClass.pendingTransaction =>
      'Pending transaction — not completed yet.',
    SmsEventClass.balanceAlert => 'Balance or limit alert — not a transaction.',
    SmsEventClass.thirdPartyEvent =>
      "Describes someone else's account or a request — not your transaction.",
    SmsEventClass.informational => 'Informational message — no money moved.',
    SmsEventClass.unknown =>
      "Couldn't confirm that money moved, or in which direction.",
    SmsEventClass.creditCardRefund =>
      'Credit card refund — check it against the original purchase.',
    SmsEventClass.cardBillPayment =>
      'Credit card bill payment — a transfer between your own accounts; check it is not counted twice.',
    SmsEventClass.reversal =>
      'Reversal — check it against the original transaction.',
  };
}

/// Whether the transaction is provably the user's. Receiving the SMS while
/// signed in is NOT proof (that only decides which account uploads it); the
/// one reliable signal is the message's last-4 resolving to exactly one of
/// the user's own registered accounts/cards.
enum SmsOwnership { verified, unverified }

/// Where `transactionDate` came from.
enum SmsDateSource { messageBody, messageReceived }
