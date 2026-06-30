import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/esk8_theme.dart';

/// Renders a trip summary card to a PNG (off-screen) and shares it.
class TripShare {
  static Future<void> shareSummary(BuildContext context, Map<String, dynamic> trip, bool isMph) async {
    final key = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -3000, // off-screen but still painted
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(key: key, child: _TripCard(trip: trip, isMph: isMph)),
        ),
      ),
    );
    final overlay = Overlay.of(context);
    overlay.insert(entry);
    try {
      // Let it lay out + paint before capturing.
      await Future.delayed(const Duration(milliseconds: 80));
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/esk8_ride_card.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'My ESK8OS ride'));
    } finally {
      entry.remove();
    }
  }
}

class _TripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final bool isMph;
  const _TripCard({required this.trip, required this.isMph});

  @override
  Widget build(BuildContext context) {
    final distUnit = isMph ? 'mi' : 'km';
    final spdUnit = isMph ? 'mph' : 'km/h';
    final climbUnit = isMph ? 'ft' : 'm';
    final start = DateTime.fromMillisecondsSinceEpoch(trip['startTime'] as int);
    final dist = (trip['distance'] as num) / (isMph ? 1609.34 : 1000);
    final maxS = (trip['maxSpeed'] as num) / (isMph ? 1.60934 : 1);
    final climb = (trip['elevGainM'] as num? ?? 0) * (isMph ? 3.28084 : 1);
    final endMs = trip['endTime'] as int?;
    final dur = endMs != null ? Duration(milliseconds: endMs - (trip['startTime'] as int)) : Duration.zero;
    final avg = dur.inSeconds > 0 ? dist / (dur.inSeconds / 3600.0) : 0.0;
    final durStr = dur.inHours > 0
        ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m'
        : '${dur.inMinutes}m ${dur.inSeconds.remainder(60)}s';

    Widget stat(String label, String value, String unit) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: Esk8Theme.number(40)),
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(fontSize: 14, color: Esk8Theme.dim)),
              ],
            ),
            Text(label.toUpperCase(), style: Esk8Theme.labelStyle),
          ],
        );

    return Container(
      width: 420,
      padding: const EdgeInsets.all(24),
      color: Esk8Theme.scaffold,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ESK8OS', style: TextStyle(color: Esk8Theme.accent, fontWeight: FontWeight.bold, letterSpacing: 3, fontSize: 18)),
              Text(DateFormat('MMM d, yyyy · h:mm a').format(start), style: TextStyle(color: Esk8Theme.dim, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Esk8Theme.border),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            stat('Distance', dist.toStringAsFixed(2), distUnit),
            stat('Time', durStr, ''),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            stat('Max', maxS.toStringAsFixed(1), spdUnit),
            stat('Avg', avg.toStringAsFixed(1), spdUnit),
            stat('Climb', climb.toStringAsFixed(0), climbUnit),
          ]),
        ],
      ),
    );
  }
}
