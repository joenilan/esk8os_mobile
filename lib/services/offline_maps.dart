import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart';

/// Offline map regions (roadmap step 5): download a trail's surrounding area
/// once over WiFi, ride it with zero signal.
///
/// Regions render through the same OpenFreeMap vector style as the on-map
/// beta. Plugin note (maplibre 0.2.2): regions cannot be deleted
/// individually — only a full database reset — so the service exposes
/// [deleteAll] and callers must label it honestly.
class OfflineMaps {
  OfflineMaps._();

  /// Same style the vector basemap renders, so offline regions and the live
  /// map share tiles.
  static const String styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  static const double minZoom = 10;
  static const double maxZoom = 14;

  /// MapLibre's own default cap; raised a little for trail-sized regions.
  static const int tileCountLimit = 8000;

  /// Pad the trail's bounding box by roughly this many meters on each side so
  /// the ride area plus surroundings are covered.
  static const double padMeters = 800;

  /// Download a region covering [bounds]. Returns the completed region.
  /// [onProgress] receives 0..1 (null while the tile total is still an
  /// estimate) plus raw byte counts.
  static Future<OfflineRegion> download({
    required LngLatBounds bounds,
    String styleUrlOverride = styleUrl,
    void Function(double? progress, int loadedBytes)? onProgress,
  }) async {
    final manager = await OfflineManager.createInstance();
    try {
      manager.setOfflineTileCountLimit(amount: tileCountLimit);
      final stream = manager.downloadRegion(
        mapStyleUrl: styleUrlOverride,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        pixelDensity: 1.0,
      );
      OfflineRegion? region;
      await for (final p in stream) {
        onProgress?.call(p.progress, p.loadedBytes);
        if (p.downloadCompleted) {
          region = p.region;
          break;
        }
      }
      if (region == null) {
        throw StateError('offline download ended without a completed region');
      }
      return region;
    } finally {
      manager.dispose();
    }
  }

  /// All downloaded regions.
  static Future<List<OfflineRegion>> list() async {
    final manager = await OfflineManager.createInstance();
    try {
      return manager.listOfflineRegions();
    } finally {
      manager.dispose();
    }
  }

  /// True when a region covering this center (±150 m) already exists — the
  /// plugin can't read region metadata back, so presence is matched by
  /// bounds center and zoom range.
  static Future<bool> hasRegionFor(LatLng center) async {
    final regions = await list();
    for (final r in regions) {
      final cLat = (r.bounds.latitudeSouth + r.bounds.latitudeNorth) / 2;
      final cLng = (r.bounds.longitudeWest + r.bounds.longitudeEast) / 2;
      final near =
          (cLat - center.latitude).abs() < 0.0015 &&
          (cLng - center.longitude).abs() < 0.0015;
      if (near && r.minZoom <= minZoom && r.maxZoom >= maxZoom) return true;
    }
    return false;
  }

  /// Deletes EVERY downloaded region (plugin limit: no per-region delete).
  static Future<void> deleteAll() async {
    final manager = await OfflineManager.createInstance();
    try {
      await manager.resetDatabase();
    } finally {
      manager.dispose();
    }
  }

  /// The trail's bounding box, padded on every side.
  static LngLatBounds boundsFor(List<LatLng> points) {
    var west = points.first.longitude;
    var east = points.first.longitude;
    var south = points.first.latitude;
    var north = points.first.latitude;
    for (final p in points) {
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
    }
    const degPerM = 1 / 111320.0;
    final pad = padMeters * degPerM;
    return LngLatBounds(
      longitudeWest: west - pad,
      longitudeEast: east + pad,
      latitudeSouth: south - pad,
      latitudeNorth: north + pad,
    );
  }
}
