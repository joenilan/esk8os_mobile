import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../ble/esk8os_ble.dart';

class GraphsView extends StatefulWidget {
  final Telemetry? telemetry;

  const GraphsView({super.key, required this.telemetry});

  @override
  State<GraphsView> createState() => _GraphsViewState();
}

class _GraphsViewState extends State<GraphsView> {
  static const int _maxDataPoints = 60; // 60 points of history
  final Queue<FlSpot> _spots = Queue();
  double _time = 0;

  @override
  void didUpdateWidget(GraphsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.telemetry != null && (oldWidget.telemetry == null || widget.telemetry!.watts != oldWidget.telemetry!.watts)) {
      _addSpot(widget.telemetry!.watts.toDouble());
    }
  }

  void _addSpot(double watts) {
    _spots.add(FlSpot(_time, watts));
    _time += 1; // Arbitrary time step
    if (_spots.length > _maxDataPoints) {
      _spots.removeFirst();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.telemetry == null) {
      return const Center(child: Text('Waiting for telemetry…'));
    }

    if (_spots.isEmpty) {
      return const Center(child: Text('Collecting data…'));
    }

    // Determine Y axis range
    double maxY = 1000;
    for (final spot in _spots) {
      if (spot.y > maxY) maxY = spot.y + 200;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 24.0, left: 16.0, top: 48.0, bottom: 24.0),
      child: Column(
        children: [
          const Text('POWER GRAPH (W)', style: TextStyle(fontSize: 18, color: Colors.grey, letterSpacing: 2)),
          const SizedBox(height: 32),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 12));
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: _spots.first.x,
                maxX: _spots.last.x,
                minY: 0,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots.toList(),
                    isCurved: true,
                    color: const Color(0xFFB950D7),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFB950D7).withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
