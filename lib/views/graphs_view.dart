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
              values: [for (final t in samples) t.live ? t.speed : null],
              color: Esk8Theme.accent,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _MetricChart(
              label: 'Power',
              unit: 'W',
              values: [
                for (final t in samples) t.live ? t.watts.toDouble() : null,
              ],
              color: const Color(0xFF4FC3F7),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _MetricChart(
              label: 'Voltage',
              unit: 'V',
              values: [for (final t in samples) t.batteryLive ? t.volts : null],
              color: Esk8Theme.yellow,
            ),
          ),
          const SizedBox(height: 12),
          _SessionPeaks(t: telemetry!, speedUnit: speedUnit),
        ],
      ),
    );
  }
}

/// A glanceable strip of this session's records — the peaks that don't fit the
/// live cards: top speed, biggest power draw, peak motor + battery current, and
/// the lowest loaded voltage (worst sag). Reset with the board trip.
class _SessionPeaks extends StatelessWidget {
  final Telemetry t;
  final String speedUnit;

  const _SessionPeaks({required this.t, required this.speedUnit});

  @override
  Widget build(BuildContext context) {
    final minV = t.minLoadedVolts > 0 ? t.minLoadedVolts : t.minVolts;
    final cells = <Widget>[
      _cell('MAX SPD', _fmt(t.maxSpeed, 1), speedUnit, Esk8Theme.accent),
      _cell(
        'MAX PWR',
        t.maxWattsSession > 0 ? '${t.maxWattsSession}' : '—',
        'W',
        const Color(0xFF4FC3F7),
      ),
      _cell('PK MOTOR', _fmt(t.maxMotorAmps, 0), 'A', Esk8Theme.orange),
      _cell('PK BATT', _fmt(t.maxBatteryAmps, 0), 'A', Esk8Theme.green),
      _cell('MIN V', _fmt(minV, 1), 'V', Esk8Theme.yellow),
    ];
    return Container(
      decoration: Esk8Theme.panelBox(),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) Container(width: 1, height: 34, color: Esk8Theme.border),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }

  static String _fmt(double v, int dp) => v > 0 ? v.toStringAsFixed(dp) : '—';

  Widget _cell(String label, String value, String unit, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Esk8Theme.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            text: value,
            style: Esk8Theme.number(20, color: color),
            children: [
              TextSpan(
                text: ' $unit',
                style: TextStyle(
                  fontSize: 10,
                  color: Esk8Theme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricChart extends StatelessWidget {
  final String label;
  final String unit;
  final List<double?> values;
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
      for (var i = 0; i < values.length; i++)
        values[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), values[i]!),
    ];
    final valid = values.whereType<double>().toList(growable: false);
    if (valid.isEmpty) {
      return Center(
        child: Text(
          '$label unavailable',
          style: TextStyle(color: Esk8Theme.dim),
        ),
      );
    }
    double minY = valid.reduce((a, b) => a < b ? a : b);
    double maxY = valid.reduce((a, b) => a > b ? a : b);
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
                  current == null
                      ? '-- $unit'
                      : '${current.toStringAsFixed(1)} $unit',
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
