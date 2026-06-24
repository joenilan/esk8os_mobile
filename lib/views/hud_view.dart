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
    final hottestTemp = [t.motorTempC, t.escTempC, t.batteryTempC].reduce((a, b) => a > b ? a : b);

    // Display values are whole numbers (precision lives in the logs); dropping
    // the decimals frees width so the cell numbers can be big and glanceable.
    const cellSize = 56.0;
    const cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 14);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        children: [
          // Speed — the hero. Given as much room as the layout allows (the
          // surrounding gaps are tight) so the FittedBox scales it up large.
          Expanded(child: Center(child: SpeedHero(value: t.speed.toStringAsFixed(0), unit: speedUnit))),
          const Divider(height: 1, thickness: 1, color: Esk8Theme.border),
          const SizedBox(height: 6),
          // Remote throttle/brake + signal-present icon (decoded PPM from the VESC).
          Row(
            children: [
              Icon(
                t.remoteConnected ? Icons.sports_esports : Icons.sports_esports_outlined,
                size: 20,
                color: t.remoteConnected ? Esk8Theme.green : Esk8Theme.dim,
              ),
              const SizedBox(width: 8),
              Expanded(child: ThrottleBar(throttle: t.remoteConnected ? t.throttle : 0, height: 14)),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedBattery(percent: t.battery, cells: cells),
          const SizedBox(height: 2),
          Text('${t.battery}%', style: Esk8Theme.number(38)),
          const SizedBox(height: 10),
          StatRow([
            StatTile(label: 'Watts', value: '${t.watts}', unit: 'W', valueSize: cellSize, padding: cellPad, valueColor: Esk8Theme.wattsColor(t.watts)),
            StatTile(label: 'Volts', value: t.volts.toStringAsFixed(1), unit: 'V', valueSize: cellSize, padding: cellPad, valueColor: Esk8Theme.green),
          ]),
          const SizedBox(height: 8),
          StatRow([
            StatTile(label: 'Range', value: t.range.toStringAsFixed(1), unit: distUnit, valueSize: cellSize, padding: cellPad),
            // Hottest of the three sensors — motor/battery often have no thermistor
            // (read 0), so showing motor alone misleads; surface the real worst temp.
            StatTile(label: 'Temp', value: '$hottestTemp', unit: '°C', valueSize: cellSize, padding: cellPad, valueColor: _tempColor(hottestTemp)),
          ]),
        ],
      ),
    );
  }
}
