import 'package:finance_app/features/people/domain/person_cycle_statement.dart';
import 'package:finance_app/features/people/presentation/widgets/person_settlement_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StatementRow _row({
  String key = 'ledger:e1',
  required StatementCategory category,
  double amount = 1000,
  double? signed,
  double? remaining,
  bool obligation = true,
  DateTime? date,
  String title = 'KSEB electricity bill',
  double advanceDelta = 0,
}) {
  final d = date ?? DateTime(2026, 9, 29);
  return StatementRow(
    key: key,
    date: d,
    createdAt: d,
    isObligation: obligation,
    category: category,
    title: title,
    amount: amount,
    signedAmount: signed ?? amount,
    advanceDelta: advanceDelta,
    runningBalance: 0,
    remainingNow: remaining,
  );
}

void main() {
  final now = DateTime(2026, 9, 30);

  test('assigned expense with a partial payment reads as assigned, partially paid', () {
    final row = _row(category: StatementCategory.gave, remaining: 400);
    final kind = settlementKindOf(row, sourceKind: 'assignedExpense');
    expect(kind, SettlementKind.assigned);
    expect(settlementPaidOf(row), 600);
    final s = settlementStatusOf(row, kind, 'Amma', now: now);
    expect(s.label, 'Partially paid');
    expect(s.detail, contains('Amma still owes'));
  });

  test('money received from the person is payable, worded without signs', () {
    final row = _row(category: StatementCategory.borrowed, title: 'Money I Borrowed', signed: -1000, remaining: 1000);
    final kind = settlementKindOf(row);
    expect(kind, SettlementKind.moneyReceived);
    expect(settlementTitleOf(row, kind, 'Amma'), 'Money received from Amma');
    expect(settlementRelationOf(row, kind, 'Amma'), startsWith('Amma gave you'));
    expect(settlementStatusOf(row, kind, 'Amma', now: now).label, 'You need to pay');
    expect(settlementColorOf(row, kind), SettlementColors.payable);
  });

  test('EMI not yet due is Upcoming; past due and unpaid is Payment due', () {
    final upcoming = _row(key: 'emi-inst:i1', category: StatementCategory.emi, remaining: 1666.67, amount: 1666.67, date: DateTime(2026, 10, 4));
    expect(settlementStatusOf(upcoming, SettlementKind.emi, 'Amma', now: now).label, 'Upcoming EMI');
    final due = _row(key: 'emi-inst:i2', category: StatementCategory.emi, remaining: 1666.67, amount: 1666.67, date: DateTime(2026, 9, 25));
    expect(settlementStatusOf(due, SettlementKind.emi, 'Amma', now: now).label, 'Payment due');
    expect(settlementColorOf(due, SettlementKind.emi), SettlementColors.emi);
  });

  test('unpaid loan installment past due is Overdue; settled is Paid in full', () {
    final overdue = _row(key: 'loan-inst:l1', category: StatementCategory.loan, remaining: 1500, amount: 2000, date: DateTime(2026, 9, 20));
    expect(settlementStatusOf(overdue, SettlementKind.loanInstallment, 'Amma', now: now).label, 'Overdue');
    final settled = _row(category: StatementCategory.gave, remaining: 0);
    expect(settlementStatusOf(settled, SettlementKind.moneyGiven, 'Amma', now: now).label, 'Paid in full');
  });

  test('advance rows are their own kind', () {
    final adv = _row(category: StatementCategory.advance, obligation: false, signed: 0, advanceDelta: -2000, amount: 2000, title: 'Advance received');
    final kind = settlementKindOf(adv);
    expect(kind, SettlementKind.advance);
    expect(settlementRelationOf(adv, kind, 'Amma'), contains('held as advance'));
  });

  testWidgets('row renders original / paid / remaining and expands', (tester) async {
    final row = _row(category: StatementCategory.gave, remaining: 400);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PersonSettlementRow(row: row, personName: 'Amma', sourceKind: 'assignedExpense', now: now)),
    ));
    expect(find.text('Assigned expense'), findsOneWidget);
    expect(find.text('PARTIALLY PAID'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    await tester.tap(find.text('KSEB electricity bill'));
    await tester.pumpAndSettle();
    expect(find.text("Amma's responsibility"), findsOneWidget);
    expect(find.text('SOURCE'), findsOneWidget);
  });
}
