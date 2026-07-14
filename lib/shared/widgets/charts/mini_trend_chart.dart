import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A minimal sparkline — no axes, no grid, no dots — for compact "how's
/// this trending" glances (e.g. the Dashboard hero balance card). Values
/// are plotted left-to-right in the order given; a flat/empty series still
/// renders (as a flat line) rather than throwing.
class MiniTrendChart extends StatelessWidget {
  const MiniTrendChart({super.key, required this.values, required this.color, this.height = 40});

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = values.isEmpty ? [0.0, 0.0] : values;
    final minY = points.reduce((a, b) => a < b ? a : b);
    final maxY = points.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY) * 0.15;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i])],
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
