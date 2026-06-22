import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../pages/settings_page.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// SETTINGS (deck page) — mirrors the board's Settings page. Shows the current
/// board config read-only; the EDIT button opens the full editor (also reachable
/// from the gear in the controls overlay).
class SettingsSummaryView extends StatelessWidget {
  final Esk8Device dev;
  final BoardSettings? settings;
  final VoidCallback onEdited;

  const SettingsSummaryView({super.key, required this.dev, required this.settings, required this.onEdited});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (s == null) return const WaitingForTelemetry();

    return PageChrome(
      sections: [
        FieldSection(
          title: 'Display',
          rows: [
            FieldRow(label: 'Units', value: s.mph ? 'MPH' : 'KM/H', valueSize: 22),
            FieldRow(label: 'Theme', value: s.theme.isNotEmpty ? s.theme : '—', valueSize: 22),
            FieldRow(label: 'Bright', value: '${s.brightness}', unit: '%'),
            FieldRow(label: 'Rider', value: s.rider.isNotEmpty ? s.rider : '—', valueSize: 22),
          ],
        ),
        FieldSection(
          title: 'Battery / Range',
          rows: [
            FieldRow(label: 'Cells', value: '${s.batterySeries}', unit: 'S'),
            FieldRow(label: 'Pack', value: s.packAh.toStringAsFixed(1), unit: 'Ah'),
            FieldRow(label: 'Stop Cell', value: s.stopCellV.toStringAsFixed(2), unit: 'V'),
            FieldRow(label: 'Wh/mi', value: '${s.whPerMile}'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsPage(dev: dev)),
              );
              onEdited();
            },
            icon: const Icon(Icons.edit, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: Esk8Theme.accent,
              side: const BorderSide(color: Esk8Theme.accent),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            label: const Text('EDIT SETTINGS', style: TextStyle(letterSpacing: 1.5)),
          ),
        ),
      ],
    );
  }
}
