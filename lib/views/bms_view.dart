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

  const BmsView({super.key, required this.dev, required this.settings});

  @override
  State<BmsView> createState() => _BmsViewState();
}

class _BmsViewState extends State<BmsView> {
  // Cache the stream so StreamBuilder doesn't re-subscribe (and re-enable
  // notifications) on every rebuild.
  late final Stream<BmsData> _stream = widget.dev.bms();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BmsData>(
      stream: _stream,
      builder: (context, snap) {
        final b = snap.data;
        if (b == null) return _centered('Waiting for BMS…', Esk8Theme.dim);
        if (!b.link) {
          return _centered(
            'BMS LINK DOWN\ncheck the UART wiring, or enable demo',
            Esk8Theme.orange,
          );
        }
        return _content(b);
      },
    );
  }

  Widget _content(BmsData b) {
    final charging = b.current > 0.5;
    return PageChrome(
      sections: [
        FieldSection(
          title: 'Pack',
          rows: [
            FieldRow(
              label: 'Voltage',
              value: b.packVolts.toStringAsFixed(2),
              unit: 'V',
              valueSize: 30,
            ),
            FieldRow(
              label: 'Current',
              value: b.current.abs().toStringAsFixed(1),
              unit: 'A',
              valueColor: charging ? Esk8Theme.green : Esk8Theme.textPrimary,
              trailing: charging ? 'CHARGING' : 'DISCHARGE',
              trailingColor: charging ? Esk8Theme.green : Esk8Theme.dim,
            ),
            FieldRow(label: 'Charge', value: '${b.soc}', unit: '%'),
            FieldRow(
              label: 'Remaining',
              value: b.remainingAh.toStringAsFixed(2),
              unit: 'Ah',
            ),
            FieldRow(label: 'Cycles', value: '${b.cycles}', valueSize: 22),
          ],
        ),
        FieldSection(
          title: 'Cells   Δ ${b.deltaMv} mV',
          rows: [
            for (var i = 0; i < b.cellCount && i < b.cellsMv.length; i++)
              _cellRow(b, i),
          ],
        ),
        FieldSection(
          title: 'Status',
          rows: [
            FieldRow(
              label: 'Discharge MOS',
              value: b.dischargeMos ? 'ON' : 'OFF',
              valueColor: b.dischargeMos ? Esk8Theme.green : Esk8Theme.danger,
              valueSize: 20,
            ),
            FieldRow(
              label: 'Charge MOS',
              value: b.chargeMos ? 'ON' : 'OFF',
              valueColor: b.chargeMos ? Esk8Theme.green : Esk8Theme.dim,
              valueSize: 20,
            ),
            FieldRow(
              label: 'Temps',
              value: '${b.tempMin}–${b.tempMax}',
              unit: '°C',
              valueSize: 22,
            ),
            FieldRow(
              label: 'Protection',
              value: b.fault ? 'FAULT' : 'OK',
              valueColor: b.fault ? Esk8Theme.danger : Esk8Theme.green,
              valueSize: 20,
            ),
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
    final isMin = (i + 1) == b.minCell;
    final isMax = (i + 1) == b.maxCell;
    final bal = b.cellBalancing(i);
    final color = stale
        ? Esk8Theme.dim
        : isMin
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
