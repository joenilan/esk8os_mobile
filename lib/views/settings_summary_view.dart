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
  final Telemetry? telemetry;
  final VoidCallback onEdited;

  const SettingsSummaryView({
    super.key,
    required this.dev,
    required this.settings,
    this.telemetry,
    required this.onEdited,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (s == null) return const WaitingForTelemetry();

    return PageChrome(
      sections: [
        FieldSection(
          title: 'Display',
          rows: [
            FieldRow(
              label: 'Hardware',
              value: _hardwareLabel(s),
              valueSize: 18,
            ),
            FieldRow(label: 'On-board UI', value: _uiLabel(s), valueSize: 18),
            FieldRow(
              label: 'Units',
              value: s.mph ? 'MPH' : 'KM/H',
              valueSize: 22,
            ),
            FieldRow(
              label: 'Theme',
              value: s.theme.isNotEmpty ? s.theme : '—',
              valueSize: 22,
            ),
            FieldRow(label: 'Bright', value: '${s.brightness}', unit: '%'),
            FieldRow(
              label: 'RGB',
              value: s.statusRgb ? 'On' : 'Off',
              valueSize: 22,
            ),
            if (s.display == 'oled')
              FieldRow(
                label: 'OLED',
                value: s.oledInvert ? 'Light' : 'Dark',
                valueSize: 22,
              ),
            FieldRow(label: 'HUD', value: _title(s.hudFace), valueSize: 22),
            FieldRow(
              label: 'Battery View',
              value: s.batteryFocus == 'volts' ? 'Volts' : 'Percent',
              valueSize: 22,
            ),
            FieldRow(
              label: 'Rider',
              value: s.rider.isNotEmpty ? s.rider : '—',
              valueSize: 22,
            ),
          ],
        ),
        FieldSection(
          title: 'Battery / Range',
          rows: [
            FieldRow(label: 'Cells', value: '${s.batterySeries}', unit: 'S'),
            FieldRow(
              label: 'Pack',
              value: s.packAh.toStringAsFixed(1),
              unit: 'Ah',
            ),
            FieldRow(
              label: 'Home Cell',
              value: s.homeCellV.toStringAsFixed(2),
              unit: 'V',
            ),
            FieldRow(
              label: 'Limp Cell',
              value: s.stopCellV.toStringAsFixed(2),
              unit: 'V',
            ),
            FieldRow(label: 'Wh/mi', value: s.whPerMile.toStringAsFixed(1)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(dev: dev, telemetry: telemetry),
                ),
              );
              onEdited();
            },
            icon: const Icon(Icons.edit, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: Esk8Theme.accent,
              side: BorderSide(color: Esk8Theme.accent),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const RoundedRectangleBorder(), // sharp — board look
            ),
            label: const Text(
              'EDIT SETTINGS',
              style: TextStyle(letterSpacing: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  static String _title(String value) {
    if (value.isEmpty) return '—';
    return value[0].toUpperCase() + value.substring(1);
  }

  static String _hardwareLabel(BoardSettings s) {
    if (s.hardware == 'tdisplay-s3') return 'T-Display S3';
    if (s.hardware == 'esp32s3-oled') return 'ESP32-S3 OLED';
    if (s.hardware == 'esp32s3-headless') return 'ESP32-S3 Headless';
    return s.hardware.isNotEmpty ? s.hardware : 'Unknown';
  }

  static String _uiLabel(BoardSettings s) {
    final display = switch (s.display) {
      'tft' => 'TFT',
      'oled' => 'OLED',
      'none' => 'None',
      _ => s.display,
    };
    final ui = switch (s.ui) {
      'full' => 'Full',
      'mini' => 'Mini',
      'headless' => 'Phone only',
      _ => s.ui,
    };
    return '$display · $ui';
  }
}
