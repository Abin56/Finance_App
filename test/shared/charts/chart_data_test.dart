import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/reports/presentation/widgets/reports_category_list.dart';
import 'package:finance_app/shared/charts/domain/bar_chart_data.dart';
import 'package:finance_app/shared/charts/domain/category_chart_adapters.dart';
import 'package:finance_app/shared/charts/domain/chart_point.dart';
import 'package:finance_app/shared/charts/domain/line_chart_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLineChartData.trend', () {
    test('wraps points into a single named series', () {
      final points = [const ChartPoint(x: 0, y: 10), const ChartPoint(x: 1, y: 20)];
      final data = AppLineChartData.trend(points: points, seriesName: 'Spending');

      expect(data.series, hasLength(1));
      expect(data.series.first.name, 'Spending');
      expect(data.series.first.points, points);
    });
  });

  group('AppBarChartData.monthlyComparison', () {
    test('builds one category per month with values aligned to series order', () {
      final data = AppBarChartData.monthlyComparison(
        monthLabels: ['Jan', 'Feb'],
        seriesByName: {
          'Income': [1000, 1200],
          'Expense': [800, 900],
        },
      );

      expect(data.groupLabels, ['Income', 'Expense']);
      expect(data.categories, hasLength(2));
      expect(data.categories[0].label, 'Jan');
      expect(data.categories[0].values, [1000, 800]);
      expect(data.categories[1].label, 'Feb');
      expect(data.categories[1].values, [1200, 900]);
    });
  });

  group('categorySpendingEntriesToPieData', () {
    test('adapts each entry into a slice using the category color and amount', () {
      final category = Category(
        id: 'cat1',
        name: 'Groceries',
        type: CategoryType.expense,
        iconKey: 'groceries',
        colorValue: 0xFF00FF00,
        createdAt: DateTime(2026, 1, 1),
      );
      final entries = [CategorySpendingEntry(category: category, amount: 500, percentOfTotal: 100)];

      final pieData = categorySpendingEntriesToPieData(entries);

      expect(pieData.slices, hasLength(1));
      expect(pieData.slices.first.label, 'Groceries');
      expect(pieData.slices.first.value, 500);
      expect(pieData.slices.first.color.toARGB32(), 0xFF00FF00);
    });

    test('returns an empty pie for an empty entry list', () {
      expect(categorySpendingEntriesToPieData(const []).slices, isEmpty);
    });
  });
}
