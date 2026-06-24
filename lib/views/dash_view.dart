import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// DASH — the detailed "is my board safe?" page: live per-motor + battery current
/// (so you can see you're under the configured motor limits), duty, voltage/watts,
/// temps, and range. The denser companion to the glanceable HUD.
class DashView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const DashView({super.key, required this.telemetry, required this.settings});

  static Color _temp(int c) {
    if (c >= 70) return Esk8Theme.danger;
    if (c >= 55) return Esk8Theme.yellow;
    return Esk8Theme.green;
  }

  // Motor current vs the per-VESC limit (default 18 A): green safe, escalating to
  // red as it approaches/exceeds. Uses abs() so braking (negative) colours too.
  static Color _amp(double a, {double limit = 18}) {
    final m = a.abs();
    if (m >= limit) return Esk8Theme.danger;
    if (m >= limit * 0.85) return Esk8Theme.orange;
    if (m >= limit * 0.65) return Esk8Theme.yellow;
    return Esk8Theme.green;
  }

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) return const WaitingForTelemetry();

    final isMph = settings?.mph == true;
    final speedUnit = isMph ? 'MPH' : 'KM/H';
    final distUnit = isMph ? 'mi' : 'km';

    return PageChrome(
      sections: [
        // Speed + volts/watts header — the detailed companion to the HUD.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpeedHero(value: '${t.speed.toInt()}', unit: speedUnit, maxSize: 92),
            const SizedBox(height: 10),
            StatRow([
              StatTile(label: 'Volts', value: t.volts.toStringAsFixed(1), unit: 'V', valueSize: 40, valueColor: Esk8Theme.green),
              StatTile(label: 'Watts', value: '${t.watts}', unit: 'W', valueSize: 40, valueColor: Esk8Theme.wattsColor(t.watts)),
            ]),
          ],
        ),
        // CURRENT — the safety read. Per-motor so each can be checked against the
        // VESC's motor-current limit; battery amps + duty alongside.
        FieldSection(
          title: 'Current',
          rows: [
            FieldRow(label: 'Motor 1', value: t.masterMotorAmps.toStringAsFixed(1), unit: 'A', valueColor: _amp(t.masterMotorAmps)),
            FieldRow(label: 'Motor 2', value: t.slaveMotorAmps.toStringAsFixed(1), unit: 'A', valueColor: _amp(t.slaveMotorAmps)),
            FieldRow(label: 'Battery', value: t.batteryAmps.toStringAsFixed(1), unit: 'A'),
            FieldRow(label: 'Duty', value: '${t.duty}', unit: '%', valueColor: Esk8Theme.dutyColor(t.duty)),
          ],
        ),
        FieldSection(
          title: 'Temps',
          rows: [
            FieldRow(label: 'Motor', value: '${t.motorTempC}', unit: '°C', valueColor: _temp(t.motorTempC)),
            FieldRow(label: 'ESC', value: '${t.escTempC}', unit: '°C', valueColor: _temp(t.escTempC)),
            FieldRow(label: 'Battery', value: '${t.batteryTempC}', unit: '°C', valueColor: _temp(t.batteryTempC)),
          ],
        ),
        FieldSection(
          title: 'Range',
          rows: [
            FieldRow(label: 'Estimated', value: t.estRange.toStringAsFixed(1), unit: distUnit),
            FieldRow(label: 'Remaining', value: t.range.toStringAsFixed(1), unit: distUnit),
          ],
        ),
      ],
    );
  }
}
