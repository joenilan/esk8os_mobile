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
    final validTemps = <int>[
      if (t.live && t.motorTempC != 0) t.motorTempC,
      if (t.live && t.escTempC != 0) t.escTempC,
      if (t.batteryLive && t.batteryTempC != 0) t.batteryTempC,
    ];
    final hottestTemp = validTemps.isEmpty
        ? null
        : validTemps.reduce((a, b) => a > b ? a : b);

    // Display values are whole numbers (precision lives in the logs); dropping
    // the decimals frees width so the cell numbers can be big and glanceable.
    const cellSize = 56.0;
    const cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 14);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        children: [
          // Speed — the hero. A big fixed size with balanced slack above/below
          // (spacers) so it reads as a composed layout, not a number adrift in a
          // void. The lower cluster anchors to the bottom.
          const Spacer(flex: 2),
          SpeedHero(
            value: t.live ? '${t.speed.toInt()}' : '--',
            unit: speedUnit,
            maxSize: 212,
          ),
          const Spacer(flex: 2),
          Divider(height: 1, thickness: 1, color: Esk8Theme.border),
          const SizedBox(height: 10),
          // Remote throttle/brake + signal-present icon (decoded PPM from the VESC).
          // Labelled so the bar isn't cryptic; the icon colour is the link state.
          Row(
            children: [
              Icon(
                t.live && t.remoteConnected
                    ? Icons.sports_esports
                    : Icons.sports_esports_outlined,
                size: 20,
                color: t.live && t.remoteConnected
                    ? Esk8Theme.green
                    : Esk8Theme.dim,
              ),
              const SizedBox(width: 8),
              Text('THROTTLE', style: Esk8Theme.labelStyle),
              const SizedBox(width: 12),
              Expanded(
                child: ThrottleBar(
                  throttle: t.live && t.remoteConnected ? t.throttle : 0,
                  height: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (t.batteryLive)
            BatteryMeter(percent: t.battery, cells: cells)
          else
            const _UnavailableBattery(),
          const SizedBox(height: 14),
          StatRow([
            StatTile(
              label: 'Watts',
              value: t.live ? '${t.watts}' : '--',
              unit: 'W',
              valueSize: cellSize,
              padding: cellPad,
              valueColor: t.live
                  ? Esk8Theme.wattsColor(t.watts)
                  : Esk8Theme.dim,
            ),
            // White, not green — green is reserved for genuine "good" signals
            // (battery zone, cool temps), so it stays meaningful rather than decor.
            StatTile(
              label: 'Volts',
              value: t.batteryLive ? t.volts.toStringAsFixed(1) : '--',
              unit: 'V',
              valueSize: cellSize,
              padding: cellPad,
              valueColor: t.batteryLive ? Esk8Theme.textPrimary : Esk8Theme.dim,
            ),
          ]),
          const SizedBox(height: 8),
          StatRow([
            StatTile(
              label: 'Range',
              value: t.batteryLive ? t.range.toStringAsFixed(1) : '--',
              unit: distUnit,
              valueSize: cellSize,
              padding: cellPad,
              valueColor: t.batteryLive ? null : Esk8Theme.dim,
            ),
            // Hottest of the three sensors — motor/battery often have no thermistor
            // (read 0), so showing motor alone misleads; surface the real worst temp.
            StatTile(
              label: 'Temp',
              value: hottestTemp?.toString() ?? '--',
              unit: '°C',
              valueSize: cellSize,
              padding: cellPad,
              valueColor: hottestTemp == null
                  ? Esk8Theme.dim
                  : _tempColor(hottestTemp),
            ),
          ]),
        ],
      ),
    );
  }
}

class _UnavailableBattery extends StatelessWidget {
  const _UnavailableBattery();

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    alignment: Alignment.center,
    decoration: BoxDecoration(border: Border.all(color: Esk8Theme.border)),
    child: Text(
      '--  BATTERY DATA',
      style: Esk8Theme.number(24, color: Esk8Theme.dim),
    ),
  );
}
