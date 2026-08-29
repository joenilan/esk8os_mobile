import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import '../maps/evee_map.dart';
import '../maps/evee_vector_map.dart';

import '../database/trip_database.dart';
import '../models/trail.dart';
import '../services/app_prefs.dart';
import '../services/offline_maps.dart';
import '../services/trail_export.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

class TrailDetailPage extends StatefulWidget {
  final int trailId;
  final bool isMph;

  const TrailDetailPage({
    super.key,
    required this.trailId,
    required this.isMph,
  });

  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends State<TrailDetailPage> {
  final MapController _mapController = MapController();
  Trail? _trail;
  List<TrailPoint> _points = const [];
  List<Waypoint> _waypoints = const [];
  bool _loading = true;
  bool _mapLight = AppPrefs.mapLight;
  // Vector beta (roadmap step 5): the same MapLibre + OpenFreeMap stack as
  // playback, with long-click POI creation and click-to-view via nearest-POI.
  bool _useVectorMap = AppPrefs.vectorBasemap;
  ml.MapController? _vectorController;
  // Offline trail maps (roadmap step 5).
  bool _offlineBusy = false;
  bool _offlineSaved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Ground distance in meters between two points (equirectangular — plenty
  /// for tap targets at city zooms).
  static double _latLngDist(LatLng a, LatLng b) {
    final dLat = (a.latitude - b.latitude) * 111320;
    final dLng =
        (a.longitude - b.longitude) *
        111320 *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  Future<void> _load() async {
    final trail = await TripDatabase.instance.getTrail(widget.trailId);
    final points = await TripDatabase.instance.getTrailPoints(widget.trailId);
    final waypoints = await TripDatabase.instance.getWaypointsForTrail(
      widget.trailId,
    );
    final saved = points.isNotEmpty
        ? await OfflineMaps.hasRegionFor(
            LatLng(points.first.latitude, points.first.longitude),
          )
        : false;
    if (!mounted) return;
    setState(() {
      _trail = trail;
      _points = points;
      _waypoints = waypoints;
      _offlineSaved = saved;
      _loading = false;
    });
  }

  /// Download this trail's surrounding area for offline use. The progress
  /// dialog is informational — the MapLibre offline pipeline continues in the
  /// background and the region persists even if the dialog is dismissed.
  Future<void> _downloadOffline() async {
    if (_points.isEmpty || _offlineBusy) return;
    setState(() => _offlineBusy = true);
    final progress = ValueNotifier<double?>(null);
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, _) => AlertDialog(
            backgroundColor: Esk8Theme.panel,
            title: Text(
              'Saving offline map',
              style: TextStyle(color: Esk8Theme.textPrimary, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: value,
                  color: Esk8Theme.accent,
                  backgroundColor: Esk8Theme.border,
                ),
                const SizedBox(height: 14),
                Text(
                  value == null
                      ? 'Preparing…'
                      : '${(value * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Esk8Theme.dim, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  'Keep the app open. The area works with zero signal once saved.',
                  style: TextStyle(color: Esk8Theme.dim, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await OfflineMaps.download(
        bounds: OfflineMaps.boundsFor([
          for (final p in _points) LatLng(p.latitude, p.longitude),
        ]),
        onProgress: (p, _) => progress.value = p,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _offlineSaved = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Offline map saved')));
    } catch (error) {
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offline download failed: $error')),
      );
    } finally {
      progress.dispose();
      if (mounted) setState(() => _offlineBusy = false);
    }
  }

  /// The plugin has no per-region delete; this resets the whole offline
  /// store, so it lives behind a confirm that says exactly that.
  Future<void> _confirmDeleteOffline() async {
    final ok = await confirmAction(
      context,
      title: 'Delete offline maps?',
      message:
          'This removes EVERY downloaded offline map area on this device, '
          'not just this trail. Downloaded areas can be restored from the '
          'trail pages afterwards.',
      confirmLabel: 'Delete all',
    );
    if (!ok) return;
    try {
      await OfflineMaps.deleteAll();
      if (mounted) {
        setState(() => _offlineSaved = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Offline maps deleted')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    }
  }

  List<List<LatLng>> get _segments {
    final grouped = <int, List<LatLng>>{};
    for (final point in _points) {
      grouped
          .putIfAbsent(point.segment, () => [])
          .add(LatLng(point.latitude, point.longitude));
    }
    return grouped.values.where((segment) => segment.length >= 2).toList();
  }

  Future<void> _fitRoute() async {
    final all = [
      for (final point in _points) LatLng(point.latitude, point.longitude),
    ];
    if (all.isEmpty) return;
    if (all.length == 1) {
      if (_useVectorMap && _vectorController != null) {
        _vectorController!.moveCamera(
          center: ml.Position(all.first.longitude, all.first.latitude),
          zoom: 16,
        );
      } else {
        _mapController.move(all.first, 16);
      }
      return;
    }
    if (_useVectorMap && _vectorController != null) {
      final west = all.map((p) => p.longitude).reduce(math.min);
      final east = all.map((p) => p.longitude).reduce(math.max);
      final south = all.map((p) => p.latitude).reduce(math.min);
      final north = all.map((p) => p.latitude).reduce(math.max);
      _vectorController!.fitBounds(
        bounds: ml.LngLatBounds(
          longitudeWest: west,
          longitudeEast: east,
          latitudeSouth: south,
          latitudeNorth: north,
        ),
      );
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(all),
        padding: const EdgeInsets.all(42),
      ),
    );
  }

  Future<void> _editTrail() async {
    final trail = _trail;
    if (trail == null) return;
    final name = TextEditingController(text: trail.name);
    final description = TextEditingController(text: trail.description);
    var surface = trail.surface;
    var difficulty = trail.difficulty;
    var direction = trail.direction;

    final edited = await showDialog<Trail>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit trail'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: description,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description / notes',
                  ),
                ),
                _TrailDropdown(
                  label: 'Surface',
                  value: surface,
                  values: const [
                    'unknown',
                    'paved',
                    'gravel',
                    'dirt',
                    'grass',
                    'mixed',
                  ],
                  onChanged: (value) => setDialogState(() => surface = value),
                ),
                _TrailDropdown(
                  label: 'Difficulty',
                  value: difficulty,
                  values: const [
                    'unknown',
                    'easy',
                    'moderate',
                    'hard',
                    'expert',
                  ],
                  onChanged: (value) =>
                      setDialogState(() => difficulty = value),
                ),
                _TrailDropdown(
                  label: 'Direction',
                  value: direction,
                  values: const ['both', 'one-way', 'loop'],
                  onChanged: (value) => setDialogState(() => direction = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      dialogContext,
                      trail.copyWith(
                        name: name.text,
                        description: description.text,
                        surface: surface,
                        difficulty: difficulty,
                        direction: direction,
                      ),
                    ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    if (edited == null) return;

    await TripDatabase.instance.updateTrailMetadata(edited);
    await _load();
  }

  Future<void> _deleteTrail() async {
    final trail = _trail;
    if (trail == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${trail.name}?',
      message:
          'This deletes the curated trail copy. Its source ride and recorded '
          'telemetry will not be changed.',
      confirmLabel: 'Delete trail',
    );
    if (!confirmed) return;
    await TripDatabase.instance.deleteTrail(widget.trailId);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _addWaypoint(LatLng point) async {
    final name = TextEditingController();
    final notes = TextEditingController();
    var type = 'note';
    final submitted = await showDialog<(String, String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add point of interest'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                _TrailDropdown(
                  label: 'Type',
                  value: type,
                  values: const [
                    'note',
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
                  ],
                  onChanged: (value) => setDialogState(() => type = value),
                ),
                TextField(
                  controller: notes,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, (
                      name.text,
                      type,
                      notes.text,
                    )),
              child: const Text('Add POI'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    notes.dispose();
    if (submitted == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await TripDatabase.instance.createWaypoint(
      Waypoint(
        trailId: widget.trailId,
        sourceTripId: _trail?.sourceTripId,
        name: submitted.$1,
        type: submitted.$2,
        notes: submitted.$3.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _load();
  }

  Future<void> _showWaypoint(Waypoint waypoint) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(waypoint.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              waypoint.type.toUpperCase(),
              style: TextStyle(
                color: Esk8Theme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            if (waypoint.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(waypoint.notes),
            ],
            const SizedBox(height: 10),
            Text(
              '${waypoint.latitude.toStringAsFixed(5)}, '
              '${waypoint.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(Icons.delete_outline, color: Esk8Theme.danger),
            label: Text('Delete', style: TextStyle(color: Esk8Theme.danger)),
          ),
        ],
      ),
    );
    if (delete != true || waypoint.id == null) return;
    await TripDatabase.instance.deleteWaypoint(waypoint.id!);
    await _load();
  }

  Future<void> _shareTrail(String format) async {
    final trail = _trail;
    if (trail == null || _points.isEmpty) return;
    try {
      if (format == 'gpx') {
        await TrailExport.shareGpx(trail, _points, _waypoints);
      } else {
        await TrailExport.shareGeoJson(trail, _points, _waypoints);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Trail export failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trail = _trail;
    final unit = widget.isMph ? 'mi' : 'km';
    final distance = trail == null
        ? 0.0
        : trail.distanceM / (widget.isMph ? 1609.344 : 1000);

    return SubPageScaffold(
      title: trail?.name ?? 'Trail',
      actions: [
        IconButton(
          tooltip: _mapLight ? 'Dark map' : 'Light map',
          onPressed: () => setState(() {
            _mapLight = !_mapLight;
            AppPrefs.mapLight = _mapLight;
          }),
          icon: Icon(
            _mapLight ? Icons.dark_mode : Icons.light_mode,
            color: Esk8Theme.accent,
          ),
        ),
        IconButton(
          tooltip: _useVectorMap
              ? 'Vector basemap (beta) — tap for raster'
              : 'Try the vector basemap (beta)',
          onPressed: () => setState(() {
            _useVectorMap = !_useVectorMap;
            AppPrefs.vectorBasemap = _useVectorMap;
          }),
          icon: Icon(
            Icons.layers_outlined,
            color: _useVectorMap ? Esk8Theme.green : Esk8Theme.accent,
          ),
        ),
        IconButton(
          tooltip: _offlineSaved
              ? 'Offline map saved — long-press to delete ALL offline maps'
              : 'Save this area for offline use',
          onPressed: (_points.isEmpty || _offlineBusy)
              ? null
              : _downloadOffline,
          onLongPress: _offlineSaved ? _confirmDeleteOffline : null,
          icon: Icon(
            _offlineSaved ? Icons.offline_pin : Icons.download_for_offline,
            color: _offlineSaved ? Esk8Theme.green : Esk8Theme.accent,
          ),
        ),
        IconButton(
          tooltip: 'Fit trail',
          onPressed: _points.isEmpty ? null : _fitRoute,
          icon: Icon(Icons.center_focus_strong, color: Esk8Theme.accent),
        ),
        IconButton(
          tooltip: 'Edit trail',
          onPressed: trail == null ? null : _editTrail,
          icon: Icon(Icons.edit_outlined, color: Esk8Theme.accent),
        ),
        PopupMenuButton<String>(
          tooltip: 'Share trail',
          enabled: trail != null && _points.isNotEmpty,
          onSelected: _shareTrail,
          icon: Icon(Icons.ios_share, color: Esk8Theme.accent),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'gpx',
              child: ListTile(
                leading: Icon(Icons.route_outlined),
                title: Text('Share GPX'),
                subtitle: Text('Tracks and waypoints'),
              ),
            ),
            PopupMenuItem(
              value: 'geojson',
              child: ListTile(
                leading: Icon(Icons.data_object),
                title: Text('Share GeoJSON'),
                subtitle: Text('Segments, metadata, and waypoints'),
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Delete trail',
          onPressed: trail == null ? null : _deleteTrail,
          icon: Icon(Icons.delete_outline, color: Esk8Theme.danger),
        ),
      ],
      children: [
        if (trail != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Esk8Theme.panel,
              border: Border(bottom: BorderSide(color: Esk8Theme.border)),
            ),
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _TrailFact('DISTANCE', '${distance.toStringAsFixed(2)} $unit'),
                _TrailFact('SURFACE', trail.surface.toUpperCase()),
                _TrailFact('DIFFICULTY', trail.difficulty.toUpperCase()),
                _TrailFact('DIRECTION', trail.direction.toUpperCase()),
                _TrailFact(
                  'EVIDENCE',
                  '${trail.pointCount} PTS · ${trail.segmentCount} SEG',
                ),
                _TrailFact('POIS', '${_waypoints.length}'),
                const _TrailFact('VISIBILITY', 'PRIVATE'),
              ],
            ),
          ),
        if (trail?.description.isNotEmpty == true)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            color: Esk8Theme.panel,
            child: Text(
              trail!.description,
              style: TextStyle(color: Esk8Theme.textMuted, fontSize: 13),
            ),
          ),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: Esk8Theme.accent),
                )
              : _points.isEmpty
              ? Center(
                  child: Text(
                    'NO TRAIL GEOMETRY',
                    style: TextStyle(color: Esk8Theme.dim),
                  ),
                )
              : Stack(
                  children: [
                    if (_useVectorMap)
                      // Roadmap step-5 beta: the same MapLibre + OpenFreeMap
                      // stack as playback. Long-click creates a POI and a
                      // click opens the nearest one, matching the raster map.
                      EveeVectorMap(
                        center: LatLng(
                          _points.first.latitude,
                          _points.first.longitude,
                        ),
                        zoom: 15,
                        dark: !_mapLight,
                        polylines: _segments,
                        waypointDots: [
                          for (final waypoint in _waypoints)
                            LatLng(waypoint.latitude, waypoint.longitude),
                        ],
                        polylineColor: Esk8Theme.accent,
                        onMapController: (controller) =>
                            _vectorController = controller,
                        onMapEvent: (event) {
                          final isLongClick = event is ml.MapEventLongClick;
                          final isClick = event is ml.MapEventClick;
                          if (!isLongClick && !isClick) return;
                          final p = (event as ml.MapEventUserInput).point;
                          final tapped = LatLng(
                            p.lat.toDouble(),
                            p.lng.toDouble(),
                          );
                          if (isLongClick) {
                            _addWaypoint(tapped);
                            return;
                          }
                          // Click: open the nearest POI within a touch's
                          // worth of ground distance at the current zoom.
                          final mpp =
                              156543.03392 *
                              math.cos(tapped.latitude * math.pi / 180) /
                              math.pow(2, 15);
                          final threshold = (24 * mpp).clamp(10.0, 150.0);
                          Waypoint? nearest;
                          var best = double.infinity;
                          for (final waypoint in _waypoints) {
                            final w = LatLng(
                              waypoint.latitude,
                              waypoint.longitude,
                            );
                            final d = _latLngDist(tapped, w);
                            if (d < best) {
                              best = d;
                              nearest = waypoint;
                            }
                          }
                          if (nearest != null && best <= threshold) {
                            _showWaypoint(nearest);
                          }
                        },
                      )
                    else
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(
                            _points.first.latitude,
                            _points.first.longitude,
                          ),
                          initialZoom: 15,
                          onMapReady: _fitRoute,
                          onLongPress: (_, point) => _addWaypoint(point),
                        ),
                        children: [
                          // Shared EveeMap source — this also picks up the dark
                          // brightness bump the other map surfaces already had.
                          EveeMap.basemap(light: _mapLight),
                          PolylineLayer(
                            polylines: [
                              for (final segment in _segments)
                                Polyline(
                                  points: segment,
                                  strokeWidth: 4,
                                  color: Esk8Theme.accent,
                                ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              for (final waypoint in _waypoints)
                                Marker(
                                  point: LatLng(
                                    waypoint.latitude,
                                    waypoint.longitude,
                                  ),
                                  width: 38,
                                  height: 38,
                                  child: GestureDetector(
                                    onTap: () => _showWaypoint(waypoint),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Esk8Theme.panel,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Esk8Theme.accent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        _waypointIcon(waypoint.type),
                                        color: Esk8Theme.accent,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SimpleAttributionWidget(
                            source: Text(
                              '© OpenStreetMap contributors · © CARTO',
                              style: TextStyle(
                                color: _mapLight
                                    ? Colors.black54
                                    : Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                            backgroundColor: _mapLight
                                ? const Color(0xAAFFFFFF)
                                : const Color(0xAA1E1E1E),
                          ),
                        ],
                      ),
                    Positioned(
                      left: 12,
                      bottom: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        color: Esk8Theme.panel.withValues(alpha: 0.9),
                        child: Text(
                          'HOLD MAP TO ADD POI',
                          style: TextStyle(
                            color: Esk8Theme.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  static IconData _waypointIcon(String type) => switch (type) {
    'trailhead' => Icons.signpost_outlined,
    'hazard' => Icons.warning_amber,
    'parking' => Icons.local_parking,
    'charging' => Icons.battery_charging_full,
    'water' => Icons.water_drop_outlined,
    'viewpoint' => Icons.landscape_outlined,
    'scenic' => Icons.photo_camera_outlined,
    'food' => Icons.restaurant_outlined,
    'restroom' => Icons.wc,
    'shelter' => Icons.cabin_outlined,
    'repair' => Icons.build_outlined,
    _ => Icons.place_outlined,
  };
}

class _TrailDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  const _TrailDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final option in values)
        DropdownMenuItem(value: option, child: Text(option.toUpperCase())),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _TrailFact extends StatelessWidget {
  final String label;
  final String value;

  const _TrailFact(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Esk8Theme.labelStyle),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          color: Esk8Theme.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
