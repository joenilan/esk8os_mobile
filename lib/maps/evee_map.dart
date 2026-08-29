import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Single source of truth for EVEE's raster basemap.
///
/// CARTO's free basemaps began enforcing API keys — tiles return an
/// "API KEY REQUIRED" error image with HTTP 200 (verified 2026-08-29), which
/// is why [basemap] now serves:
///  * light — OpenStreetMap standard raster tiles (no key; fine for
///    personal-use volume, revisit before mass distribution),
///  * dark — Esri World Dark Gray Canvas (no key, already dark, so the old
///    CARTO brightness bump is gone).
///
/// Attribution is rendered on-map by [basemap] itself so it can never be
/// dropped from a new surface again. The roadmap's durable provider move —
/// self-hosted tiles on the rider's own infra, or a keyed CARTO account, or
/// vector MapLibre — stays a one-file change behind this seam.
class EveeMap {
  EveeMap._();

  static const String _osmUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// ArcGIS REST serves /tile/{level}/{row}/{col} — note the {y}/{x} order.
  static const String _esriDarkUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/'
      'World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';

  static const String _attributionOsm =
      '© OpenStreetMap contributors';
  static const String _attributionEsri =
      '© OpenStreetMap contributors · Tiles © Esri';

  static const String userAgentPackageName = 'com.joenilan.esk8os_mobile';

  /// The basemap layer stack: tiles + attribution.
  ///
  /// Attribution is mode-aware (crediting the tiles actually shown) and
  /// rendered with a plain widget — flutter_map's SimpleAttributionWidget
  /// hardcodes a 'flutter_map | © ' prefix that garbled the line on device.
  static Widget basemap({required bool light}) {
    final TileLayer layer = TileLayer(
      urlTemplate: light ? _osmUrl : _esriDarkUrl,
      userAgentPackageName: userAgentPackageName,
      maxNativeZoom: light ? 19 : 16,
    );
    return Stack(
      children: [
        Positioned.fill(child: layer),
        Positioned(
          bottom: 0,
          right: 0,
          child: ColoredBox(
            color: Colors.black45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                light ? _attributionOsm : _attributionEsri,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
