import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../database/trip_database.dart';
import '../models/trail.dart';
import '../services/app_prefs.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trail = await TripDatabase.instance.getTrail(widget.trailId);
    final points = await TripDatabase.instance.getTrailPoints(widget.trailId);
    final waypoints = await TripDatabase.instance.getWaypointsForTrail(
      widget.trailId,
    );
    if (!mounted) return;
    setState(() {
      _trail = trail;
      _points = points;
      _waypoints = waypoints;
      _loading = false;
    });
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
      _mapController.move(all.first, 16);
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
                        if (_mapLight)
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                          )
                        else
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                          ),
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
