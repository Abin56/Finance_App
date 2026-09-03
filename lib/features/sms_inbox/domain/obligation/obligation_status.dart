/// The lifecycle a [FinancialObligation] moves through — independent of
/// [ObligationSemanticBucket], which only classifies a single SMS/event.
/// This tracks the obligation's own state over time, across possibly many
/// observations (a reminder SMS, then a due-date SMS, then the actual
/// payment).
///
/// Not every obligation reaches [completed] — the whole point of Safety
/// rule 10 ("a reminder must never automatically create a real
/// transaction") is that this engine only ever *observes* and *links*,
/// never assumes an obligation was paid without an actual matching
/// [FinancialEvent].
enum ObligationStatus {
  /// Just observed from a reminder-shaped SMS; no due date resolved yet.
  detected,

  /// A due/scheduled date was resolved and it is in the future.
  upcoming,

  /// The resolved due/scheduled date has arrived or passed, with no linked
  /// completed payment yet.
  due,

  /// A payment attempt was observed (e.g. a "payment failed, please retry"
  /// SMS) but not yet confirmed successful.
  paymentAttempted,

  /// Resolved — a completed [FinancialEvent] was linked to this obligation.
  completed,

  /// A payment attempt against this obligation failed and no further
  /// attempt has been observed.
  failed,

  /// The obligation was explicitly cancelled (e.g. subscription
  /// cancellation SMS) — never inferred, only set from an explicit signal.
  cancelled,

  /// The due/scheduled date passed long enough ago with no activity that
  /// this obligation is no longer considered outstanding for linking
  /// purposes.
  expired,

  /// A completed payment linked to this obligation was later reversed.
  reversed,
}

extension ObligationStatusX on ObligationStatus {
  static ObligationStatus fromName(String? name) {
    if (name == null) return ObligationStatus.detected;
    return ObligationStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ObligationStatus.detected,
    );
  }

  /// Whether this obligation is still a candidate for
  /// [ObligationLinker]/matching against a later completed [FinancialEvent]
  /// — i.e. still "owed."
  bool get isOutstanding {
    switch (this) {
      case ObligationStatus.detected:
      case ObligationStatus.upcoming:
      case ObligationStatus.due:
      case ObligationStatus.paymentAttempted:
        return true;
      case ObligationStatus.completed:
      case ObligationStatus.failed:
      case ObligationStatus.cancelled:
      case ObligationStatus.expired:
      case ObligationStatus.reversed:
        return false;
    }
  }

  String get label {
    switch (this) {
      case ObligationStatus.detected:
        return 'Detected';
      case ObligationStatus.upcoming:
        return 'Upcoming';
      case ObligationStatus.due:
        return 'Due';
      case ObligationStatus.paymentAttempted:
        return 'Payment attempted';
      case ObligationStatus.completed:
        return 'Completed';
      case ObligationStatus.failed:
        return 'Failed';
      case ObligationStatus.cancelled:
        return 'Cancelled';
      case ObligationStatus.expired:
        return 'Expired';
      case ObligationStatus.reversed:
        return 'Reversed';
    }
  }
}
