import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart';

/// MapLibre + OpenFreeMap vector map (roadmap step 5).
///
/// Renders OpenFreeMap's free vector styles through MapLibre GL — no API key,
/// no tile caps, real map styling instead of raster images — behind the same
/// maps/ seam as the raster [EveeMap] basemap.
///
/// Scope: Android in-app surfaces (playback first). The floating overlay runs
/// in a separate engine where native map views don't exist; it stays raster.
/// The caller owns the camera via [onMapController] and observes gestures via
/// [onMapEvent]; route/trail/marker layers diff natively on rebuild, so a
/// per-frame rebuild is cheap (same model as the raster path).
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
    this.trailBase,
    this.tipSegment,
    this.marker,
    this.polylineColor = const Color(0xFFB950D7),
    this.onMapController,
    this.onMapEvent,
  });

  // OpenFreeMap hosted styles (verified live 2026-08-29): liberty (colorful,
  // like the OSM default), bright, positron (grayscale) and dark. No key,
  // no registration. Liberty reads best in daylight; dark matches the theme.
  static const String _styleLight =
      'https://tiles.openfreemap.org/styles/liberty';
  static const String _styleDark = 'https://tiles.openfreemap.org/styles/dark';

  static const String attributionText =
      '© OpenStreetMap contributors · © OpenFreeMap';

  /// Camera position at construction (the caller drives it afterwards).
  final LatLng center;
  final double zoom;
  final bool dark;

  /// The full route, drawn dimmed under everything else.
  final List<List<LatLng>> polylines;

  /// The traveled portion of the ride, drawn at full strength. Pass the same
  /// instance when unchanged — the native layer diff skips identical sources.
  final List<LatLng>? trailBase;

  /// The 2-point segment connecting the trail base to the interpolated scrub
  /// marker, so line and dot move as one entity. Rebuilt every frame.
  final List<LatLng>? tipSegment;

  /// The scrub/playback position dot.
  final LatLng? marker;
  final Color polylineColor;
  final void Function(MapController controller)? onMapController;
  final void Function(MapEvent event)? onMapEvent;

  @override
  Widget build(BuildContext context) {
    final routeLines = [
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
              if (routeLines.isNotEmpty)
                PolylineLayer(
                  polylines: routeLines,
                  color: polylineColor.withValues(alpha: 0.5),
                  width: 4,
                ),
              if (trailBase != null && trailBase!.length >= 2)
                PolylineLayer(
                  polylines: [
                    LineString(
                      coordinates: [
                        for (final p in trailBase!)
                          Position(p.longitude, p.latitude),
                      ],
                    ),
                  ],
                  color: polylineColor,
                  width: 4,
                ),
              if (tipSegment != null && tipSegment!.length == 2)
                PolylineLayer(
                  polylines: [
                    LineString(
                      coordinates: [
                        for (final p in tipSegment!)
                          Position(p.longitude, p.latitude),
                      ],
                    ),
                  ],
                  color: polylineColor,
                  width: 4,
                ),
              if (marker != null)
                CircleLayer(
                  points: [
                    Point(
                      coordinates: Position(
                        marker!.longitude,
                        marker!.latitude,
                      ),
                    ),
                  ],
                  radius: 7,
                  color: polylineColor,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
            ],
            onMapCreated: (controller) => onMapController?.call(controller),
            onEvent: onMapEvent,
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
