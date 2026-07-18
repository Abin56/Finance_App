import 'package:fl_chart/fl_chart.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/reports/presentation/widgets/cash_flow_chart.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the bug where CashFlowChart bucketed by
/// Transaction.dateTime instead of the accounting-month-aware date already
/// used to build the transaction list it was given — a transaction whose
/// accountingMonth pulled it into the displayed period, but whose real date
/// fell outside every week window, silently contributed to zero bars while
/// still counting in the Overview stat cards above the chart.
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

  Transaction income({required DateTime dateTime, double amount = 100}) {
    return Transaction(
      id: 'i-${dateTime.millisecondsSinceEpoch}',
      type: TransactionType.income,
      amount: amount,
      dateTime: dateTime,
      accountId: 'acc1',
      categoryId: 'cat1',
      createdAt: dateTime,
    );
  }

  double totalChartExpense(WidgetTester tester) {
    final barChart = tester.widget<BarChart>(find.byType(BarChart));
    var total = 0.0;
    for (final group in barChart.data.barGroups) {
      total += group.barRods[1].toY; // index 1 = expense rod, per barRods order
    }
    return total;
  }

  double totalChartIncome(WidgetTester tester) {
    final barChart = tester.widget<BarChart>(find.byType(BarChart));
    var total = 0.0;
    for (final group in barChart.data.barGroups) {
      total += group.barRods[0].toY; // index 0 = income rod
    }
    return total;
  }

  testWidgets('chart total matches the Overview total for plain same-month transactions', (tester) async {
    final periodStart = DateTime(2026, 7, 1);
    final periodEnd = DateTime(2026, 7, 31, 23, 59, 59);
    final transactions = [
      expense(dateTime: DateTime(2026, 7, 5), amount: 300),
      expense(dateTime: DateTime(2026, 7, 20), amount: 200),
      income(dateTime: DateTime(2026, 7, 10), amount: 1000),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashFlowChart(
            periodStart: periodStart,
            periodEnd: periodEnd,
            transactions: transactions,
            period: ReportsPeriod.thisMonth,
          ),
        ),
      ),
    );

    expect(totalChartExpense(tester), 500, reason: 'must equal the Overview card\'s expense total (300+200)');
    expect(totalChartIncome(tester), 1000);
  });

  testWidgets(
    'a transaction reassigned to this month via accountingMonth appears in the chart, not vanishes',
    (tester) async {
      final periodStart = DateTime(2026, 7, 1);
      final periodEnd = DateTime(2026, 7, 31, 23, 59, 59);
      // Real date is June (outside every July week window), but
      // accountingMonth pulls it into July — reports_screen.dart would
      // have included this in periodTransactions for a July "This Month"
      // view since range.contains(reportDateFor(t)) is true.
      final reassigned = expense(dateTime: DateTime(2026, 6, 28), accountingMonth: DateTime(2026, 7), amount: 700);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashFlowChart(
              periodStart: periodStart,
              periodEnd: periodEnd,
              transactions: [reassigned],
              period: ReportsPeriod.thisMonth,
            ),
          ),
        ),
      );

      expect(
        totalChartExpense(tester),
        700,
        reason: 'accounting-month-reassigned transaction must land in a bar, not silently disappear',
      );
    },
  );

  testWidgets('non-month-granular period buckets by the real date, unaffected by accountingMonth', (tester) async {
    final periodStart = DateTime(2026, 7, 1);
    final periodEnd = DateTime(2026, 7, 7, 23, 59, 59);
    // thisWeek is not month-granular — reportDateFor always returns dateTime.
    final t = expense(dateTime: DateTime(2026, 7, 3), accountingMonth: DateTime(2026, 9), amount: 400);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashFlowChart(
            periodStart: periodStart,
            periodEnd: periodEnd,
            transactions: [t],
            period: ReportsPeriod.thisWeek,
          ),
        ),
      ),
    );

    expect(totalChartExpense(tester), 400);
  });
}
