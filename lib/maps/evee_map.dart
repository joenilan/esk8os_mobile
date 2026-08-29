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

  static const String _attribution =
      '© OpenStreetMap contributors · Tiles © Esri';

  static const String userAgentPackageName = 'com.joenilan.esk8os_mobile';

  /// The basemap layer stack: tiles + attribution.
  static Widget basemap({required bool light}) {
    final TileLayer layer = TileLayer(
      urlTemplate: light ? _osmUrl : _esriDarkUrl,
      userAgentPackageName: userAgentPackageName,
      maxNativeZoom: light ? 19 : 16,
    );
    return Stack(
      children: [
        Positioned.fill(child: layer),
        const Positioned(
          bottom: 0,
          right: 0,
          child: SimpleAttributionWidget(
            source: Text(
              _attribution,
              style: TextStyle(fontSize: 10, color: Colors.white),
            ),
            backgroundColor: Colors.black45,
          ),
        ),
      ],
    );
  }
}
