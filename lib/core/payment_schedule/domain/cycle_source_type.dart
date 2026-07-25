/// Where a [CycleItem] originated, for display/identification purposes only
/// — deliberately a separate vocabulary from [OwnerType]. `OwnerType`
/// describes *business ownership* of a Firestore-persisted
/// [PaymentSchedule]/[Installment] document (Loan, EMI, Split Expense,
/// Bill); `CycleSourceType` describes *where a cycle item came from* for
/// carry-forward/scheduling purposes, independent of whether that source is
/// backed by the `payment_schedule` engine at all (a credit card `Statement`
/// isn't). The shared cycle engine (`CycleEngine`/`CycleItem`) depends only
/// on this enum, never on any feature-specific type — each feature maps its
/// own model to a [CycleSourceType] through its own adapter (e.g.
/// `StatementCycleItem`, `InstallmentCycleItem`), so a new feature can plug
/// in without the engine importing anything feature-specific.
/// Historical snapshot status per source, as of Chat 1 (2026-07):
/// documentation only — no schema changes were made or are proposed here.
///
/// - [creditCardStatement]: already immutable-per-occurrence. Each closed
///   billing cycle materializes as its own new Firestore document
///   (`StatementRepository.materializeIfDue`); `totalAmount`/`periodStart`/
///   `periodEnd`/`dueDate` are frozen at creation and never rewritten.
/// - [emi], [loan], [splitExpense] (via `Installment`/`PaymentSchedule`):
///   already immutable-per-occurrence. `InstallmentRepository.generateInstallments`
///   creates one document per due date up front; no rollover exists by
///   design (see `Installment`'s own class doc, which contrasts this
///   directly with the older `Bill` model below).
/// - [bill]: now immutable-per-occurrence, same as the sources above.
///   `Bill` is a template (name/amount/recurrence/`nextDueDate`); each
///   billing cycle materializes as its own `BillOccurrence` document
///   (`BillOccurrenceRepository.ensureCurrentOccurrence`), never rewritten
///   once settled. `BillOccurrenceCycleItem` is the `CycleItem` adapter for
///   this source.
enum CycleSourceType {
  creditCardStatement,
  bill,
  emi,
  loan,
  splitExpense,

  /// A generic `payment_schedule` engine installment not covered by a more
  /// specific value above — reserved for a future owner type.
  paymentSchedule,

  /// A future recurring-payment feature not yet built.
  recurringPayment,

  /// A future manual balance/ledger correction, not tied to any recurring
  /// cycle of its own.
  manualAdjustment,

  /// Anything not covered by the values above.
  other,
}
