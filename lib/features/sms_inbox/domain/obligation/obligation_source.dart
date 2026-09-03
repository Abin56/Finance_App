/// Where a [FinancialObligation] came from — kept as its own field (rather
/// than inferred from other fields) so future sources (a user-created
/// reminder, a linked `Bill`/`Installment` schedule) can be added without
/// changing how existing SMS-detected obligations are represented.
enum ObligationSource {
  /// Detected from an SMS reminder-shaped [FinancialEvent] — the only
  /// source this Phase 4 foundation produces.
  smsDetected,

  /// Reserved for a future manual "remind me about this" entry point.
  manual,

  /// Reserved for a future link to an existing `Bill`/`Installment`
  /// schedule (see `lib/features/bills`, `lib/core/payment_schedule`) —
  /// not populated by this phase.
  scheduleLinked,
}

extension ObligationSourceX on ObligationSource {
  static ObligationSource fromName(String? name) {
    if (name == null) return ObligationSource.smsDetected;
    return ObligationSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ObligationSource.smsDetected,
    );
  }
}
