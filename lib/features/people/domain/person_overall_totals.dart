import 'ledger_entry.dart';

/// Splits a person's ledger activity into two separate positive totals —
/// "You Owe" and "They Owe" — rather than the single netted number
/// `Person.currentBalance` already is. Needed because a person can owe you
/// on some transactions while you owe them on others at the same time (e.g.
/// a split expense they haven't paid back, plus an unrelated loan you took
/// from them); netting alone answers "who's ahead overall" but not "how
/// much is actually outstanding in each direction," which is what a
/// Previous/Current/Overall dashboard needs to show without hiding either
/// side's activity.
///
/// Pure, no I/O — mirrors `CycleAggregate`'s `.from()` shape.
class PersonOverallTotals {
  const PersonOverallTotals({
    required this.totalYouOwe,
    required this.totalTheyOwe,
    required this.netBalance,
  });

  /// Sum of every entry whose `signedAmount` is negative (money moving
  /// toward "you owe them more"), reported as a positive amount.
  final double totalYouOwe;

  /// Sum of every entry whose `signedAmount` is positive (money moving
  /// toward "they owe you more").
  final double totalTheyOwe;

  /// `totalTheyOwe - totalYouOwe` — matches `Person.currentBalance`'s sign
  /// convention (positive = they owe you).
  final double netBalance;

  /// Computes totals from a person's active (non-deleted) ledger entries.
  /// Individual entries are untouched — this only folds them into two
  /// running sums, never collapses or removes source records.
  static PersonOverallTotals from(List<LedgerEntry> activeEntries) {
    var youOwe = 0.0;
    var theyOwe = 0.0;
    for (final entry in activeEntries) {
      if (entry.isDeleted) continue;
      final signed = entry.signedAmount;
      if (signed >= 0) {
        theyOwe += signed;
      } else {
        youOwe += -signed;
      }
    }
    return PersonOverallTotals(totalYouOwe: youOwe, totalTheyOwe: theyOwe, netBalance: theyOwe - youOwe);
  }
}
