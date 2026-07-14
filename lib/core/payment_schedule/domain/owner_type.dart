/// What kind of feature entity a [PaymentSchedule] belongs to. Stored as a
/// plain string on the schedule (and denormalized onto every [Installment]
/// and [InstallmentPayment]) so the engine can stay ignorant of any one
/// feature's domain model while still letting a future cross-owner query
/// (e.g. "every overdue installment regardless of loan/bill/split") filter
/// by it.
enum OwnerType { loan, emi, splitExpense, bill }

extension OwnerTypeX on OwnerType {
  static OwnerType fromName(String name) =>
      OwnerType.values.firstWhere((t) => t.name == name, orElse: () => OwnerType.loan);
}
