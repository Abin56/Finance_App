import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/reports/presentation/widgets/reports_my_expense_card.dart';

/// 360x640 is the standard small Android phone — the card lays its stats out
/// two to a Row, so this is the width they have to survive.
const _smallPhone = Size(360, 640);

void main() {
  testWidgets('shows each figure once and fits a small phone', (tester) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportsMyExpenseCard(
            breakdown: (personal: 1234567.89, split: 987654.32, total: 2222222.21),
            moneyToReceive: 1234567.89,
            moneyReceived: 999999.99,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Total Expense'), findsOneWidget);
    expect(find.text('Money To Receive'), findsOneWidget);
    expect(find.text('Money Received'), findsOneWidget);

    // "Outstanding Amount" used to render the same moneyToReceive figure a
    // second time. Every tile on this card must be a distinct metric.
    expect(find.text('Outstanding Amount'), findsNothing);
  });
}
