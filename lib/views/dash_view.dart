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

  static String _warningLabel(int code) => switch (code) {
    3 => 'Limp home',
    2 => 'Voltage sag',
    1 => 'Turn home',
    _ => 'OK',
  };

  static Color _warningColor(int code) => switch (code) {
    3 => Esk8Theme.danger,
    2 => Esk8Theme.orange,
    1 => Esk8Theme.yellow,
    _ => Esk8Theme.green,
  };

  static String _duration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
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
            SpeedHero(
              value: t.live ? '${t.speed.toInt()}' : '--',
              unit: speedUnit,
              maxSize: 92,
            ),
            const SizedBox(height: 10),
            StatRow([
              StatTile(
                label: 'Volts',
                value: t.batteryLive ? t.volts.toStringAsFixed(1) : '--',
                unit: 'V',
                valueSize: 40,
                // White, matching the HUD — green stays reserved for the safety
                // zones on this page (current/temp/range), where it means "safe".
                valueColor: t.batteryLive
                    ? Esk8Theme.textPrimary
                    : Esk8Theme.dim,
              ),
              StatTile(
                label: 'Watts',
                value: t.live ? '${t.watts}' : '--',
                unit: 'W',
                valueSize: 40,
                valueColor: t.live
                    ? Esk8Theme.wattsColor(t.watts)
                    : Esk8Theme.dim,
              ),
            ]),
          ],
        ),
        // CURRENT — the safety read. Per-motor so each can be checked against the
        // VESC's motor-current limit; battery amps + duty alongside.
        FieldSection(
          title: 'Current',
          rows: [
            FieldRow(
              label: 'Motor 1',
              value: t.live ? t.masterMotorAmps.toStringAsFixed(1) : '--',
              unit: 'A',
              valueColor: t.live ? _amp(t.masterMotorAmps) : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Motor 2',
              value: t.live ? t.slaveMotorAmps.toStringAsFixed(1) : '--',
              unit: 'A',
              valueColor: t.live ? _amp(t.slaveMotorAmps) : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Battery',
              value: t.live ? t.batteryAmps.toStringAsFixed(1) : '--',
              unit: 'A',
              valueColor: t.live ? null : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Duty',
              value: t.live ? '${t.duty}' : '--',
              unit: '%',
              valueColor: t.live ? Esk8Theme.dutyColor(t.duty) : Esk8Theme.dim,
            ),
          ],
        ),
        FieldSection(
          title: 'Temps',
          rows: [
            FieldRow(
              label: 'Motor',
              value: t.live && t.motorTempC != 0 ? '${t.motorTempC}' : '--',
              unit: '°C',
              valueColor: t.live && t.motorTempC != 0
                  ? _temp(t.motorTempC)
                  : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'ESC',
              value: t.live && t.escTempC != 0 ? '${t.escTempC}' : '--',
              unit: '°C',
              valueColor: t.live && t.escTempC != 0
                  ? _temp(t.escTempC)
                  : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Battery',
              value: t.batteryLive && t.batteryTempC != 0
                  ? '${t.batteryTempC}'
                  : '--',
              unit: '°C',
              valueColor: t.batteryLive && t.batteryTempC != 0
                  ? _temp(t.batteryTempC)
                  : Esk8Theme.dim,
            ),
          ],
        ),
        FieldSection(
          title: 'Range',
          rows: [
            FieldRow(
              label: 'Home remaining',
              value: t.batteryLive ? t.range.toStringAsFixed(1) : '--',
              unit: distUnit,
              valueColor: !t.batteryLive
                  ? Esk8Theme.dim
                  : t.range <= 2
                  ? Esk8Theme.danger
                  : Esk8Theme.green,
            ),
            FieldRow(
              label: 'Limp remaining',
              value: t.batteryLive ? t.limpRange.toStringAsFixed(1) : '--',
              unit: distUnit,
              valueColor: !t.batteryLive
                  ? Esk8Theme.dim
                  : t.limpRange <= 2
                  ? Esk8Theme.danger
                  : Esk8Theme.yellow,
            ),
            FieldRow(
              label: 'Home full',
              value: t.batteryLive ? t.estRange.toStringAsFixed(1) : '--',
              unit: distUnit,
              valueColor: t.batteryLive ? null : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Limp full',
              value: t.batteryLive ? t.limpEstRange.toStringAsFixed(1) : '--',
              unit: distUnit,
              valueColor: t.batteryLive ? null : Esk8Theme.dim,
            ),
          ],
        ),
        FieldSection(
          title: 'Battery Safety',
          rows: [
            FieldRow(
              label: 'Warning',
              value: t.live ? _warningLabel(t.rangeWarning) : '--',
              valueColor: t.live
                  ? _warningColor(t.rangeWarning)
                  : Esk8Theme.dim,
              valueSize: 24,
            ),
            FieldRow(
              label: 'Loaded cell',
              value: !t.batteryLive
                  ? '--'
                  : t.cellVolts > 0
                  ? t.cellVolts.toStringAsFixed(2)
                  : (t.volts / (settings?.batterySeries ?? 10)).toStringAsFixed(
                      2,
                    ),
              unit: 'V',
              valueColor: !t.batteryLive
                  ? Esk8Theme.dim
                  : settings != null && t.cellVolts <= settings!.homeCellV
                  ? Esk8Theme.orange
                  : Esk8Theme.textPrimary,
            ),
            FieldRow(
              label: 'Lowest loaded',
              value: !t.live
                  ? '--'
                  : t.minLoadedVolts > 0
                  ? t.minLoadedVolts.toStringAsFixed(1)
                  : t.minVolts.toStringAsFixed(1),
              unit: 'V',
              valueColor: t.live ? null : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Max battery',
              value: t.live ? t.maxBatteryAmps.toStringAsFixed(1) : '--',
              unit: 'A',
              valueColor: t.live
                  ? _amp(t.maxBatteryAmps, limit: 36)
                  : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Below home',
              value: _duration(t.homeVoltageSeconds),
              trailing: '${t.sagEvents}x',
              trailingColor: t.sagEvents > 0 ? Esk8Theme.orange : Esk8Theme.dim,
              valueSize: 24,
            ),
            FieldRow(
              label: 'Below limp',
              value: _duration(t.limpVoltageSeconds),
              valueColor: t.limpVoltageSeconds > 0
                  ? Esk8Theme.danger
                  : Esk8Theme.textPrimary,
              valueSize: 24,
            ),
          ],
        ),
      ],
    );
  }
}
