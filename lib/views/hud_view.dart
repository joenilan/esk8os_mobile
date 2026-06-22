import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// HUD — big speed, segmented battery + %, and a 2×2 of cells (watts / volts /
/// range / temp) with semantic value colours. The top/bottom identifying panels
/// and page dots are drawn by the dashboard around all pages.
class HudView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const HudView({super.key, required this.telemetry, required this.settings});

  static Color _tempColor(int c) {
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
    final distUnit = isMph ? 'MI' : 'KM';
    final cells = settings?.batterySeries ?? 12;

    // Display values are whole numbers (precision lives in the logs); dropping
    // the decimals frees width so the cell numbers can be big and glanceable.
    const cellSize = 56.0;
    const cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 18);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          // Speed — big but not overpowering, MPH snug underneath.
          Expanded(child: Center(child: SpeedHero(value: t.speed.toStringAsFixed(0), unit: speedUnit))),
          const Divider(height: 1, thickness: 1, color: Esk8Theme.border),
          const SizedBox(height: 10),
          SegmentedBattery(percent: t.battery, cells: cells),
          const SizedBox(height: 2),
          Text('${t.battery}%', style: Esk8Theme.number(38)),
          const SizedBox(height: 14),
          StatRow([
            StatTile(label: 'Watts', value: '${t.watts}', unit: 'W', valueSize: cellSize, padding: cellPad, valueColor: Esk8Theme.wattsColor(t.watts)),
            StatTile(label: 'Volts', value: t.volts.toStringAsFixed(0), unit: 'V', valueSize: cellSize, padding: cellPad, valueColor: Esk8Theme.green),
          ]),
          const SizedBox(height: 12),
          StatRow([
            StatTile(label: 'Range', value: t.range.toStringAsFixed(0), unit: distUnit, valueSize: cellSize, padding: cellPad),
            StatTile(label: 'Temp', value: '${t.motorTempC}', unit: '°C', valueSize: cellSize, padding: cellPad, valueColor: _tempColor(t.motorTempC)),
          ]),
        ],
      ),
    );
  }
}
