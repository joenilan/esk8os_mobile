import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../widgets/esk8_widgets.dart';

/// TRIP (stats) — mirrors the board's Trip page: THIS TRIP (time / distance /
/// avg / max / efficiency) and ODOMETER (lifetime total). Distinct from the GPS
/// map page, which is an app-only extra.
class TripStatsView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const TripStatsView({super.key, required this.telemetry, required this.settings});

  static String _hms(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) return const WaitingForTelemetry();

    final isMph = settings?.mph == true;
    final distUnit = isMph ? 'mi' : 'km';
    final speedUnit = isMph ? 'mph' : 'km/h';
    final effUnit = isMph ? 'wh/mi' : 'wh/km';

    return PageChrome(
      sections: [
        FieldSection(
          title: 'This Trip',
          rows: [
            FieldRow(label: 'Time', value: _hms(t.rideSeconds)),
            FieldRow(label: 'Distance', value: t.trip.toStringAsFixed(2), unit: distUnit),
            FieldRow(label: 'Avg', value: t.avgSpeed.toStringAsFixed(1), unit: speedUnit),
            FieldRow(label: 'Max', value: t.maxSpeed.toStringAsFixed(1), unit: speedUnit),
            FieldRow(label: 'Efficiency', value: '${t.efficiency}', unit: effUnit),
          ],
        ),
        FieldSection(
          title: 'Odometer',
          rows: [
            FieldRow(label: 'Total', value: t.odometer.toStringAsFixed(1), unit: distUnit),
          ],
        ),
      ],
    );
  }
}
