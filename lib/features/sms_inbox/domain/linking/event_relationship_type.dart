/// How a newly-processed [FinancialEvent] relates to something already
/// known — an existing [FinancialEvent] or an outstanding
/// `FinancialObligation` (Phase 4). Deliberately a rich enum, never a
/// boolean `isDuplicate`/`isLinked`: the whole point of Phase 5 is that
/// "related" is not one concept (see Part 2 of the task).
///
/// [EventRelationshipEngine] (event-to-event) produces every value except
/// [paymentFor]/[installmentFor]/[subscriptionFor]/[scheduledFor], which
/// only [ObligationSettlementBridge] (event-to-obligation, wrapping the
/// Phase 4 `ObligationLinker`) produces — a `FinancialEvent` alone has no
/// `ObligationType` to refine those from.
enum EventRelationshipType {
  /// No related event/obligation found — a genuinely new, standalone event.
  newEvent,

  /// The same underlying financial event, reported again with no status
  /// change (e.g. two SMS for the same debit, differently worded).
  duplicate,

  /// The same underlying financial event, but its status changed since the
  /// last observation (generic — see [pendingUpdate]/[failedUpdate] for the
  /// specific transitions those own).
  update,

  /// A generic status-change to pending (first observation that this event
  /// is pending, or a re-confirmation of pending status).
  pendingUpdate,

  /// A status-change to failed.
  failedUpdate,

  /// A completed event resolving an earlier `FinancialEvent` that itself
  /// never represented money movement (a reminder, scheduled notice,
  /// pending, or failed attempt) — mirrors
  /// `FinancialEventMatchResult.resolvesPriorEvent`, but as a first-class
  /// relationship type rather than a single catch-all matcher outcome.
  reminderFor,

  /// Reserved for a future, more specific "resolves an earlier explicitly
  /// scheduled debit" event-to-event relationship. Not produced by
  /// [EventRelationshipEngine] today (that case currently resolves to
  /// [reminderFor], since a raw `FinancialEvent` carries no
  /// due-vs-scheduled distinction — only a `FinancialObligation` does, via
  /// `ObligationType`). [ObligationSettlementBridge] DOES produce this
  /// value, for `ObligationType.upcomingDebit`.
  scheduledFor,

  /// A reversal of a prior charge.
  reversalOf,

  /// A refund of a prior charge.
  refundOf,

  /// A completed payment settling an outstanding `FinancialObligation`
  /// (generic — due payment, bill, credit card due). Produced only by
  /// [ObligationSettlementBridge].
  paymentFor,

  /// A completed payment settling an EMI/loan `FinancialObligation`.
  /// Produced only by [ObligationSettlementBridge].
  installmentFor,

  /// A completed payment settling a subscription-renewal
  /// `FinancialObligation`. Produced only by [ObligationSettlementBridge].
  subscriptionFor,

  /// The debit and credit halves of one transfer between two of the user's
  /// own accounts — see [TransferPairDetector]. Neither half is income or
  /// an expense.
  transferPair,

  /// A meaningful, corroborated relationship that doesn't cleanly fit a
  /// more specific type above — always [EventRelationship.needsReview].
  relatedEvent,

  /// Multiple candidates matched with comparable confidence — never
  /// arbitrarily resolved to one. See [EventRelationship.alternativeCandidates].
  possibleMatch,

  /// Some weak signal was present but not enough to justify even a
  /// [possibleMatch] verdict — recorded for transparency, never acted on.
  unknownRelationship,
}

extension EventRelationshipTypeX on EventRelationshipType {
  static EventRelationshipType fromName(String? name) {
    if (name == null) return EventRelationshipType.unknownRelationship;
    return EventRelationshipType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => EventRelationshipType.unknownRelationship,
    );
  }

  /// Whether this type represents a definite, actionable relationship
  /// (safe to treat as decided) as opposed to something that still needs a
  /// human/automation-policy look — [possibleMatch]/[unknownRelationship]/
  /// [relatedEvent] are never "definite", regardless of confidence.
  bool get isDefinite {
    switch (this) {
      case EventRelationshipType.possibleMatch:
      case EventRelationshipType.unknownRelationship:
      case EventRelationshipType.relatedEvent:
        return false;
      default:
        return true;
    }
  }
}
