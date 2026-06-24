import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// POWER — mirrors the board's Power page: POWER / ENERGY / SPEED / SESSION
/// fieldsets with semantic value colours (duty & peak escalate to yellow/red,
/// regen is green).
class PowerView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const PowerView({super.key, required this.telemetry, this.settings});

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) return const WaitingForTelemetry();

    return PageChrome(
      sections: [
        FieldSection(
          title: 'Power',
          rows: [
            FieldRow(label: 'Motor', value: t.motorAmps.toStringAsFixed(1), unit: 'A'),
            FieldRow(label: 'Battery', value: t.batteryAmps.toStringAsFixed(1), unit: 'A'),
            FieldRow(label: 'Duty', value: '${t.duty}', unit: '%', valueColor: Esk8Theme.dutyColor(t.duty)),
            FieldRow(label: 'Peak (now)', value: '${t.peakWatts}', unit: 'W', valueColor: Esk8Theme.wattsColor(t.peakWatts)),
          ],
        ),
        FieldSection(
          title: 'Energy',
          rows: [
            FieldRow(label: 'Used', value: '${t.wattHours}', unit: 'Wh'),
            FieldRow(label: 'Regen', value: '+${t.regenWh}', unit: 'Wh', valueColor: Esk8Theme.green),
          ],
        ),
        // Speed max/avg lives on the TRIP page (deduped). Session mirrors the board:
        // session-max power + session-min voltage. (Uptime lives on SYSTEM.)
        FieldSection(
          title: 'Session',
          rows: [
            FieldRow(label: 'Max (ride)', value: '${t.maxWattsSession}', unit: 'W', valueColor: Esk8Theme.wattsColor(t.maxWattsSession)),
            FieldRow(label: 'Min Volt', value: t.minVolts.toStringAsFixed(1), unit: 'V'),
          ],
        ),
      ],
    );
  }
}
