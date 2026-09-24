/// Why one [smsItemId] was linked to [financialEventId] — see
/// `TransactionMatcher`. Never a flat "duplicate of" chain (that's what
/// orphaned duplicates when the row it points at is deleted); the event row
/// is the anchor, and every contributing SMS points at it independently.
enum FinancialEventLinkType {
  /// This SMS is what the event was first built from.
  newEvent,

  /// A second (or later) SMS describing the same real-world event (e.g. a
  /// bank alert and a UPI app notification both texting about one payment).
  additionalEvidence,

  refundOf,

  reversalOf,

  /// A weak-signal match (same sender/amount/day, no reference number to
  /// confirm) — always surfaced for manual review, never silently merged.
  possibleDuplicate,
}

extension FinancialEventLinkTypeX on FinancialEventLinkType {
  static FinancialEventLinkType fromName(String? name) {
    if (name == null) return FinancialEventLinkType.newEvent;
    return FinancialEventLinkType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => FinancialEventLinkType.newEvent,
    );
  }
}

/// One SMS's contribution to a [FinancialEvent] — see `financial_event.dart`
/// and the `sms_financial_event_links` table. Deleting the [smsItemId] row
/// only removes this one link; every other SMS linked to [financialEventId]
/// (and the event itself) is unaffected, which is what structurally fixes
/// the old flat `duplicate_of_id` chain's orphaning problem.
class FinancialEventEvidenceLink {
  const FinancialEventEvidenceLink({
    required this.id,
    required this.financialEventId,
    required this.smsItemId,
    required this.linkType,
    required this.confidence,
    required this.linkedAt,
  });

  final String id;
  final String financialEventId;
  final String smsItemId;
  final FinancialEventLinkType linkType;

  /// 0.0-1.0 — how confident `TransactionMatcher` was in this specific link
  /// (a reference-number match is near 1.0; a weak sender/amount/day match
  /// is lower).
  final double confidence;

  final DateTime linkedAt;
}
