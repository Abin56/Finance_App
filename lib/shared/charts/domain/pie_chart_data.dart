import 'package:flutter/material.dart';

/// One wedge in an [AppPieChartData].
class ChartSlice {
  const ChartSlice({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;
}

/// Library-agnostic input for [AppPieChart] — a list of [ChartSlice]
/// wedges. Percent-of-total is derived from the slices' relative [
/// ChartSlice.value]s by the rendering widget, never precomputed here.
class AppPieChartData {
  const AppPieChartData({required this.slices});

  final List<ChartSlice> slices;

  /// The spec's "Category Chart" — a breakdown by category is just an
  /// [AppPieChartData] built from category totals, not a distinct chart
  /// type. Callers with an existing per-category domain model (e.g.
  /// `CategorySpendingEntry`) should adapt it to [ChartSlice]s themselves
  /// rather than this factory inventing a second category shape.
  factory AppPieChartData.byCategory(List<ChartSlice> categorySlices) {
    return AppPieChartData(slices: categorySlices);
  }
}
