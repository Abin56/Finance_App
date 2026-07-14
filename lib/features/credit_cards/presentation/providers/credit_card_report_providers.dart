import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/providers/person_statement_grouping_providers.dart';
import 'credit_card_providers.dart';

/// Sum of every card-account transaction dated within [start]..[end]
/// (inclusive) — Reports' "Monthly Card Spend" figure. Reuses
/// [transactionsForCardProvider] (already excludes soft-deleted entries via
/// the account-level filter it's built on) rather than re-deriving
/// "which transactions are on a card" a second time.
final creditCardSpendForRangeProvider = Provider.family<double, ({DateTime start, DateTime end})>((ref, range) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  var total = 0.0;
  for (final card in cards) {
    final transactions = ref.watch(transactionsForCardProvider(card.id));
    total += transactions
        .where((t) => !t.dateTime.isBefore(range.start) && !t.dateTime.isAfter(range.end))
        .fold(0.0, (sum, t) => sum + t.amount);
  }
  return total;
});

/// Count of statements (across every card) generated within [start]..[end]
/// — Reports' "Statement History" count.
final statementCountForRangeProvider = Provider.family<int, ({DateTime start, DateTime end})>((ref, range) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  var count = 0;
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    count += statements
        .where((s) => !s.generatedDate.isBefore(range.start) && !s.generatedDate.isAfter(range.end))
        .length;
  }
  return count;
});

/// Sum of manually-logged [Statement.interestCharged] across every
/// statement generated within [start]..[end] — omitted entirely from the
/// Reports UI when 0 (this app has no interest-calculation engine, so this
/// is purely what the user has logged, not computed).
final interestChargedForRangeProvider = Provider.family<double, ({DateTime start, DateTime end})>((ref, range) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  var total = 0.0;
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    for (final statement in statements) {
      if (statement.generatedDate.isBefore(range.start) || statement.generatedDate.isAfter(range.end)) continue;
      total += statement.interestCharged ?? 0;
    }
  }
  return total;
});

/// Sum of manually-logged [Statement.lateFee] across every statement
/// generated within [start]..[end] — same "omit when 0" convention.
final lateFeesForRangeProvider = Provider.family<double, ({DateTime start, DateTime end})>((ref, range) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  var total = 0.0;
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    for (final statement in statements) {
      if (statement.generatedDate.isBefore(range.start) || statement.generatedDate.isAfter(range.end)) continue;
      total += statement.lateFee ?? 0;
    }
  }
  return total;
});

/// Sum of every person's pending expense share across every statement —
/// Reports' "Friend Pending inside statement" figure, reusing
/// `personStatementGroupsProvider`'s per-person grouping rather than
/// re-deriving the card/statement linkage a third time.
final totalFriendPendingInStatementsProvider = Provider<double>((ref) {
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  var total = 0.0;
  for (final person in people) {
    final groups = ref.watch(personStatementGroupsProvider(person.id));
    for (final group in groups) {
      total += group.items.fold(0.0, (sum, i) => sum + i.pending);
    }
  }
  return total;
});
