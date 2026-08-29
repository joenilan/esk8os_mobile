import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Single source of truth for EVEE's raster basemap (CARTO tiles on OSM data).
///
/// Every map surface — the live ride map, playback, trail detail, and the
/// floating-ride overlay — renders through [basemap] so that:
///  * the dark "brightness bump" is applied consistently (trail detail used to
///    miss it and render near-black tiles),
///  * tile requests identify the app via [userAgentPackageName] (flutter_map
///    defaults to "unknown"; CARTO asks for an identifiable client),
///  * OSM/CARTO attribution ships on every surface, and
///  * the roadmap's future provider swap (licensed vector tiles / MapLibre /
///    self-hosted extracts) is a one-file change behind this seam.
class EveeMap {
  EveeMap._();

  static const String _voyagerUrl =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
  static const String _darkUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const List<String> _subdomains = ['a', 'b', 'c', 'd'];

  /// CARTO's free basemaps require visible OSM + CARTO attribution.
  static const String attributionText = '© OpenStreetMap contributors © CARTO';

  static const String userAgentPackageName = 'com.joenilan.esk8os_mobile';

  /// Brightness bump applied to dark tiles so they read like the app's theme.
  static const ColorFilter _darkBump = ColorFilter.matrix([
    1.5, 0, 0, 0, 15, //
    0, 1.5, 0, 0, 15, //
    0, 0, 1.5, 0, 15, //
    0, 0, 0, 1, 0, //
  ]);

  /// The basemap layer stack: tiles + attribution.
  ///
  /// [light] selects the Voyager style; dark uses dark_all with the brightness
  /// bump. [retina] substitutes @2x tiles for the `{r}` placeholder — the
  /// overlay passes `RetinaMode.isHighDensity(context)`; the in-app maps keep
  /// their historical `false` so tile traffic does not silently double.
  static Widget basemap({required bool light, bool retina = false}) {
    final TileLayer layer = TileLayer(
      urlTemplate: light ? _voyagerUrl : _darkUrl,
      subdomains: _subdomains,
      retinaMode: retina,
      userAgentPackageName: userAgentPackageName,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: light
              ? layer
              : ColorFiltered(colorFilter: _darkBump, child: layer),
        ),
        const Positioned(
          bottom: 0,
          right: 0,
          child: SimpleAttributionWidget(
            source: Text(
              attributionText,
              style: TextStyle(fontSize: 10, color: Colors.white),
            ),
            backgroundColor: Colors.black45,
          ),
        ),
      ],
    );
  }
}
