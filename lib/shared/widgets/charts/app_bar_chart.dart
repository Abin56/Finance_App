import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../charts/domain/bar_chart_data.dart';

/// Renders [AppBarChartData] via `fl_chart` — the one place any new
/// screen/card needs to know `fl_chart`'s own API for bar charts.
class AppBarChart extends StatelessWidget {
  const AppBarChart({super.key, required this.data, this.height = 200});

  final AppBarChartData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.categories.isEmpty) return SizedBox(height: height);

    final maxY = data.categories.expand((c) => c.values).fold(0.0, (max, v) => v > max ? v : max);
    final chartMax = maxY == 0 ? 1.0 : maxY * 1.15;
    final defaultColors = [context.colors.primary, context.colors.secondary, context.colors.tertiary];

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: chartMax,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.categories.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSizes.xs),
                    child: Text(data.categories[index].label, style: context.textTheme.bodySmall),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.categories.length; i++) _group(i, data.categories[i], defaultColors),
          ],
        ),
      ),
    );
  }

  BarChartGroupData _group(int index, ChartCategory category, List<Color> defaultColors) {
    return BarChartGroupData(
      x: index,
      barsSpace: 6,
      barRods: [
        for (var i = 0; i < category.values.length; i++)
          BarChartRodData(
            toY: category.values[i],
            color: category.colors?[i] ?? defaultColors[i % defaultColors.length],
            width: category.values.length > 1 ? 10 : 16,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
      ],
    );
  }
}
