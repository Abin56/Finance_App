/// What [AutomationPolicy] recommends for a [FinancialEvent].
///
/// IMPORTANT: this phase's pipeline (`SmsInboxItemsNotifier._generateFinancialEventsForPending`)
/// only ever *computes and stores* this value — it never executes
/// [createTransaction]/[updateTransaction] automatically. Every event is
/// surfaced through the existing manual `SmsConvertSheet`/`SmsConversionRouter`
/// flow regardless of which action was recommended, so the recommendation can
/// be validated against real usage before any auto-execution is enabled in a
/// later phase.
enum AutomationAction {
  /// A new `Transaction` should be created. Computed, not executed, this
  /// phase.
  createTransaction,

  /// Reserved — no scenario in this phase's `TransactionMatcher` produces a
  /// match result that maps to this action yet. Kept in the enum so wiring a
  /// real "this SMS corrects/completes an existing event" case later is a
  /// new branch, not a breaking enum change.
  updateTransaction,

  /// This event is additional evidence for (or a refund/reversal of) an
  /// existing event — surfaced for manual review this phase rather than
  /// auto-linked.
  linkToExisting,

  needsReview,

  ignore,
}

extension AutomationActionX on AutomationAction {
  static AutomationAction fromName(String? name) {
    if (name == null) return AutomationAction.needsReview;
    return AutomationAction.values.firstWhere(
      (a) => a.name == name,
      orElse: () => AutomationAction.needsReview,
    );
  }
}
