import 'cycle_anchor.dart';
import 'cycle_item.dart';

/// The result of running a list of [CycleItem]s through
/// [CycleEngine.classifyForCarryForward].
///
/// The rule applied to reach this result, for every item, one at a time:
///
/// ```text
///                    ┌────────────────┐
///                    │  Classify by   │
///                    │  CycleAnchor   │
///                    └───────┬────────┘
///                            │
///        ┌───────────────────┼───────────────────┐
///        ▼                   ▼                    ▼
///   Previous Cycle      Current Cycle        Future Cycle
///        │                   │                    │
///   Unpaid? ── Yes ──► Carry Forward          Never shown
///        │              (previousCyclePending)     │
///        No                  │                     ▼
///        ▼                   ▼                (not returned)
///   History only        Always shown
///  (not returned)        (current)
/// ```
///
/// - **Previous cycle, still pending (not settled)** → surfaced in
///   [previousCyclePending] so the user can't miss it once a new cycle
///   starts. This is the "carry forward" behavior.
/// - **Previous cycle, settled** → dropped entirely. Not in
///   [previousCyclePending], not in [current], not in [future] — it
///   disappears from this view for good (still visible in whatever
///   feature-level history list reads the raw records directly; this
///   engine only decides what needs *attention*, not what's remembered).
/// - **Current cycle** → always in [current], whether paid or not — "this
///   cycle" is shown unconditionally.
/// - **Future cycle** → always in [future], never in [current] or
///   [previousCyclePending].
///
/// See the doc comment on [CycleEngine] itself for how the pieces
/// ([CycleAnchor], [CyclePeriod], [CycleItem], [CycleEngine]) fit together.
class CycleEngineResult<T extends CycleItem> {
  const CycleEngineResult({
    required this.previousCyclePending,
    required this.current,
    required this.future,
  });

  /// Previous-cycle items that are NOT settled — carried forward into the
  /// "Previous Cycle Pending" view. A previous-cycle item that IS settled is
  /// simply absent from every list here: settled previous-cycle items
  /// disappear entirely, never shown again.
  final List<T> previousCyclePending;

  /// Every item whose [CycleItem.cycleDate] classifies as
  /// [CycleClassification.current] — shown regardless of settled state (a
  /// paid current-cycle item still shows; only previous-cycle settled items
  /// disappear).
  final List<T> current;

  /// Every item whose [CycleItem.cycleDate] classifies as
  /// [CycleClassification.future] — never shown in a current-cycle view.
  final List<T> future;
}

/// The shared Payment Cycle engine — the single implementation of
/// "previous cycle pending carries forward into current cycle; settled
/// previous-cycle items disappear forever" for the whole app. Every feature
/// with its own notion of a recurring due date/window (Credit Card
/// statements today; Bills/EMI/Loans later) runs its own [CycleItem]
/// adapter through this one pure function instead of reimplementing
/// carry-forward itself. See [CycleEngineResult] for the exact rule and a
/// flow diagram.
///
/// How the four pieces fit together:
///
/// - [CycleAnchor] — "when does a cycle start/end", given a single anchor
///   day of month (e.g. a credit card's statement day). Pure date math, no
///   feature knowledge.
/// - [CyclePeriod] — one concrete `[start, end]` window, produced by
///   [CycleAnchor].
/// - [CycleItem] — the feature-agnostic contract ([CycleEngine] only ever
///   touches these five things: [CycleItem.cycleDate], [CycleItem.isSettled],
///   [CycleItem.carryForwardEligible], plus the descriptive
///   [CycleItem.sourceType]/[CycleItem.totalAmount]/etc. fields, which
///   [CycleEngine] doesn't inspect at all). Each feature supplies its own
///   adapter implementing this — `StatementCycleItem` for Credit Cards,
///   `InstallmentCycleItem` for EMI/Loans.
/// - [CycleEngine] (this class) — the one function,
///   [classifyForCarryForward], that takes a list of [CycleItem]s plus a
///   [CycleAnchor] and returns a [CycleEngineResult]. Pure, no I/O, no
///   Riverpod/Firestore dependency — a feature's provider calls this after
///   loading its own records and wrapping them in its adapter.
///
/// A new feature adopts this engine by writing ONE adapter class (a
/// `*CycleItem` implementing [CycleItem] over its own domain model) and ONE
/// provider that loads its records, wraps them, and calls
/// [classifyForCarryForward] — nothing here ever needs to change for a new
/// adopter.
abstract class CycleEngine {
  CycleEngine._();

  static CycleEngineResult<T> classifyForCarryForward<T extends CycleItem>(
    List<T> items,
    CycleAnchor anchor, {
    DateTime? now,
  }) {
    final previousPending = <T>[];
    final current = <T>[];
    final future = <T>[];
    for (final item in items) {
      final classification = anchor.classify(item.cycleDate, now: now);
      switch (classification) {
        case CycleClassification.previous:
          if (!item.isSettled && item.carryForwardEligible) previousPending.add(item);
        case CycleClassification.current:
          current.add(item);
        case CycleClassification.future:
          future.add(item);
      }
    }
    return CycleEngineResult(previousCyclePending: previousPending, current: current, future: future);
  }
}
