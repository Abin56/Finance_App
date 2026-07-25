import 'package:flutter/material.dart';

import '../../../features/reports/presentation/widgets/reports_category_list.dart';
import 'pie_chart_data.dart';

/// Adapts the Reports feature's existing [CategorySpendingEntry] list into
/// [AppPieChartData] for chart rendering — [CategorySpendingEntry] itself
/// stays the domain shape non-chart UI (the ranked list) already uses;
/// this only exists so a chart view alongside that list doesn't need its
/// own second category shape.
AppPieChartData categorySpendingEntriesToPieData(List<CategorySpendingEntry> entries) {
  return AppPieChartData(
    slices: [
      for (final entry in entries)
        ChartSlice(label: entry.category.name, value: entry.amount, color: Color(entry.category.colorValue)),
    ],
  );
}
