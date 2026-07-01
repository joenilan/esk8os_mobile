import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// GRAPHS mirrors the board's live-graph page. The rolling samples are owned by
/// DashboardPage so they keep collecting even when this page is offscreen.
class GraphsView extends StatelessWidget {
  final Telemetry? telemetry;
  final List<Telemetry> history;
  final BoardSettings? settings;

  const GraphsView({
    super.key,
    required this.telemetry,
    required this.history,
    this.settings,
  });

  @override
  Widget build(BuildContext context) {
    if (telemetry == null) return const WaitingForTelemetry();
    if (history.isEmpty) {
      return Center(
        child: Text(
          'Collecting data...',
          style: TextStyle(color: Esk8Theme.textMuted),
        ),
      );
    }

    final speedUnit = settings?.mph == true ? 'MPH' : 'KM/H';
    final samples = List<Telemetry>.of(history, growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 44, 12, 8),
      child: Column(
        children: [
          Expanded(
            child: _MetricChart(
              label: 'Speed',
              unit: speedUnit,
              values: [for (final t in samples) t.speed],
              color: Esk8Theme.accent,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _MetricChart(
              label: 'Power',
              unit: 'W',
              values: [for (final t in samples) t.watts.toDouble()],
              color: const Color(0xFF4FC3F7),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _MetricChart(
              label: 'Voltage',
              unit: 'V',
              values: [for (final t in samples) t.volts],
              color: Esk8Theme.yellow,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChart extends StatelessWidget {
  final String label;
  final String unit;
  final List<double> values;
  final Color color;

  const _MetricChart({
    required this.label,
    required this.unit,
    required this.values,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    double minY = values.reduce((a, b) => a < b ? a : b);
    double maxY = values.reduce((a, b) => a > b ? a : b);
    if (maxY - minY < 1) maxY = minY + 1;
    final pad = (maxY - minY) * 0.15;
    minY -= pad;
    maxY += pad;
    final current = values.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SectionTitle(label),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '${current.toStringAsFixed(1)} $unit',
                  style: Esk8Theme.number(22, color: color),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (values.length - 1).toDouble().clamp(1, double.infinity),
              minY: minY,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
