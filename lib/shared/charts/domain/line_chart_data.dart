import 'package:flutter/material.dart';

import 'chart_point.dart';

/// Library-agnostic input for [AppLineChart] — one or more [ChartSeries]
/// plotted on a shared x-axis. Callers build this from whatever provider
/// output they already have; [AppLineChart] alone knows how to turn it
/// into an `fl_chart` widget, so a future charting-library swap only
/// touches that one file.
class AppLineChartData {
  const AppLineChartData({required this.series, this.xAxisLabels});

  final List<ChartSeries> series;

  /// Tick labels for the x-axis, indexed the same way as each series'
  /// [ChartPoint.x] (0, 1, 2, ...) — e.g. day-of-month or week number
  /// labels. Omit to hide x-axis labels entirely.
  final List<String>? xAxisLabels;

  /// A single-series line — the spec's "Trend Chart" is architecturally
  /// just an [AppLineChartData] with one [ChartSeries], not a distinct
  /// chart type.
  factory AppLineChartData.trend({
    required List<ChartPoint> points,
    String seriesName = 'Trend',
    Color? color,
    List<String>? xAxisLabels,
  }) {
    return AppLineChartData(
      series: [ChartSeries(name: seriesName, points: points, color: color)],
      xAxisLabels: xAxisLabels,
    );
  }
}
