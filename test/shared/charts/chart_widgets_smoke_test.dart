import 'package:finance_app/shared/charts/domain/bar_chart_data.dart';
import 'package:finance_app/shared/charts/domain/chart_point.dart';
import 'package:finance_app/shared/charts/domain/line_chart_data.dart';
import 'package:finance_app/shared/charts/domain/pie_chart_data.dart';
import 'package:finance_app/shared/widgets/charts/app_bar_chart.dart';
import 'package:finance_app/shared/widgets/charts/app_line_chart.dart';
import 'package:finance_app/shared/widgets/charts/app_pie_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders each chart widget with empty/single-point/multi-series input to
/// confirm none throw — these charts are pure presentation over data models
/// already unit-tested in `chart_data_test.dart`, so this only guards
/// against layout/render crashes, not chart math.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
  }

  group('AppLineChart', () {
    testWidgets('renders with no data', (tester) async {
      await pump(tester, const AppLineChart(data: AppLineChartData(series: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a single point', (tester) async {
      await pump(
        tester,
        AppLineChart(data: AppLineChartData.trend(points: const [ChartPoint(x: 0, y: 5)])),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders multiple series', (tester) async {
      await pump(
        tester,
        const AppLineChart(
          data: AppLineChartData(
            series: [
              ChartSeries(name: 'Income', points: [ChartPoint(x: 0, y: 10), ChartPoint(x: 1, y: 20)]),
              ChartSeries(name: 'Expense', points: [ChartPoint(x: 0, y: 5), ChartPoint(x: 1, y: 15)]),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppBarChart', () {
    testWidgets('renders with no categories', (tester) async {
      await pump(tester, const AppBarChart(data: AppBarChartData(categories: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders grouped bars', (tester) async {
      await pump(
        tester,
        AppBarChart(
          data: AppBarChartData.monthlyComparison(
            monthLabels: const ['Jan', 'Feb'],
            seriesByName: const {
              'Income': [1000, 1200],
              'Expense': [800, 900],
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppPieChart', () {
    testWidgets('renders with no slices', (tester) async {
      await pump(tester, const AppPieChart(data: AppPieChartData(slices: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders multiple slices', (tester) async {
      await pump(
        tester,
        const AppPieChart(
          data: AppPieChartData(
            slices: [
              ChartSlice(label: 'Food', value: 60, color: Colors.red),
              ChartSlice(label: 'Transport', value: 40, color: Colors.blue),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
