import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart';

/// MapLibre + OpenFreeMap vector prototype (roadmap step 5).
///
/// Renders OpenFreeMap's free vector styles through MapLibre GL — no API key,
/// no tile caps, real map styling instead of raster images — behind the same
/// maps/ seam as the raster [EveeMap] basemap. Prototype scope, deliberately:
///  * Android in-app surfaces only (playback first). The floating overlay runs
///    in a separate engine where native map views don't exist; it stays raster.
///  * Camera is fixed at construction; follow/scrub camera work lands after
///    the stack proves itself on hardware.
///  * The live ride map keeps the proven raster path until this is validated.
///
/// Attribution: OpenFreeMap serves OpenStreetMap data and requires on-map
/// attribution, same rule as the raster path.
class EveeVectorMap extends StatelessWidget {
  const EveeVectorMap({
    super.key,
    required this.center,
    this.zoom = 16,
    this.dark = false,
    this.polylines = const [],
    this.polylineColor = const Color(0xFFB950D7),
  });

  // OpenFreeMap hosted styles (verified live 2026-08-29): liberty, bright,
  // positron and dark. No key, no registration.
  static const String _styleLight =
      'https://tiles.openfreemap.org/styles/positron';
  static const String _styleDark = 'https://tiles.openfreemap.org/styles/dark';

  static const String attributionText =
      '© OpenStreetMap contributors · © OpenFreeMap';

  /// Route start (map opens here).
  final LatLng center;
  final double zoom;
  final bool dark;

  /// Route segments in the app'sLatLng form; each becomes a vector LineString.
  final List<List<LatLng>> polylines;
  final Color polylineColor;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final segment in polylines)
        if (segment.length >= 2)
          LineString(
            coordinates: [
              for (final p in segment) Position(p.longitude, p.latitude),
            ],
          ),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: MapLibreMap(
            options: MapOptions(
              initStyle: dark ? _styleDark : _styleLight,
              initZoom: zoom,
              initCenter: Position(center.longitude, center.latitude),
            ),
            layers: [
              if (lines.isNotEmpty)
                PolylineLayer(
                  polylines: lines,
                  color: polylineColor.withValues(alpha: 0.75),
                  width: 4,
                ),
            ],
          ),
        ),
        const Positioned(
          bottom: 0,
          right: 0,
          child: ColoredBox(
            color: Colors.black45,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                attributionText,
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
