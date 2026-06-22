import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// GRAPHS mirrors the board's live-graph page: a rolling history of the key
/// metrics rather than a single power trace. Three stacked, independently scaled
/// line charts (Speed / Power / Voltage) over the most recent ~60 samples.
class GraphsView extends StatefulWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const GraphsView({super.key, required this.telemetry, this.settings});

  @override
  State<GraphsView> createState() => _GraphsViewState();
}

class _GraphsViewState extends State<GraphsView> {
  static const int _maxPoints = 60;
  final Queue<double> _speed = Queue();
  final Queue<double> _watts = Queue();
  final Queue<double> _volts = Queue();

  @override
  void didUpdateWidget(GraphsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final t = widget.telemetry;
    if (t == null) return;
    // Append on each new frame (speed is the cheapest "did it change" proxy).
    if (oldWidget.telemetry == null || t.speed != oldWidget.telemetry!.speed || t.watts != oldWidget.telemetry!.watts) {
      _push(_speed, t.speed);
      _push(_watts, t.watts.toDouble());
      _push(_volts, t.volts);
    }
  }

  void _push(Queue<double> q, double v) {
    q.add(v);
    if (q.length > _maxPoints) q.removeFirst();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.telemetry == null) return const WaitingForTelemetry();
    if (_speed.isEmpty) {
      return const Center(child: Text('Collecting data…', style: TextStyle(color: Esk8Theme.textMuted)));
    }

    final speedUnit = widget.settings?.mph == true ? 'MPH' : 'KM/H';

    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 22, 12, 8),
        child: Column(
          children: [
            Expanded(child: _MetricChart(label: 'Speed', unit: speedUnit, data: _speed, color: Esk8Theme.accent)),
            const SizedBox(height: 16),
            Expanded(child: _MetricChart(label: 'Power', unit: 'W', data: _watts, color: const Color(0xFF4FC3F7))),
            const SizedBox(height: 16),
            Expanded(child: _MetricChart(label: 'Voltage', unit: 'V', data: _volts, color: Esk8Theme.yellow)),
          ],
        ),
    );
  }
}

class _MetricChart extends StatelessWidget {
  final String label;
  final String unit;
  final Queue<double> data;
  final Color color;

  const _MetricChart({required this.label, required this.unit, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final values = data.toList();
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];
    double minY = values.reduce((a, b) => a < b ? a : b);
    double maxY = values.reduce((a, b) => a > b ? a : b);
    if (maxY - minY < 1) maxY = minY + 1; // avoid a flat-line zero range
    final pad = (maxY - minY) * 0.15;
    minY -= pad;
    maxY += pad;
    final current = values.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SectionTitle(label),
            Text('${current.toStringAsFixed(1)} $unit',
                style: Esk8Theme.number(22, color: color)),
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
                  belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.18)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
