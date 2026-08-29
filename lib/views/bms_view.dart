import 'package:flutter/material.dart';

import '../ble/esk8os_ble.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// BMS — the Daly pack's per-cell detail, the one thing the VESC can't show.
/// A single lagging cell is invisible from the pack terminals and is how a DIY
/// pack strands you or catches fire; here it's the short red bar. Only shown for
/// boards that expose the BMS characteristic (BMS builds) — see [Esk8Device.hasBms].
class BmsView extends StatefulWidget {
  final Esk8Device dev;
  final BoardSettings? settings;
  final Stream<BmsData>? bmsStream;

  const BmsView({
    super.key,
    required this.dev,
    required this.settings,
    this.bmsStream,
  });

  @override
  State<BmsView> createState() => _BmsViewState();
}

class _BmsViewState extends State<BmsView> {
  // Cache the stream so StreamBuilder doesn't re-subscribe (and re-enable
  // notifications) on every rebuild.
  late final Stream<BmsData> _stream = widget.bmsStream ?? widget.dev.bms();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BmsData>(
      stream: _stream,
      builder: (context, snap) {
        final b = snap.data;
        if (b == null) return _centered('Waiting for BMS…', Esk8Theme.dim);
        if (!b.link) {
          return _centered(
            'BMS LINK DOWN\nclose the Daly app · check UART K power/range',
            Esk8Theme.orange,
          );
        }
        return _content(b);
      },
    );
  }

  Widget _content(BmsData b) {
    final currentState = !b.packFresh
        ? null
        : b.current > 0.5
        ? 'CHARGING'
        : b.current < -0.5
        ? 'DISCHARGE'
        : 'IDLE';
    final currentColor = currentState == 'CHARGING'
        ? Esk8Theme.green
        : currentState == 'IDLE'
        ? Esk8Theme.dim
        : Esk8Theme.textPrimary;
    final alarmColor = _alarmColor(b.effectiveAlarmLevel);
    final spreadColor = b.effectiveAlarmLevel == 2 || b.deltaMv > 100
        ? Esk8Theme.danger
        : b.effectiveAlarmLevel == 1 || b.deltaMv >= 50
        ? Esk8Theme.yellow
        : Esk8Theme.textPrimary;
    final cellRows = b.cellsMv.length;
    return PageChrome(
      sections: [
        FieldSection(
          title: 'Pack',
          rows: [
            FieldRow(
              label: 'Voltage',
              value: b.packFresh ? b.packVolts.toStringAsFixed(2) : '--',
              unit: 'V',
              valueColor: b.packFresh ? Esk8Theme.textPrimary : Esk8Theme.dim,
              valueSize: 30,
            ),
            FieldRow(
              label: 'Current',
              value: b.packFresh ? b.current.abs().toStringAsFixed(1) : '--',
              unit: 'A',
              valueColor: currentColor,
              trailing: currentState,
              trailingColor: currentColor,
            ),
            FieldRow(
              label: 'Charge',
              value: b.packFresh ? '${b.soc}' : '--',
              unit: '%',
              valueColor: b.packFresh ? null : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Remaining',
              value: b.mosFresh ? b.remainingAh.toStringAsFixed(2) : '--',
              unit: 'Ah',
              valueColor: b.mosFresh ? null : Esk8Theme.dim,
            ),
            FieldRow(
              label: 'Cycles',
              value: b.statusFresh ? '${b.cycles}' : '--',
              valueColor: b.statusFresh ? null : Esk8Theme.dim,
              valueSize: 22,
            ),
          ],
        ),
        FieldSection(
          title: 'Cells   Δ ${b.minMaxVoltageFresh ? '${b.deltaMv} mV' : '--'}',
          rows: [for (var i = 0; i < cellRows; i++) _cellRow(b, i)],
        ),
        FieldSection(
          title: 'Status',
          rows: [
            FieldRow(
              label: 'Discharge MOS',
              value: b.mosFresh ? (b.dischargeMos ? 'ON' : 'OFF') : '--',
              valueColor: !b.mosFresh
                  ? Esk8Theme.dim
                  : b.dischargeMos
                  ? Esk8Theme.green
                  : Esk8Theme.danger,
              valueSize: 20,
            ),
            FieldRow(
              label: 'Charge MOS',
              value: b.mosFresh ? (b.chargeMos ? 'ON' : 'OFF') : '--',
              valueColor: !b.mosFresh
                  ? Esk8Theme.dim
                  : b.chargeMos
                  ? Esk8Theme.green
                  : Esk8Theme.dim,
              valueSize: 20,
            ),
            FieldRow(
              label: 'Temps',
              value: b.temperaturesFresh ? '${b.tempMin}–${b.tempMax}' : '--',
              unit: '°C',
              valueColor: b.temperaturesFresh ? null : Esk8Theme.dim,
              valueSize: 22,
            ),
            FieldRow(
              label: 'Protection',
              value: b.alarmLabel,
              valueColor: alarmColor,
              valueSize: 20,
            ),
            FieldRow(
              label: 'Cell spread',
              value: b.minMaxVoltageFresh ? '${b.deltaMv}' : '--',
              unit: 'mV',
              valueColor: b.minMaxVoltageFresh ? spreadColor : Esk8Theme.dim,
              valueSize: 22,
            ),
          ],
        ),
        FieldSection(
          title: 'Diagnostics',
          rows: [
            FieldRow(
              label: 'Fresh groups',
              value: _freshnessSummary(b),
              trailing: b.freshnessMask == null
                  ? 'LEGACY'
                  : '0x${b.freshnessMask!.toRadixString(16).padLeft(3, '0')}',
              trailingColor: b.freshnessMask == null
                  ? Esk8Theme.dim
                  : b.freshnessMask == BmsData.allFreshMask
                  ? Esk8Theme.green
                  : Esk8Theme.orange,
              valueColor:
                  b.freshnessMask == null ||
                      b.freshnessMask == BmsData.allFreshMask
                  ? Esk8Theme.green
                  : Esk8Theme.orange,
              valueSize: 20,
            ),
            FieldRow(
              label: 'Stale groups',
              value: _staleGroups(b),
              valueColor: _staleGroups(b) == 'NONE'
                  ? Esk8Theme.green
                  : Esk8Theme.orange,
              valueSize: 18,
            ),
            FieldRow(
              label: 'Raw fault bytes',
              value: b.rawFaultBytes ?? 'NOT PROVIDED',
              valueColor: b.rawFaultBytes == null ? Esk8Theme.dim : alarmColor,
              valueSize: 18,
            ),
            if (b.lastRawFaultBytes != null)
              FieldRow(
                label: 'Last protection',
                value: b.lastFaultLabel ?? 'UNCLASSIFIED BMS ALERT',
                trailing: b.lastFaultAgeSec == null
                    ? null
                    : '${b.lastFaultAgeSec}s AGO',
                valueColor: Esk8Theme.orange,
                trailingColor: Esk8Theme.dim,
                valueSize: 18,
              ),
            if (b.lastRawFaultBytes != null)
              FieldRow(
                label: 'Last fault bytes',
                value: b.lastRawFaultBytes!,
                valueColor: Esk8Theme.orange,
                valueSize: 18,
              ),
            // The pack's own discharge limits (read-only Modbus evidence).
            // Context for any ride peak: P1 is the limit that opened the
            // discharge MOS on the 2026-07-30 validation ride.
            if (b.ocSettingsValid) ...[
              FieldRow(
                label: 'O/C warn limit',
                value: b.ocWarnA!.toStringAsFixed(1),
                unit: 'A',
                trailing: b.ocAgeSec == null ? null : '${b.ocAgeSec}s AGO',
                trailingColor: Esk8Theme.dim,
                valueSize: 20,
              ),
              FieldRow(
                label: 'O/C protect 1',
                value: b.ocProtect1A!.toStringAsFixed(1),
                unit: 'A',
                trailing: '${b.ocProtect1DelayMs} ms',
                valueColor: Esk8Theme.orange,
                trailingColor: Esk8Theme.dim,
                valueSize: 20,
              ),
              FieldRow(
                label: 'O/C protect 2',
                value: b.ocProtect2A!.toStringAsFixed(1),
                unit: 'A',
                trailing: '${b.ocProtect2DelayMs} ms',
                trailingColor: Esk8Theme.dim,
                valueSize: 20,
              ),
            ],
          ],
        ),
      ],
    );
  }

  // One cell: number, a level bar (mapped over 3.0–4.2 V so the bar reads as an
  // absolute charge level), and the mV. The weak (min) cell is red, the top cell
  // green, a balancing cell yellow, a stale cell greyed and shown as "— —".
  Widget _cellRow(BmsData b, int i) {
    final mv = b.cellsMv[i];
    final stale = b.cellStale(i);
    final isWeak = b.minMaxVoltageFresh && b.cellWeak(i);
    final isMax = b.minMaxVoltageFresh && (i + 1) == b.maxCell;
    final bal = b.cellBalancing(i);
    final color = stale
        ? Esk8Theme.dim
        : isWeak
        ? Esk8Theme.danger
        : bal
        ? Esk8Theme.yellow
        : isMax
        ? Esk8Theme.green
        : Esk8Theme.textPrimary;
    final frac = ((mv - 3000) / 1200.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${i + 1}',
              style: TextStyle(fontSize: 12, color: Esk8Theme.dim),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 14,
                color: Esk8Theme.border.withValues(alpha: 0.45),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac,
                  child: Container(
                    color: color.withValues(alpha: stale ? 0.3 : 0.85),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              stale ? '— —' : '$mv',
              textAlign: TextAlign.right,
              style: Esk8Theme.number(15, color: color),
            ),
          ),
          SizedBox(
            width: 16,
            child: bal
                ? Icon(Icons.bolt, size: 13, color: Esk8Theme.yellow)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  static Color _alarmColor(int level) => switch (level) {
    0 => Esk8Theme.green,
    1 => Esk8Theme.yellow,
    2 => Esk8Theme.danger,
    _ => Esk8Theme.orange,
  };

  static String _freshnessSummary(BmsData b) {
    final mask = b.freshnessMask;
    if (mask == null) return b.link ? 'LINK FRESH' : 'LINK DOWN';
    var count = 0;
    for (var bit = 0; bit < 9; bit++) {
      if ((mask & (1 << bit)) != 0) count++;
    }
    return '$count / 9';
  }

  static String _staleGroups(BmsData b) {
    final mask = b.freshnessMask;
    if (mask == null) return 'NONE';
    const names = [
      'PACK',
      'MIN/MAX V',
      'MIN/MAX T',
      'MOS',
      'STATUS',
      'CELLS',
      'TEMPS',
      'BALANCE',
      'FAULTS',
    ];
    final stale = <String>[
      for (var bit = 0; bit < names.length; bit++)
        if ((mask & (1 << bit)) == 0) names[bit],
    ];
    return stale.isEmpty ? 'NONE' : stale.join(' · ');
  }

  Widget _centered(String text, Color color) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          color: color,
          letterSpacing: 0.6,
          height: 1.5,
        ),
      ),
    ),
  );
}
