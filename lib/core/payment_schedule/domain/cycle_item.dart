import 'cycle_source_type.dart';

/// The minimal feature-agnostic shape [CycleEngine] needs from any due item
/// — a credit card `Statement`, a `Bill`, an `Installment`. Never persisted
/// itself; always a thin, cheap-to-construct view built by each feature's
/// own adapter over an already-loaded domain object (see `StatementCycleItem`,
/// `InstallmentCycleItem`). This is the single contract that lets
/// [CycleEngine] classify/carry-forward across Credit Cards, Bills, EMI, and
/// Loans without knowing which one it's looking at, and without importing
/// anything feature-specific.
///
/// Every field here must be a real, honestly-derivable value from the
/// wrapped domain object — never a placeholder. [totalAmount]/[paidAmount]
/// are optional (nullable) precisely because not every future adopter is
/// guaranteed to track a due amount the same way (see the note on each
/// getter) — a null there means "this source doesn't track that", not "not
/// yet wired up".
///
/// Deliberately NOT included: an `originalCycle`/`currentCycle` pair. Which
/// cycle a date falls into is only meaningful relative to a caller-supplied
/// [CycleAnchor] and "now" (see `CycleAnchor.classify`) — it is not a fixed
/// property of the item itself, and an adapter has no anchor to classify
/// against at construction time (the caller picks the anchor, e.g. a card's
/// own `statementDay`). Classification is therefore always computed by
/// [CycleEngine] from [cycleDate], never stored on [CycleItem] — the same
/// "derive, don't cache a relative-to-now value" posture already used by
/// `Statement.status`/`Installment.status`/`Bill.status` elsewhere in this
/// codebase.
abstract class CycleItem {
  const CycleItem();

  /// Stable identity of the underlying record — used only for
  /// equality/keying by callers, not by the classifier itself.
  String get id;

  /// Which feature/model this item was adapted from — for display/grouping
  /// only (e.g. a future cross-feature "what's carried forward" list that
  /// needs to label each row). [CycleEngine] itself never branches on this.
  CycleSourceType get sourceType;

  /// The identifier of the underlying domain record within its own feature
  /// (a `Statement.id`, `Bill.id`, `Installment.id`) — today this is always
  /// equal to [id], but kept as a distinct getter so a future adapter that
  /// wraps a *derived* item (e.g. a synthetic per-participant split of one
  /// underlying record) can give the derived view its own [id] while still
  /// pointing back at the record it came from.
  String get sourceId;

  /// The date this item's cycle is anchored to for classification purposes
  /// — a Statement's period end, a Bill's due date, an Installment's due
  /// date.
  DateTime get cycleDate;

  /// The same date, exposed under the name every adopter's own domain model
  /// already uses for it — an alias of [cycleDate], not a second concept.
  DateTime get dueDate => cycleDate;

  /// The full amount owed for this cycle item, if this source tracks one —
  /// a Statement's `totalAmount`, a Bill's `amount`, an Installment's
  /// `amountDue`. Null only for a future source that genuinely has no fixed
  /// due amount (e.g. [CycleSourceType.manualAdjustment]).
  double? get totalAmount;

  /// How much of [totalAmount] has been paid so far, if tracked. Null under
  /// the same condition as [totalAmount].
  double? get paidAmount;

  /// [totalAmount] minus [paidAmount], clamped to a non-negative value —
  /// null iff either input is null. Never computed independently by a
  /// caller; always derived here from the same two real fields every
  /// adapter already exposes (mirrors `Statement.remainingAmount`/
  /// `Installment.remainingAmount`'s own clamp).
  double? get remainingAmount {
    final total = totalAmount;
    final paid = paidAmount;
    if (total == null || paid == null) return null;
    return (total - paid).clamp(0, total);
  }

  /// True once this item needs no further action. Feature-specific
  /// "settled" definitions are computed by each adapter and exposed here,
  /// so the shared engine never has to know what "settled" means for a
  /// given feature — only that this flag says so.
  bool get isSettled;

  /// True when [cycleDate] has passed and this item is still not [isSettled]
  /// — independent of which cycle (previous/current) it falls into. Exposed
  /// so a UI can show an "overdue" indicator on a *current*-cycle item
  /// without waiting for it to roll into "previous cycle pending" first.
  bool get isOverdue;

  /// Whether this specific item may ever be carried forward at all, before
  /// [CycleEngine] even asks whether it's previous-cycle and unsettled.
  /// Defaults to `true` for every adapter today (every current source is
  /// carry-forward-eligible) — exists so a future source can opt out
  /// entirely (e.g. a one-off manual adjustment with no notion of "next
  /// cycle" to carry into) without [CycleEngine] needing a new branch.
  bool get carryForwardEligible => true;
}
