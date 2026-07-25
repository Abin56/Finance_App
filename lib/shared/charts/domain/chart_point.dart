import 'package:flutter/material.dart';

/// One point in a line-chart series — an x/y pair plus an optional label
/// for axis ticks or tooltips. [x] is a plain double (not a [DateTime])
/// so a series can be indexed by day, week, or category ordinal alike;
/// callers own the mapping from their own domain values to an index.
class ChartPoint {
  const ChartPoint({required this.x, required this.y, this.label});

  final double x;
  final double y;
  final String? label;
}

/// One named line within an [AppLineChartData] — e.g. "Income" vs
/// "Expenses" plotted on the same axes.
class ChartSeries {
  const ChartSeries({required this.name, required this.points, this.color});

  final String name;
  final List<ChartPoint> points;
  final Color? color;
}
