import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'person_pending_participants_providers.dart';

/// This person's split/assigned-expense reconciliation numbers — the
/// Contact Ledger stat card's `You will receive` / `Total Settled` /
/// `Total Spent` trio. Scoped to Expense participations only (not plain
/// lending/adjustment ledger entries, which are out of scope for this
/// redesign), folded from [personSplitParticipantsProvider] so it can never
/// disagree with the per-row settlement numbers the same screen shows.
class PersonExpenseStats {
  const PersonExpenseStats({required this.totalSpent, required this.totalSettled});

  final double totalSpent;
  final double totalSettled;

  /// `Total Spent = Total Settled + Pending` holds by construction — this
  /// is the one place that identity is derived, never re-computed elsewhere.
  double get pending => totalSpent - totalSettled;
}

final personExpenseStatsProvider = Provider.family<PersonExpenseStats, String>((ref, personId) {
  final participants = ref.watch(personSplitParticipantsProvider(personId));
  final totalSpent = participants.fold(0.0, (sum, p) => sum + p.participant.share);
  final totalSettled = participants.fold(0.0, (sum, p) => sum + p.installment.amountPaid);
  return PersonExpenseStats(totalSpent: totalSpent, totalSettled: totalSettled);
});
