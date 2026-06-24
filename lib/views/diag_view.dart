import 'package:flutter/material.dart';

import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// DIAG — remote/throttle + VESC diagnostics. The remote throttle is the VESC's
/// decoded PPM input (-1..1), so it reflects the VESC's PPM calibration, not the
/// raw receiver. Remote battery/buttons aren't available over PPM (one-way).
class DiagView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const DiagView({super.key, required this.telemetry, required this.settings});

  // VESC mc_fault_code -> short name (common codes; falls back to the number).
  static String _faultName(int code) {
    switch (code) {
      case 0:
        return 'NONE';
      case 1:
        return 'OVER-VOLTAGE';
      case 2:
        return 'UNDER-VOLTAGE';
      case 3:
        return 'DRV';
      case 4:
        return 'ABS OVER-CURRENT';
      case 5:
        return 'ESC OVER-TEMP';
      case 6:
        return 'MOTOR OVER-TEMP';
      case 7:
        return 'GATE DRV OVER-V';
      case 8:
        return 'GATE DRV UNDER-V';
      case 9:
        return 'MCU UNDER-V';
      case 10:
        return 'WATCHDOG RESET';
      case 11:
        return 'ENCODER SPI';
      default:
        return 'FAULT #$code';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) return const WaitingForTelemetry();

    final connected = t.remoteConnected;
    final pct = (t.throttle.abs() * 100).round();
    final isBrake = t.throttle < -0.02;
    final isAccel = t.throttle > 0.02;
    final throttleLabel = !connected
        ? 'NO SIGNAL'
        : isAccel
            ? 'ACCEL $pct%'
            : isBrake
                ? 'BRAKE $pct%'
                : 'CENTER';
    final throttleColor = !connected
        ? Esk8Theme.dim
        : isAccel
            ? Esk8Theme.green
            : isBrake
                ? Esk8Theme.danger
                : Esk8Theme.textPrimary;

    final faultOk = t.fault == 0;

    return PageChrome(
      sections: [
        FieldSection(
          title: 'Remote',
          rows: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('BRAKE',
                          style: TextStyle(fontSize: 11, color: Esk8Theme.danger, letterSpacing: 1)),
                      Text('ACCEL',
                          style: TextStyle(fontSize: 11, color: Esk8Theme.green, letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ThrottleBar(throttle: connected ? t.throttle : 0),
                  const SizedBox(height: 6),
                  Text(throttleLabel,
                      style: TextStyle(
                          fontSize: 16, color: throttleColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
            ),
            FieldRow(
              label: 'Signal',
              value: connected ? 'CONNECTED' : 'NO SIGNAL',
              valueColor: connected ? Esk8Theme.green : Esk8Theme.danger,
              valueSize: 20,
            ),
          ],
        ),
        FieldSection(
          title: 'VESC',
          rows: [
            FieldRow(
              label: 'Fault',
              value: faultOk ? 'OK' : _faultName(t.fault),
              valueColor: faultOk ? Esk8Theme.green : Esk8Theme.danger,
              valueSize: 20,
            ),
            if (t.lastFault != 0)
              FieldRow(
                label: 'Last fault',
                value: _faultName(t.lastFault),
                valueColor: Esk8Theme.yellow,
                valueSize: 20,
              ),
            FieldRow(
              label: 'Firmware',
              value: t.vescFw.isNotEmpty ? t.vescFw : '—',
              valueSize: 22,
            ),
            FieldRow(
              label: '2nd motor (CAN)',
              value: t.slaveOnline ? 'ONLINE' : 'OFFLINE',
              valueColor: t.slaveOnline ? Esk8Theme.green : Esk8Theme.dim,
              valueSize: 20,
            ),
          ],
        ),
        FieldSection(
          title: 'Motors',
          rows: [
            FieldRow(label: 'Master current', value: t.masterMotorAmps.toStringAsFixed(1), unit: 'A'),
            FieldRow(label: 'Slave current', value: t.slaveMotorAmps.toStringAsFixed(1), unit: 'A'),
          ],
        ),
        FieldSection(
          title: 'System',
          rows: [
            FieldRow(label: 'Runtime', value: _hms(t.rideSeconds), valueSize: 22),
            FieldRow(label: 'Link', value: 'BLE', valueColor: Esk8Theme.green, valueSize: 20),
          ],
        ),
      ],
    );
  }

  static String _hms(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}
