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
    final distUnit = isMph ? 'mi' : 'km';
    final effUnit = isMph ? 'wh/mi' : 'wh/km';

    return PageChrome(
      sections: [
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
