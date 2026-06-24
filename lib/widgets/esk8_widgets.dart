import 'package:flutter/material.dart';
import 'esk8_theme.dart';

/// Shared dashboard widget kit — ports the firmware's NZXT-CAM layout language
/// (`src/ui/ui.cpp`): sharp-cornered cells, segmented battery, "fieldset"
/// sections (centered title + rule + label/value rows), semantic value colours.
/// Every numeric readout is overflow-proof (value+unit live in a [FittedBox]).

/// A bordered stat cell: small label above a big BebasNeue value + unit. Used in
/// the HUD 2×2 grid (mirrors `drawCell` on the board). Sharp corners.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final CrossAxisAlignment align;
  final double valueSize;
  final bool overlay;
  final Color? valueColor;
  final EdgeInsets padding;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.align = CrossAxisAlignment.center,
    this.valueSize = 44,
    this.overlay = false,
    this.valueColor,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final fitAlign = switch (align) {
      CrossAxisAlignment.start => Alignment.centerLeft,
      CrossAxisAlignment.end => Alignment.centerRight,
      _ => Alignment.center,
    };
    return Container(
      padding: padding,
      decoration: Esk8Theme.panelBox(overlay: overlay),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align,
        children: [
          // Value on top, label beneath — matches the board's cells.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: fitAlign,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: Esk8Theme.number(valueSize, color: valueColor ?? Esk8Theme.textPrimary)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(unit, style: const TextStyle(fontSize: 14, color: Esk8Theme.dim)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: Esk8Theme.labelStyle),
        ],
      ),
    );
  }
}

/// The big speed readout (HUD). The number fills the width (scaling via
/// [FittedBox]); the unit sits directly underneath — mirrors the board.
class SpeedHero extends StatelessWidget {
  final String value;
  final String unit;
  final double maxSize;

  const SpeedHero({super.key, required this.value, required this.unit, this.maxSize = 156});

  @override
  Widget build(BuildContext context) {
    // scaleDown keeps the hero a fixed, glanceable size (only shrinking for very
    // wide values); the tight line height pulls MPH right up under the digits.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: Esk8Theme.number(maxSize, color: Esk8Theme.textPrimary).copyWith(height: 0.8)),
        ),
        Text(unit,
            style: const TextStyle(
                fontSize: 26, color: Esk8Theme.dim, fontWeight: FontWeight.w600, letterSpacing: 3)),
      ],
    );
  }
}

/// Segmented battery gauge — a 1:1 port of `drawBatteryCellsRow`: [cells] bordered
/// segments, filled (green→yellow→orange→red by level) up to a continuous level
/// with the boundary segment partially filled by width.
class SegmentedBattery extends StatelessWidget {
  final int percent;
  final int cells;
  final double height;

  const SegmentedBattery({super.key, required this.percent, this.cells = 12, this.height = 26});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _BatteryPainter(percent.clamp(0, 100), cells), size: Size.infinite),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final int percent;
  final int cells;
  _BatteryPainter(this.percent, this.cells);

  @override
  void paint(Canvas canvas, Size size) {
    final gap = cells > 12 ? 2.0 : 4.0;
    final cellW = (size.width - (cells - 1) * gap) / cells;
    final fillColor = Esk8Theme.batteryColor(percent);
    final level = percent * cells / 100.0;
    final full = level.floor();
    final frac = level - full;

    final borderP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Esk8Theme.border;
    final fillP = Paint()..color = fillColor;

    for (var i = 0; i < cells; i++) {
      final x = i * (cellW + gap);
      final rect = Rect.fromLTWH(x, 0, cellW, size.height);
      canvas.drawRect(rect.deflate(0.75), borderP);
      if (i < full) {
        canvas.drawRect(rect.deflate(2), fillP);
      } else if (i == full && frac > 0) {
        final fw = (cellW - 4) * frac;
        if (fw > 0) canvas.drawRect(Rect.fromLTWH(x + 2, 2, fw, size.height - 4), fillP);
      }
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) => old.percent != percent || old.cells != cells;
}

/// A "fieldset" section: bordered box with a centred title + underline rule at
/// the top, then label/value rows. Mirrors `drawCard` on the board.
class FieldSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const FieldSection({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: Esk8Theme.panelBox(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text(title.toUpperCase(), style: Esk8Theme.labelStyle)),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1, color: Esk8Theme.border),
          const SizedBox(height: 4),
          ...rows,
        ],
      ),
    );
  }
}

/// One row inside a [FieldSection]: muted label on the left, BebasNeue value +
/// unit on the right, optional [trailing] (e.g. a green "(90%)").
class FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color valueColor;
  final String? trailing;
  final Color trailingColor;
  final double valueSize;

  const FieldRow({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.valueColor = Esk8Theme.textPrimary,
    this.trailing,
    this.trailingColor = Esk8Theme.green,
    this.valueSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 14, color: Esk8Theme.label, letterSpacing: 0.5)),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: Esk8Theme.number(valueSize, color: valueColor)),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    Text(unit, style: const TextStyle(fontSize: 13, color: Esk8Theme.dim)),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Text(trailing!, style: Esk8Theme.number(valueSize - 4, color: trailingColor)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grey, letter-spaced section heading (e.g. "POWER") — used outside fieldsets.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 16, color: Esk8Theme.label, letterSpacing: 3, fontWeight: FontWeight.bold),
      );
}

/// Top status strip — app wordmark · rider/connection · clock. Mirrors the
/// board's header row.
class TopStatusBar extends StatelessWidget {
  final String left;
  final String center;
  final String right;
  const TopStatusBar({super.key, this.left = 'ESK8OS', this.center = '', this.right = ''});

  @override
  Widget build(BuildContext context) {
    const s = TextStyle(fontSize: 13, color: Esk8Theme.dim, letterSpacing: 1.5, fontWeight: FontWeight.w600);
    return Row(
      children: [
        Text(left, style: s),
        Expanded(child: Center(child: Text(center, style: s))),
        Text(right, style: s),
      ],
    );
  }
}

/// Bottom status line — battery% · trip · odometer. Mirrors the board's footer.
class BottomStatus extends StatelessWidget {
  final int percent;
  final String trip;
  final String odo;
  const BottomStatus({super.key, required this.percent, required this.trip, required this.odo});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$percent%', style: TextStyle(fontSize: 13, color: Esk8Theme.batteryColor(percent), fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Text('T:$trip', style: const TextStyle(fontSize: 13, color: Esk8Theme.dim)),
        const SizedBox(width: 10),
        Text('O:$odo', style: const TextStyle(fontSize: 13, color: Esk8Theme.dim)),
      ],
    );
  }
}

/// A generic bordered panel (sharp corners).
class GlancePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool overlay;
  const GlancePanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.overlay = false});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: Esk8Theme.panelBox(overlay: overlay),
        child: child,
      );
}

/// Standard "no telemetry yet" placeholder.
class WaitingForTelemetry extends StatelessWidget {
  const WaitingForTelemetry({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Waiting for telemetry…', style: TextStyle(color: Esk8Theme.dim)),
      );
}

/// Page scaffold for the stat pages: vertically centres content when it fits,
/// scrolls when it doesn't. Reclaims the top cutout band and reserves bottom
/// room for the page dots.
class GlanceScaffold extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final double spacing;
  const GlanceScaffold({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 44),
    this.spacing = 14,
  });

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        children[i],
      ],
    ];
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - padding.vertical),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: spaced,
            ),
          ),
        ),
      ),
    );
  }
}

/// Body layout for the detail pages: sections centred when short, scrollable
/// when tall. The top/bottom identifying panels and page dots are provided once
/// by the dashboard around the PageView, so pages render content only.
class PageChrome extends StatelessWidget {
  final List<Widget> sections;
  final double spacing;
  const PageChrome({super.key, required this.sections, this.spacing = 12});

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        sections[i],
      ],
    ];
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight - 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced,
          ),
        ),
      ),
    );
  }
}

/// Center-zero throttle bar: fills right (green) on accel, left (red) on brake.
/// [throttle] is -1..1 (the VESC's decoded remote input).
class ThrottleBar extends StatelessWidget {
  final double throttle;
  final double height;
  const ThrottleBar({super.key, required this.throttle, this.height = 30});

  @override
  Widget build(BuildContext context) {
    final accel = throttle.clamp(0.0, 1.0).toDouble();
    final brake = (-throttle).clamp(0.0, 1.0).toDouble();
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Esk8Theme.scaffold,
        border: Border.all(color: Esk8Theme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                  widthFactor: brake, child: Container(color: Esk8Theme.danger)),
            ),
          ),
          Container(width: 2, color: Esk8Theme.label),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                  widthFactor: accel, child: Container(color: Esk8Theme.green)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of equal-width tiles with consistent gaps. Tiles share width via
/// [Expanded]; top-aligned (never stretch — that forces infinite height in the
/// unbounded page columns).
class StatRow extends StatelessWidget {
  final List<Widget> tiles;
  final double gap;
  const StatRow(this.tiles, {super.key, this.gap = 12});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: tiles[i]),
          ],
        ],
      );
}
