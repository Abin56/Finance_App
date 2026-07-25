import 'package:flutter/material.dart';

/// One bar (or one group of bars sharing an x position, via [values]) in
/// an [AppBarChartData].
class ChartCategory {
  const ChartCategory({required this.label, required this.values, this.colors});

  final String label;

  /// One bar's height per group member — a single-element list draws one
  /// plain bar; multiple elements draw grouped bars sharing this
  /// category's x position (e.g. Income vs Expense for the same month).
  final List<double> values;

  /// Colors for each entry in [values], same index alignment. Falls back
  /// to the rendering widget's default palette if omitted.
  final List<Color>? colors;
}

/// Library-agnostic input for [AppBarChart] — a list of [ChartCategory]
/// bars/groups plotted on a shared x-axis, plus optional legend labels
/// for grouped bars.
class AppBarChartData {
  const AppBarChartData({required this.categories, this.groupLabels});

  final List<ChartCategory> categories;

  /// Legend labels for each position within a [ChartCategory.values] group
  /// — e.g. `['Income', 'Expense']` for a two-bar-per-month comparison.
  /// Omit for single-value (ungrouped) bars.
  final List<String>? groupLabels;

  /// Grouped bars comparing the same two (or more) series across several
  /// periods — the spec's "Monthly Comparison Chart" is an
  /// [AppBarChartData] whose every [ChartCategory.values] has the same
  /// length as [groupLabels], not a distinct chart type.
  factory AppBarChartData.monthlyComparison({
    required List<String> monthLabels,
    required Map<String, List<double>> seriesByName,
  }) {
    final groupLabels = seriesByName.keys.toList();
    final categories = [
      for (var i = 0; i < monthLabels.length; i++)
        ChartCategory(
          label: monthLabels[i],
          values: [for (final series in groupLabels) seriesByName[series]![i]],
        ),
    ];
    return AppBarChartData(categories: categories, groupLabels: groupLabels);
  }
}
