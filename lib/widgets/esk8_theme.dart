import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design tokens for the ESK8OS dashboard — a 1:1 port of the firmware's
/// CAM theme (`src/ui/Theme.cpp`) so the app reads exactly like the board: NZXT
/// CAM language, **sharp corners (no rounded borders)**, thin grey panels,
/// segmented battery, and semantic value colours (white default, green healthy,
/// yellow/orange/red as values climb).
class Esk8Theme {
  Esk8Theme._();

  // CAM palette (exact RGB from THEMES[] "CAM").
  static const Color accent = Color(0xFFB950D7); // {185,80,215}
  static const Color scaffold = Color(0xFF1A1A1A); // bg {26,26,26}
  static const Color panel = Color(0xFF1A1A1A); // cells share the bg; only borders separate
  static const Color panelOverlay = Color(0xDD1A1A1A);
  static const Color border = Color(0xFF444444); // {68,68,68}
  static const Color dim = Color(0xFF888888); // {136,136,136}
  static const Color label = Color(0xFFAAAAAA); // {170,170,170}

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textMuted = label;
  static const Color green = Color(0xFF00C864); // {0,200,100}
  static const Color yellow = Color(0xFFFFCD00); // {255,205,0}
  static const Color orange = Color(0xFFFF8000); // {255,128,0}
  static const Color danger = Color(0xFFFF3333); // red {255,51,51}

  /// Sharp corners — the board never rounds.
  static const double radius = 0.0;

  // ---- Semantic value colours (mirror ui.cpp color-zone helpers) ----

  /// Battery: ≥50 green · ≥30 yellow · ≥15 orange · else red.
  static Color batteryColor(int pct) {
    if (pct >= 50) return green;
    if (pct >= 30) return yellow;
    if (pct >= 15) return orange;
    return danger;
  }

  /// Watts: ≥3000 red · ≥2000 orange · ≥1000 yellow · else white.
  static Color wattsColor(num w) {
    if (w >= 3000) return danger;
    if (w >= 2000) return orange;
    if (w >= 1000) return yellow;
    return textPrimary;
  }

  /// Duty %: ≥95 red · ≥85 orange · ≥70 yellow · else white.
  static Color dutyColor(num d) {
    if (d >= 95) return danger;
    if (d >= 85) return orange;
    if (d >= 70) return yellow;
    return textPrimary;
  }

  /// Big BebasNeue numeral (speed heroes, stat values).
  static TextStyle number(double size, {Color color = textPrimary}) =>
      GoogleFonts.bebasNeue(
        fontSize: size,
        fontWeight: FontWeight.normal,
        color: color,
        height: 1.0,
        letterSpacing: 1.0,
      );

  /// Small all-caps section / tile label.
  static const TextStyle labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: label,
    letterSpacing: 1.5,
  );

  /// Standard bordered panel decoration (sharp corners).
  static BoxDecoration panelBox({bool overlay = false, Color? borderColor}) =>
      BoxDecoration(
        color: overlay ? panelOverlay : panel,
        border: Border.all(color: borderColor ?? border),
      );
}
