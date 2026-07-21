import 'package:finance_app/features/transactions/domain/history_entry.dart';
import 'package:finance_app/features/transactions/presentation/widgets/history_tile.dart';
import 'package:finance_app/shared/domain/transaction_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Task 3's "replace every existing history row badge":
/// HistoryTile (the row every Main History entry renders through) must show
/// a TransactionKindBadge whose kind matches HistoryEntry.kind, whichever
/// source feature (plain expense, split expense, loan, bill, EMI, credit
/// card statement) built the entry.
void main() {
  HistoryEntry entryWith({required TransactionKind kind, required HistoryCategory category}) {
    return HistoryEntry(
      id: 'e1',
      date: DateTime(2026, 1, 1),
      title: 'Row title',
      subtitle: 'Row subtitle',
      amount: 100,
      isCredit: false,
      category: category,
      icon: Icons.circle_outlined,
      kind: kind,
    );
  }

  Future<void> pump(WidgetTester tester, HistoryEntry entry) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: HistoryTile(entry: entry))),
    );
  }

  final cases = {
    TransactionKind.myExpense: HistoryCategory.transaction,
    TransactionKind.splitExpense: HistoryCategory.splitExpense,
    TransactionKind.loan: HistoryCategory.loan,
    TransactionKind.bill: HistoryCategory.bill,
    TransactionKind.emi: HistoryCategory.emi,
    TransactionKind.creditCard: HistoryCategory.statementGenerated,
    TransactionKind.transfer: HistoryCategory.transaction,
  };

  for (final entry in cases.entries) {
    testWidgets('shows a ${entry.key.label} badge for a ${entry.value} entry', (tester) async {
      await pump(tester, entryWith(kind: entry.key, category: entry.value));

      expect(find.text(entry.key.label), findsOneWidget);
      expect(find.byIcon(entry.key.icon), findsOneWidget);
    });
  }
}
