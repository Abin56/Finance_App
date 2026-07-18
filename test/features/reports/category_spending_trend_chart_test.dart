import 'package:fl_chart/fl_chart.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/reports/presentation/widgets/category_spending_trend_chart.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the bug where CategorySpendingTrendChart bucketed
/// by Transaction.dateTime instead of the accounting-month-aware date
/// already used to build the transaction list — a transaction whose
/// accountingMonth pulled it into the displayed period, but whose real date
/// fell outside every day in the chart's date range, silently contributed
/// to zero chart points while the header total (folded from the same list
/// directly) still counted it.
void main() {
  Transaction expense({required DateTime dateTime, DateTime? accountingMonth, double amount = 100}) {
    return Transaction(
      id: 'e-${dateTime.millisecondsSinceEpoch}-${accountingMonth?.millisecondsSinceEpoch}',
      type: TransactionType.expense,
      amount: amount,
      dateTime: dateTime,
      accountId: 'acc1',
      categoryId: 'cat1',
      createdAt: dateTime,
      accountingMonth: accountingMonth,
    );
  }

  double chartTotal(WidgetTester tester) {
    final lineChart = tester.widget<LineChart>(find.byType(LineChart));
    return lineChart.data.lineBarsData.single.spots.fold(0.0, (sum, s) => sum + s.y);
  }

  testWidgets('chart total matches the header total for plain same-month transactions', (tester) async {
    final periodStart = DateTime(2026, 7, 1);
    final periodEnd = DateTime(2026, 7, 31);
    final transactions = [
      expense(dateTime: DateTime(2026, 7, 5), amount: 300),
      expense(dateTime: DateTime(2026, 7, 20), amount: 200),
    ];
    // categoryTotal on the real screen is transactions.fold(0, +amount) —
    // the same 500 the chart must reconcile to.

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategorySpendingTrendChart(
            periodStart: periodStart,
            periodEnd: periodEnd,
            transactions: transactions,
            color: Colors.blue,
            period: ReportsPeriod.thisMonth,
          ),
        ),
      ),
    );

    expect(chartTotal(tester), 500);
  });

  testWidgets('a transaction reassigned to this month via accountingMonth appears in the chart', (tester) async {
    final periodStart = DateTime(2026, 7, 1);
    final periodEnd = DateTime(2026, 7, 31);
    // Real date is June, outside the July day range — accountingMonth
    // pulls it into July, matching what category_spending_detail_screen.dart
    // would have already filtered into `categoryTransactions` for July.
    final reassigned = expense(dateTime: DateTime(2026, 6, 28), accountingMonth: DateTime(2026, 7), amount: 650);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategorySpendingTrendChart(
            periodStart: periodStart,
            periodEnd: periodEnd,
            transactions: [reassigned],
            color: Colors.blue,
            period: ReportsPeriod.thisMonth,
          ),
        ),
      ),
    );

    expect(chartTotal(tester), 650, reason: 'must land on a day within the range, not silently vanish');
  });

  testWidgets('non-month-granular period buckets by the real date, unaffected by accountingMonth', (tester) async {
    final periodStart = DateTime(2026, 7, 1);
    final periodEnd = DateTime(2026, 7, 7);
    final t = expense(dateTime: DateTime(2026, 7, 3), accountingMonth: DateTime(2026, 9), amount: 400);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategorySpendingTrendChart(
            periodStart: periodStart,
            periodEnd: periodEnd,
            transactions: [t],
            color: Colors.blue,
            period: ReportsPeriod.thisWeek,
          ),
        ),
      ),
    );

    expect(chartTotal(tester), 400);
  });
}
