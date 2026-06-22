import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// DASH — mirrors the board's Dash page: TEMPS and RANGE as "fieldset" sections
/// with label-left / value-right rows.
class DashView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const DashView({super.key, required this.telemetry, required this.settings});

  static Color _temp(int c) {
    if (c >= 70) return Esk8Theme.danger;
    if (c >= 55) return Esk8Theme.yellow;
    return Esk8Theme.green;
  }

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) return const WaitingForTelemetry();

    final isMph = settings?.mph == true;
    final speedUnit = isMph ? 'MPH' : 'KM/H';
    final distUnit = isMph ? 'mi' : 'km';
    final effUnit = isMph ? 'wh/mi' : 'wh/km';

    return PageChrome(
      sections: [
        // Speed + volts/watts header — the detailed companion to the HUD.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpeedHero(value: t.speed.toStringAsFixed(0), unit: speedUnit, maxSize: 104),
            const SizedBox(height: 10),
            StatRow([
              StatTile(label: 'Volts', value: t.volts.toStringAsFixed(0), unit: 'V', valueSize: 44, valueColor: Esk8Theme.green),
              StatTile(label: 'Watts', value: '${t.watts}', unit: 'W', valueSize: 44, valueColor: Esk8Theme.wattsColor(t.watts)),
            ]),
          ],
        ),
        FieldSection(
          title: 'Temps',
          rows: [
            FieldRow(label: 'Motor', value: '${t.motorTempC}', unit: '°C', valueColor: _temp(t.motorTempC)),
            FieldRow(label: 'Battery', value: '${t.batteryTempC}', unit: '°C', valueColor: _temp(t.batteryTempC)),
            FieldRow(label: 'ESC', value: '${t.escTempC}', unit: '°C', valueColor: _temp(t.escTempC)),
          ],
        ),
        FieldSection(
          title: 'Range',
          rows: [
            FieldRow(label: 'Estimated', value: t.estRange.toStringAsFixed(1), unit: distUnit),
            FieldRow(label: 'Remaining', value: t.range.toStringAsFixed(1), unit: distUnit),
            FieldRow(label: 'Avg', value: '${t.efficiency}', unit: effUnit),
          ],
        ),
      ],
    );
  }
}
