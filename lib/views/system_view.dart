import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// SYSTEM — mirrors the board's System page (device / runtime / status). The
/// board's firmware-version + memory aren't in the BLE payload yet, so this
/// shows what the link exposes: runtime, fault, and the active board config.
class SystemView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const SystemView({super.key, required this.telemetry, required this.settings});

  static String _hms(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) return const WaitingForTelemetry();
    final s = settings;

    final faultOk = t.fault == 0;

    return PageChrome(
      sections: [
        FieldSection(
          title: 'System',
          rows: [
            FieldRow(label: 'Runtime', value: _hms(t.rideSeconds)),
            FieldRow(
              label: 'Fault',
              value: faultOk ? 'OK' : '${t.fault}',
              valueColor: faultOk ? Esk8Theme.green : Esk8Theme.danger,
            ),
            FieldRow(label: 'Link', value: 'BLE', valueColor: Esk8Theme.green),
          ],
        ),
        FieldSection(
          title: 'Board',
          rows: [
            FieldRow(label: 'Rider', value: (s?.rider.isNotEmpty == true) ? s!.rider : '—', valueSize: 22),
            FieldRow(label: 'Units', value: (s?.mph == true) ? 'MPH' : 'KM/H', valueSize: 22),
            FieldRow(label: 'Cells', value: '${s?.batterySeries ?? 0}', unit: 'S'),
            FieldRow(label: 'Theme', value: (s?.theme.isNotEmpty == true) ? s!.theme : '—', valueSize: 22),
            FieldRow(label: 'Bright', value: '${s?.brightness ?? 0}', unit: '%'),
          ],
        ),
      ],
    );
  }
}
