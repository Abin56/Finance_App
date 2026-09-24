/// The part a [FinancialEvent] plays relative to other events describing the
/// same broader financial story (a purchase and its later refund, a credit
/// card charge and its later bill payment).
///
/// TODO(reminders): a future `reminderTrigger` value is reserved for when a
/// dedicated `FinancialReminder` engine is built (see the SMS AI rebuild
/// plan, deferred items) — an event that should *spawn* a reminder rather
/// than describe a completed money movement. Not added yet: this enum only
/// describes things that already happened.
enum FinancialEventRole {
  /// A normal, one-off transaction with nothing else to link it to.
  standalone,

  /// A charge (typically a credit-card purchase) that a later
  /// [linkedSettlement] event resolves — see [FinancialEvent.linkedEventId].
  originalCharge,

  /// A refund, reversal, or bill payment that resolves an earlier
  /// [originalCharge] event.
  linkedSettlement,
}

extension FinancialEventRoleX on FinancialEventRole {
  static FinancialEventRole fromName(String? name) {
    if (name == null) return FinancialEventRole.standalone;
    return FinancialEventRole.values.firstWhere(
      (r) => r.name == name,
      orElse: () => FinancialEventRole.standalone,
    );
  }
}
