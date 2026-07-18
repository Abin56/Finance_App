import 'package:finance_app/core/constants/app_colors.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/domain/person_timeline_entry.dart';
import 'package:finance_app/features/people/presentation/widgets/person_statement_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds the amount `Text` rendered directly below a `_StatRow`'s label —
/// avoids ambiguous matches when two stat rows happen to share a value.
String _amountNear(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
  final texts = tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)));
  return texts.last.data!;
}

/// Regression coverage for the bug where "Total money given"/"Total money
/// received" always showed ₹0 for non-loan history — they used to filter
/// entries by a hardcoded title set ({'Money given', 'Money repaid', ...})
/// that never matched the real `LedgerEntryType.label` values
/// ('They Need to Pay Me', 'Mark as Paid', etc.), so only the two
/// loan-specific titles ('Money lent', 'Loan payment received') ever
/// counted. The fix switched to signedAmount-based totals across every
/// category, matching the documented sign convention (positive = given,
/// negative = received) instead of title string matching.
void main() {
  Person person({double currentBalance = 0}) => Person(
        id: 'p1',
        name: 'Alex',
        avatarColorValue: 0xFF000000,
        openingBalance: 0,
        currentBalance: currentBalance,
        createdAt: DateTime(2026, 1, 1),
      );

  PersonTimelineEntry entry({
    required String id,
    required String title,
    required double signedAmount,
    PersonTimelineCategory category = PersonTimelineCategory.lending,
  }) {
    return PersonTimelineEntry(
      id: id,
      date: DateTime(2026, 1, 1),
      icon: Icons.circle,
      title: title,
      signedAmount: signedAmount,
      category: category,
      isDeleted: false,
      color: AppColors.pending,
    );
  }

  Future<void> pumpHeader(WidgetTester tester, Person p, List<PersonTimelineEntry> entries) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PersonStatementHeader(person: p, entries: entries)),
      ),
    );
  }

  testWidgets('sums money given/received from manual ledger-entry-labeled titles, not just loan titles', (
    tester,
  ) async {
    final entries = [
      // Real LedgerEntryType.label strings — none of these match the old
      // hardcoded title sets, which is exactly the bug this guards against.
      entry(id: 'e1', title: 'They Need to Pay Me', signedAmount: 1000), // gave
      entry(id: 'e2', title: 'Mark as Paid', signedAmount: 500), // repaid
      entry(id: 'e3', title: 'They Paid for Me', signedAmount: -300), // borrowed
      entry(id: 'e4', title: 'Received Payment', signedAmount: -200), // receivedBack
    ];

    await pumpHeader(tester, person(currentBalance: 1000), entries);

    expect(_amountNear(tester, 'Total money given'), '₹1,500.00', reason: '1000 (gave) + 500 (repaid)');
    expect(_amountNear(tester, 'Total money received'), '₹500.00', reason: '300 (borrowed) + 200 (receivedBack)');
  });

  testWidgets('includes split/assigned-expense and adjustment entries in the given/received totals', (tester) async {
    final entries = [
      entry(id: 'e1', title: 'They Need to Pay Me', signedAmount: 200, category: PersonTimelineCategory.splitExpense),
      entry(
        id: 'e2',
        title: 'They Need to Pay Me',
        signedAmount: 300,
        category: PersonTimelineCategory.assignedExpense,
      ),
      entry(id: 'e3', title: 'Correct Balance', signedAmount: -100, category: PersonTimelineCategory.other),
    ];

    await pumpHeader(tester, person(currentBalance: 400), entries);

    expect(_amountNear(tester, 'Total money given'), '₹500.00', reason: '200 (split) + 300 (assigned)');
    expect(_amountNear(tester, 'Total money received'), '₹100.00', reason: '100 (adjustment)');
  });

  testWidgets('shows ₹0.00 for both totals when there are no entries', (tester) async {
    await pumpHeader(tester, person(), const []);

    expect(_amountNear(tester, 'Total money given'), '₹0.00');
    expect(_amountNear(tester, 'Total money received'), '₹0.00');
  });
}
