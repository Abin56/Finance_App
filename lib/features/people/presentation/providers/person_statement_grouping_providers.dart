import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../credit_cards/domain/statement.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// One [Statement] a person owes money inside, paired with every one of
/// their pending expense participations that falls within it — the People
/// screen's "group assigned expenses by statement" requirement. Built
/// entirely from existing providers (`pendingSplitParticipantsProvider`,
/// `creditCardsStreamProvider`, `statementsStreamProvider`) — no new stored
/// linkage, since a purchase's statement is always derivable from
/// `Transaction.accountId` + `Transaction.dateTime` at read time.
typedef StatementExpenseGroup = ({
  Statement statement,
  List<({String expenseDescription, double share, double collected, double pending})> items,
});

/// Every [StatementExpenseGroup] for [personId] — one entry per statement
/// that has at least one of this person's pending expense shares inside it,
/// newest statement first. Expenses on a card with no linked
/// [CreditCardProfile], or on a plain (non-card) account, are simply
/// excluded — "grouped by statement" only applies to card spending.
final personStatementGroupsProvider = Provider.family<List<StatementExpenseGroup>, String>((ref, personId) {
  final pending = ref.watch(pendingSplitParticipantsProvider).where((p) => p.participant.personId == personId);
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  final transactionById = {for (final t in transactions) t.id: t};
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];

  final itemsByStatementId = <String, List<({String expenseDescription, double share, double collected, double pending})>>{};
  final statementById = <String, Statement>{};

  for (final entry in pending) {
    final transaction = transactionById[entry.expense.transactionId];
    if (transaction == null) continue;
    final card = cards.where((c) => c.accountId == transaction.accountId).firstOrNull;
    if (card == null) continue;

    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    final statement = statements.where((s) => s.contains(transaction.dateTime)).firstOrNull;
    if (statement == null) continue;

    statementById[statement.id] = statement;
    (itemsByStatementId[statement.id] ??= []).add((
      expenseDescription: entry.expense.description,
      share: entry.participant.share,
      collected: entry.installment.amountPaid,
      pending: entry.installment.remainingAmount,
    ));
  }

  final groups = [
    for (final id in itemsByStatementId.keys) (statement: statementById[id]!, items: itemsByStatementId[id]!),
  ]..sort((a, b) => b.statement.periodEnd.compareTo(a.statement.periodEnd));
  return groups;
});
