/// Where a [FinancialEvent] sits in the review pipeline.
enum FinancialEventStatus {
  /// Surfaced in the SMS Inbox review flow, awaiting a manual Convert (or
  /// Ignore) decision — the only status this phase's pipeline ever writes
  /// for a newly-detected event, since automatic transaction creation is not
  /// wired up yet (see `AutomationPolicy`'s doc comment).
  pendingReview,

  /// Reserved for a future phase where a high-confidence event is converted
  /// automatically without a manual Convert step. Never set by this phase's
  /// pipeline.
  autoCreated,

  /// This event was matched as additional evidence for (or a refund/reversal
  /// of) an existing event rather than becoming a new transaction on its own.
  linked,

  ignored,

  /// The event was detected but a required field (amount, or an unresolved
  /// account) is missing enough that even a manual reviewer needs more
  /// context before converting it.
  needsMoreInfo,
}

extension FinancialEventStatusX on FinancialEventStatus {
  static FinancialEventStatus fromName(String? name) {
    if (name == null) return FinancialEventStatus.pendingReview;
    return FinancialEventStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => FinancialEventStatus.pendingReview,
    );
  }
}
