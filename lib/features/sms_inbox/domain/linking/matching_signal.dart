/// One category of evidence [EventRelationshipEngine] can find between two
/// events — Part 3's 19-signal list. Several of the task's named signals
/// (UTR, transaction id, UPI reference, VPA, loan/EMI identifier) collapse
/// onto [referenceId] here: `FinancialEvent.referenceNumber` is the single
/// field the existing (owned) extractor already reconciles all of those
/// into, via [ReferenceNormalizer] for comparison — this engine does not
/// re-parse the SMS body to tell them apart, since that would duplicate
/// extraction logic that already exists upstream. Similarly [person]
/// collapses onto [merchant] (`FinancialEvent.merchant` represents either).
enum MatchingSignal {
  referenceId,
  utr,
  transactionId,
  upiReference,
  amount,
  merchant,
  person,
  paymentProvider,
  accountOrCard,
  paymentMethod,
  eventType,
  transactionStatus,
  temporalProximity,
  obligationType,
  direction,
  smsSender,
  vpa,
  loanEmiIdentifier,
  creditCardIdentifier,
}

/// One matched signal, its contribution to the raw score, and a
/// human-readable description — always attached to an [EventRelationship]
/// or [EventRelationshipCandidate] verbatim, same transparency convention
/// every other matcher in this feature follows (`TransactionMatchOutcome`,
/// `ObligationLinkOutcome`).
class MatchedSignal {
  const MatchedSignal({
    required this.signal,
    required this.weight,
    required this.description,
  });

  final MatchingSignal signal;
  final double weight;
  final String description;
}
