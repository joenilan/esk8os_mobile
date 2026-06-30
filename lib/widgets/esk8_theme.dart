import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One board colour palette — a 1:1 mirror of a `THEMES[]` entry in the firmware
/// (`src/ui/Theme.cpp`). RGB values are copied verbatim so the app reads exactly
/// like the board for the selected theme.
class _Palette {
  final Color bg, border, dim, label, white, green, red, accent, yellow, orange;
  const _Palette({
    required this.bg,
    required this.border,
    required this.dim,
    required this.label,
    required this.white,
    required this.green,
    required this.red,
    required this.accent,
    required this.yellow,
    required this.orange,
  });
}

/// Central design tokens for the ESK8OS dashboard. The live colours below are
/// **mutable** and get swapped by [applyTheme] so the app mirrors whichever
/// palette the board is running (NZXT-CAM language, sharp corners, thin grey
/// panels, semantic value colours). Defaults are CAM until settings load.
class Esk8Theme {
  Esk8Theme._();

  /// The 8 board palettes (exact RGB from `THEMES[]` in src/ui/Theme.cpp).
  static const Map<String, _Palette> _palettes = {
    'CAM': _Palette(
      bg: Color(0xFF1A1A1A), border: Color(0xFF444444), dim: Color(0xFF888888),
      label: Color(0xFFAAAAAA), white: Color(0xFFFFFFFF), green: Color(0xFF00C864),
      red: Color(0xFFFF3333), accent: Color(0xFFB950D7), yellow: Color(0xFFFFCD00),
      orange: Color(0xFFFF8000),
    ),
    'EMBER': _Palette(
      bg: Color(0xFF14100E), border: Color(0xFF483A30), dim: Color(0xFF967A64),
      label: Color(0xFFC0A28A), white: Color(0xFFFFF6EC), green: Color(0xFF78C85A),
      red: Color(0xFFFF3C30), accent: Color(0xFFFF8C28), yellow: Color(0xFFFFCD00),
      orange: Color(0xFFFF7800),
    ),
    'ICE': _Palette(
      bg: Color(0xFF12161A), border: Color(0xFF36424A), dim: Color(0xFF788C96),
      label: Color(0xFFA2B6C0), white: Color(0xFFF0F8FF), green: Color(0xFF00D296),
      red: Color(0xFFFF4646), accent: Color(0xFF00C8E6), yellow: Color(0xFFFFD25A),
      orange: Color(0xFFFF8C28),
    ),
    'LIGHT': _Palette(
      bg: Color(0xFFECECF0), border: Color(0xFFB0B0B6), dim: Color(0xFF78787E),
      label: Color(0xFF4A4A50), white: Color(0xFF18181C), green: Color(0xFF009648),
      red: Color(0xFFD22020), accent: Color(0xFF962CBE), yellow: Color(0xFFBE8C00),
      orange: Color(0xFFD66000),
    ),
    'CYBER': _Palette(
      bg: Color(0xFF0A0812), border: Color(0xFF3E1E54), dim: Color(0xFF7C5CA2),
      label: Color(0xFFBA8EE0), white: Color(0xFFE4E6FF), green: Color(0xFF00FFB4),
      red: Color(0xFFFF2A78), accent: Color(0xFFFF2CCC), yellow: Color(0xFFFFEE3C),
      orange: Color(0xFFFF78C8),
    ),
    'SYNTHWAVE': _Palette(
      bg: Color(0xFF160C22), border: Color(0xFF46285A), dim: Color(0xFF966EAA),
      label: Color(0xFFD296C8), white: Color(0xFFFAF0FF), green: Color(0xFF3CF0C8),
      red: Color(0xFFFF506E), accent: Color(0xFFFF5AAA), yellow: Color(0xFFFFD264),
      orange: Color(0xFFFF965A),
    ),
    'MONO': _Palette(
      bg: Color(0xFF101010), border: Color(0xFF404040), dim: Color(0xFF828282),
      label: Color(0xFFB4B4B4), white: Color(0xFFF5F5F5), green: Color(0xFFC8C8C8),
      red: Color(0xFFEBEBEB), accent: Color(0xFFFFFFFF), yellow: Color(0xFFD2D2D2),
      orange: Color(0xFFE1E1E1),
    ),
    'FOREST': _Palette(
      bg: Color(0xFF0E1610), border: Color(0xFF304634), dim: Color(0xFF6E8C74),
      label: Color(0xFFA0BEA4), white: Color(0xFFECF6EE), green: Color(0xFF5ADC78),
      red: Color(0xFFF05A46), accent: Color(0xFF78D26E), yellow: Color(0xFFDCC85A),
      orange: Color(0xFFEB9646),
    ),
  };

  /// Name of the palette currently applied (so widgets can react, e.g. light mode).
  static String themeName = 'CAM';

  /// Bumped on every [applyTheme] so the app root can rebuild the MaterialApp
  /// (and any listener) when the board's selected palette changes.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // ---- Live colours (mutable; swapped by applyTheme to mirror the board) ----
  static Color accent = const Color(0xFFB950D7);
  static Color scaffold = const Color(0xFF1A1A1A); // == palette bg
  static Color panel = const Color(0xFF1A1A1A); // cells share the bg; only borders separate
  static Color panelOverlay = const Color(0xDD1A1A1A);
  static Color border = const Color(0xFF444444);
  static Color dim = const Color(0xFF888888);
  static Color label = const Color(0xFFAAAAAA);
  static Color textPrimary = const Color(0xFFFFFFFF);
  static Color textMuted = const Color(0xFFAAAAAA);
  static Color green = const Color(0xFF00C864);
  static Color yellow = const Color(0xFFFFCD00);
  static Color orange = const Color(0xFFFF8000);
  static Color danger = const Color(0xFFFF3333);

  /// True when the active palette is a light-background theme (LIGHT) — lets
  /// status bars / overlays flip to dark-on-light where needed.
  static bool get isLight => scaffold.computeLuminance() > 0.5;

  /// Apply a board theme by name (case-insensitive). Falls back to CAM. Call
  /// this when board settings load/change, then rebuild the widget tree.
  static void applyTheme(String name) {
    final key = name.toUpperCase();
    final p = _palettes[key] ?? _palettes['CAM']!;
    themeName = _palettes.containsKey(key) ? key : 'CAM';
    accent = p.accent;
    scaffold = p.bg;
    panel = p.bg;
    panelOverlay = p.bg.withValues(alpha: 0.87);
    border = p.border;
    dim = p.dim;
    label = p.label;
    textPrimary = p.white;
    textMuted = p.label;
    green = p.green;
    yellow = p.yellow;
    orange = p.orange;
    danger = p.red;
    revision.value++;
  }

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
  static TextStyle number(double size, {Color? color}) => GoogleFonts.bebasNeue(
    fontSize: size,
    fontWeight: FontWeight.normal,
    color: color ?? textPrimary,
    height: 1.0,
    letterSpacing: 1.0,
  );

  /// Small all-caps section / tile label.
  static TextStyle get labelStyle => TextStyle(
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
