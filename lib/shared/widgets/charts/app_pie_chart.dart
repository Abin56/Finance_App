import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../charts/domain/pie_chart_data.dart';

/// Renders [AppPieChartData] via `fl_chart` — the one place any new
/// screen/card needs to know `fl_chart`'s own API for pie charts.
/// Percent-of-total is computed here from each slice's relative value,
/// never passed in precomputed.
class AppPieChart extends StatelessWidget {
  const AppPieChart({super.key, required this.data, this.size = 160, this.centerSpaceRadius = 40});

  final AppPieChartData data;
  final double size;
  final double centerSpaceRadius;

  @override
  Widget build(BuildContext context) {
    final total = data.slices.fold(0.0, (sum, s) => sum + s.value);
    if (data.slices.isEmpty || total <= 0) return SizedBox(height: size, width: size);

    return SizedBox(
      height: size,
      width: size,
      child: PieChart(
        PieChartData(
          centerSpaceRadius: centerSpaceRadius,
          sectionsSpace: 2,
          sections: [
            for (final slice in data.slices)
              PieChartSectionData(
                value: slice.value,
                color: slice.color,
                title: '${(slice.value / total * 100).round()}%',
                titleStyle: context.textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                radius: size / 2 - centerSpaceRadius,
              ),
          ],
        ),
      ),
    );
  }
}
