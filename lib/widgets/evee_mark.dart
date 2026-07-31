import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'esk8_theme.dart';

/// The EVEE Bolt-E mark, drawn as a vector so it's crisp at any size and takes
/// the theme accent. Geometry matches the launcher icon (design/evee-identity.html
/// in the firmware repo): an "E" whose middle arm is a lightning bolt, raked
/// forward for motion.
class BoltEMark extends StatelessWidget {
  final double size;
  final Color? color;
  const BoltEMark({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _BoltEPainter(color ?? Esk8Theme.accent)),
  );
}

class _BoltEPainter extends CustomPainter {
  final Color color;
  _BoltEPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // The mark lives in a 120-unit space; its leaned bbox centres near (59,60)
    // and stands 64 units tall. Fit it into the paint box with a little padding.
    const pad = 0.06;
    final k = size.height * (1 - 2 * pad) / 64.0;
    final lean = Matrix4.identity()
      ..setEntry(0, 3, 9.0) // translate x +9 (recentre the shear)
      ..setEntry(
        0,
        1,
        -math.tan(9 * math.pi / 180),
      ); // skewX(-9°): forward rake

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    canvas.translate(-59.0, -60.0);
    canvas.transform(lean.storage);

    final p = Paint()
      ..color = color
      ..isAntiAlias = true;
    void bar(double x, double y, double w, double h) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(2),
      ),
      p,
    );
    bar(40, 28, 14, 64); // spine
    bar(40, 28, 39, 14); // top arm
    bar(40, 78, 39, 14); // bottom arm
    canvas.drawPath(
      Path()
        ..moveTo(54, 52)
        ..lineTo(82, 52)
        ..lineTo(66, 62)
        ..lineTo(78, 62)
        ..lineTo(52, 74)
        ..lineTo(64, 63)
        ..lineTo(54, 63)
        ..close(),
      p,
    ); // bolt middle arm
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BoltEPainter old) => old.color != color;
}

/// Horizontal EVEE lockup: the mark + the wordmark in Bebas Neue. Used in the
/// app header where space is tight.
class EveeWordmark extends StatelessWidget {
  final double markSize;
  final double fontSize;
  final Color? textColor;
  const EveeWordmark({
    super.key,
    this.markSize = 18,
    this.fontSize = 22,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      BoltEMark(size: markSize, color: Esk8Theme.accent),
      SizedBox(width: markSize * 0.4),
      Text(
        'EVEE',
        style: GoogleFonts.bebasNeue(
          fontSize: fontSize,
          height: 1.0,
          letterSpacing: 2.5,
          color: textColor ?? Esk8Theme.textPrimary,
        ),
      ),
    ],
  );
}

/// The edition wordmark for a firmware vehicle type. The edition is a claim
/// ABOUT THE VEHICLE, so it only means something once a board has told us what
/// it is — callers pass null (and the lockup omits the line) until then. Only
/// skate is established (ESK8OS); other editions land as each vehicle ships.
String? editionFor(int vehicleType) {
  switch (vehicleType) {
    case 0:
      return 'ESK8OS'; // skate
    default:
      return null; // e-bike / scooter / moped / car / euc / onewheel — TBD
  }
}

/// The full vertical lockup for splash / front-door use: the wordmark, and —
/// only when [edition] is known — the "powered by" line under it. Before we've
/// connected to a vehicle we don't know the edition, so [edition] is null and
/// the line is omitted; it's a reveal, not a default.
class EveeLockup extends StatelessWidget {
  final double scale;
  final String? edition;
  const EveeLockup({super.key, this.scale = 1.0, this.edition});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      EveeWordmark(markSize: 44 * scale, fontSize: 56 * scale),
      if (edition != null && edition!.isNotEmpty) ...[
        SizedBox(height: 10 * scale),
        Text(
          'POWERED BY ${edition!}',
          style: TextStyle(
            color: Esk8Theme.dim,
            fontSize: 11 * scale,
            letterSpacing: 4 * scale,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}
