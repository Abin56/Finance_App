import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../charts/domain/chart_point.dart';
import '../../charts/domain/line_chart_data.dart';

/// Renders [AppLineChartData] via `fl_chart` — the one place any new
/// screen/card needs to know `fl_chart`'s own API. Every caller builds an
/// [AppLineChartData] from its own provider output and hands it here;
/// swapping the underlying charting library only ever means changing this
/// file.
class AppLineChart extends StatelessWidget {
  const AppLineChart({super.key, required this.data, this.height = 200, this.showDots = false});

  final AppLineChartData data;
  final double height;
  final bool showDots;

  @override
  Widget build(BuildContext context) {
    final allPoints = [for (final s in data.series) ...s.points];
    if (allPoints.isEmpty) return SizedBox(height: height);

    final minY = allPoints.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = allPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY) * 0.15;
    final defaultColors = [context.colors.primary, context.colors.secondary, context.colors.tertiary];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: data.xAxisLabels != null,
                getTitlesWidget: (value, meta) {
                  final labels = data.xAxisLabels;
                  final index = value.toInt();
                  if (labels == null || index < 0 || index >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[index], style: context.textTheme.bodySmall),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            for (var i = 0; i < data.series.length; i++)
              _lineBar(data.series[i], defaultColors[i % defaultColors.length]),
          ],
        ),
      ),
    );
  }

  LineChartBarData _lineBar(ChartSeries series, Color fallbackColor) {
    final color = series.color ?? fallbackColor;
    return LineChartBarData(
      spots: [for (final p in series.points) FlSpot(p.x, p.y)],
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(show: showDots),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
