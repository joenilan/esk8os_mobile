import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart';

/// MapLibre + OpenFreeMap vector map (roadmap step 5).
///
/// Renders OpenFreeMap's free vector styles through MapLibre GL — no API key,
/// no tile caps, real map styling instead of raster images — behind the same
/// maps/ seam as the raster [EveeMap] basemap.
///
/// Scope: Android in-app surfaces (playback, trail detail, live ride). The
/// floating overlay runs in a separate engine where native map views don't
/// exist; it stays raster. The caller owns the camera via [onMapController]
/// and observes gestures via [onMapEvent]; layers diff natively on rebuild.
///
/// POI markers render as a symbol layer with pre-rendered per-type icons
/// (assets/map_markers/poi_TYPE.png) registered via StyleController.addImage
/// on style load — there is no icon-font path in maplibre 0.2.2.
///
/// Attribution: OpenFreeMap serves OpenStreetMap data and requires on-map
/// attribution, same rule as the raster path.
class EveeVectorMap extends StatefulWidget {
  const EveeVectorMap({
    super.key,
    required this.center,
    this.zoom = 16,
    this.dark = false,
    this.polylines = const [],
    this.trailBase,
    this.tipSegment,
    this.marker,
    this.waypointDots = const [],
    this.polylineColor = const Color(0xFFB950D7),
    this.onMapController,
    this.onMapEvent,
  });

  static const String attributionText =
      '© OpenStreetMap contributors · © OpenFreeMap';

  /// Camera position at construction (the caller drives it afterwards).
  final LatLng center;
  final double zoom;
  final bool dark;

  /// The full route, split into segments (pauses/GPS outages break the
  /// line), drawn dimmed under everything else.
  final List<List<LatLng>> polylines;

  /// The traveled portion of the ride, per segment, drawn at full strength.
  /// Pass the same instance when unchanged — the native layer diff skips
  /// identical sources.
  final List<List<LatLng>>? trailBase;

  /// The 2-point segment connecting the trail base to the interpolated scrub
  /// marker, so line and dot move as one entity. Rebuilt every frame.
  final List<LatLng>? tipSegment;

  /// The scrub/playback position dot.
  final LatLng? marker;

  /// POI markers with a map icon per type. Icons are pre-rendered assets
  /// (see scripts/gen_poi_icons.py); a type without an icon asset falls
  /// back to the plain disc.
  final List<PoiMarker> waypointDots;

  final Color polylineColor;
  final void Function(MapController controller)? onMapController;
  final void Function(MapEvent event)? onMapEvent;

  @override
  State<EveeVectorMap> createState() => _EveeVectorMapState();
}

/// A named POI position for the symbol layer.
class PoiMarker {
  const PoiMarker({required this.position, this.type = 'note'});

  final LatLng position;

  /// One of the trail POI types; selects the icon asset. Unknown types fall
  /// back to the plain pin ("poi_note").
  final String type;
}

class _EveeVectorMapState extends State<EveeVectorMap> {
  static const String _styleLight =
      'https://tiles.openfreemap.org/styles/liberty';
  static const String _styleDark = 'https://tiles.openfreemap.org/styles/dark';

  /// Icon PNGs registered into the style, named `poi_<type>`.
  final Set<String> _registeredImages = {};

  static const List<String> _poiTypes = [
    'trailhead',
    'hazard',
    'parking',
    'charging',
    'water',
    'viewpoint',
    'scenic',
    'food',
    'restroom',
    'shelter',
    'repair',
    'note',
  ];

  /// Register every POI icon into the loaded style. A failed asset load
  /// (missing file) is skipped — that type's MarkerLayer is suppressed and
  /// the caller can rely on dots instead, never a crash.
  Future<void> _loadPoiImages(StyleController style) async {
    for (final kind in _poiTypes) {
      try {
        final bytes = await rootBundle.load('assets/map_markers/poi_$kind.png');
        await style.addImage('poi_$kind', bytes.buffer.asUint8List());
        _registeredImages.add('poi_$kind');
      } catch (_) {
        // Icon unavailable: skip; that type's layer just won't render.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeLines = [
      for (final segment in widget.polylines)
        if (segment.length >= 2)
          LineString(
            coordinates: [
              for (final p in segment) Position(p.longitude, p.latitude),
            ],
          ),
    ];
    final trailLines = (widget.trailBase ?? const <List<LatLng>>[])
        .where((seg) => seg.length >= 2)
        .map(
          (seg) => LineString(
            coordinates: [
              for (final p in seg) Position(p.longitude, p.latitude),
            ],
          ),
        )
        .toList();
    // One symbol layer per POI type — MarkerLayer's iconImage is per-layer.
    final poisByType = <String, List<PoiMarker>>{};
    for (final poi in widget.waypointDots) {
      final key = _poiTypes.contains(poi.type) ? poi.type : 'note';
      (poisByType[key] ??= []).add(poi);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: MapLibreMap(
            options: MapOptions(
              initStyle: widget.dark ? _styleDark : _styleLight,
              initZoom: widget.zoom,
              initCenter: Position(
                widget.center.longitude,
                widget.center.latitude,
              ),
            ),
            layers: [
              if (routeLines.isNotEmpty)
                PolylineLayer(
                  polylines: routeLines,
                  color: widget.polylineColor.withValues(alpha: 0.5),
                  width: 4,
                ),
              if (trailLines.isNotEmpty)
                PolylineLayer(
                  polylines: trailLines,
                  color: widget.polylineColor,
                  width: 4,
                ),
              if (widget.tipSegment != null && widget.tipSegment!.length == 2)
                PolylineLayer(
                  polylines: [
                    LineString(
                      coordinates: [
                        for (final p in widget.tipSegment!)
                          Position(p.longitude, p.latitude),
                      ],
                    ),
                  ],
                  color: widget.polylineColor,
                  width: 4,
                ),
              for (final entry in poisByType.entries)
                MarkerLayer(
                  points: [
                    for (final poi in entry.value)
                      Point(
                        coordinates: Position(
                          poi.position.longitude,
                          poi.position.latitude,
                        ),
                      ),
                  ],
                  iconImage: 'poi_${entry.key}',
                  iconSize: 0.9,
                  iconAllowOverlap: true,
                ),
              if (widget.marker != null)
                CircleLayer(
                  points: [
                    Point(
                      coordinates: Position(
                        widget.marker!.longitude,
                        widget.marker!.latitude,
                      ),
                    ),
                  ],
                  radius: 7,
                  color: widget.polylineColor,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
            ],
            onMapCreated: (controller) =>
                widget.onMapController?.call(controller),
            onStyleLoaded: (style) async {
              await _loadPoiImages(style);
              if (mounted) setState(() {});
            },
            onEvent: widget.onMapEvent,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: ColoredBox(
            color: Colors.black45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                EveeVectorMap.attributionText,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
