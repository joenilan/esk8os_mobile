import 'package:flutter/material.dart';
import '../database/trip_database.dart';
import '../models/trail.dart';
import '../services/trip_backup.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';
import 'trail_detail_page.dart';
import 'trip_playback_page.dart';
import 'package:intl/intl.dart';

enum _LibrarySection { rides, trails, waypoints }

class TripHistoryPage extends StatefulWidget {
  final bool isMph;
  const TripHistoryPage({super.key, required this.isMph});

  @override
  State<TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<TripHistoryPage> {
  List<Map<String, dynamic>> _trips = [];
  List<Trail> _trails = [];
  List<Waypoint> _waypoints = [];
  bool _isLoading = true;
  _LibrarySection _section = _LibrarySection.rides;
  String _dbSizeStr = 'Calculating…';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final trips = await TripDatabase.instance.getAllTrips();
    final trails = await TripDatabase.instance.getAllTrails();
    final waypoints = await TripDatabase.instance.getAllWaypoints();
    final sizeBytes = await TripDatabase.instance.getDatabaseSize();
    final mb = sizeBytes / (1024 * 1024);

    if (mounted) {
      setState(() {
        _trips = trips;
        _trails = trails;
        _waypoints = waypoints;
        _dbSizeStr = '${mb.toStringAsFixed(2)} MB';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTrip(int id) async {
    final ok = await confirmAction(
      context,
      title: 'Delete trip?',
      message:
          'This permanently deletes the trip and its recorded telemetry. '
          'This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await TripDatabase.instance.deleteTrip(id);
    _loadData();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _export() async {
    try {
      final result = await TripBackup.export();
      _toast(
        result.isEmpty
            ? 'No library data to back up'
            : 'Backing up ${result.label}…',
      );
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _import() async {
    try {
      final result = await TripBackup.import();
      if (!result.isEmpty) {
        _loadData();
        _toast('Restored ${result.label}');
      }
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  Future<void> _createTrail(Map<String, dynamic> trip) async {
    final start = DateTime.fromMillisecondsSinceEpoch(trip['startTime'] as int);
    final name = TextEditingController(
      text: 'Trail · ${DateFormat('MMM d, yyyy').format(start)}',
    );
    final description = TextEditingController();
    final submitted = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create trail from ride'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'EVEE will copy this route into an editable private trail. '
              'The recorded ride remains unchanged.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Trail name'),
            ),
            TextField(
              controller: description,
              maxLength: 1000,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, (name.text, description.text)),
            icon: const Icon(Icons.alt_route),
            label: const Text('Create trail'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (submitted == null) return;

    try {
      final trail = await TripDatabase.instance.createTrailFromTrip(
        tripId: trip['id'] as int,
        name: submitted.$1,
        description: submitted.$2,
      );
      await _loadData();
      if (!mounted) return;
      _toast('${trail.name} added to Trails');
      setState(() => _section = _LibrarySection.trails);
    } catch (error) {
      _toast('Could not create trail: $error');
    }
  }

  Future<void> _deleteTrail(Trail trail) async {
    final id = trail.id;
    if (id == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete ${trail.name}?',
      message:
          'This deletes the curated trail copy. The source ride and its '
          'telemetry will not be changed.',
      confirmLabel: 'Delete trail',
    );
    if (!ok) return;
    await TripDatabase.instance.deleteTrail(id);
    _loadData();
  }

  Future<void> _deleteWaypoint(Waypoint waypoint) async {
    final id = waypoint.id;
    if (id == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete ${waypoint.name}?',
      message:
          'This removes the waypoint from your library. Its Trail and source '
          'Ride will not be changed.',
      confirmLabel: 'Delete waypoint',
    );
    if (!ok) return;
    await TripDatabase.instance.deleteWaypoint(id);
    _loadData();
  }

  String _formatDuration(int? startMs, int? endMs) {
    if (startMs == null || endMs == null) return 'Ongoing';
    final diff = Duration(milliseconds: endMs - startMs);
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${diff.inSeconds.remainder(60)}s';
  }

  @override
  Widget build(BuildContext context) {
    final unitStr = widget.isMph ? 'mi' : 'km';
    final speedUnitStr = widget.isMph ? 'mph' : 'km/h';

    return SubPageScaffold(
      title: 'Library',
      actions: [
        IconButton(
          icon: Icon(Icons.upload, color: Esk8Theme.accent),
          tooltip: 'Back up rides',
          onPressed: _export,
        ),
        IconButton(
          icon: Icon(Icons.download, color: Esk8Theme.accent),
          tooltip: 'Restore rides',
          onPressed: _import,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'DB $_dbSizeStr',
            style: TextStyle(color: Esk8Theme.dim, fontSize: 12),
          ),
        ),
      ],
      children: [
        Container(
          color: Esk8Theme.panel,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _LibrarySectionButton(
                  label: 'RIDES',
                  count: _trips.length,
                  selected: _section == _LibrarySection.rides,
                  onTap: () => setState(() => _section = _LibrarySection.rides),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LibrarySectionButton(
                  label: 'TRAILS',
                  count: _trails.length,
                  selected: _section == _LibrarySection.trails,
                  onTap: () =>
                      setState(() => _section = _LibrarySection.trails),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LibrarySectionButton(
                  label: 'POIS',
                  count: _waypoints.length,
                  selected: _section == _LibrarySection.waypoints,
                  onTap: () =>
                      setState(() => _section = _LibrarySection.waypoints),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildLibraryBody(unitStr, speedUnitStr)),
      ],
    );
  }

  Widget _buildLibraryBody(String unitStr, String speedUnitStr) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: Esk8Theme.accent));
    }
    return switch (_section) {
      _LibrarySection.rides =>
        _trips.isEmpty
            ? _emptyRideState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _trips.length,
                itemBuilder: (context, index) =>
                    _tripRow(_trips[index], unitStr, speedUnitStr),
              ),
      _LibrarySection.trails =>
        _trails.isEmpty
            ? _emptyTrailState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _trails.length,
                itemBuilder: (context, index) => _trailRow(_trails[index]),
              ),
      _LibrarySection.waypoints =>
        _waypoints.isEmpty
            ? _emptyWaypointState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _waypoints.length,
                itemBuilder: (context, index) =>
                    _waypointRow(_waypoints[index]),
              ),
    };
  }

  /// Anchored empty state, matching the scan-home board treatment.
  Widget _emptyRideState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Esk8Theme.border),
          ),
          child: Icon(Icons.route, size: 44, color: Esk8Theme.dim),
        ),
        const SizedBox(height: 24),
        Text(
          'NO TRIPS YET',
          style: TextStyle(
            fontSize: 18,
            letterSpacing: 2.5,
            fontWeight: FontWeight.bold,
            color: Esk8Theme.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Recorded rides show up here',
          style: TextStyle(fontSize: 13, color: Esk8Theme.dim),
        ),
      ],
    ),
  );

  Widget _emptyTrailState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Esk8Theme.border),
          ),
          child: Icon(Icons.alt_route, size: 44, color: Esk8Theme.dim),
        ),
        const SizedBox(height: 24),
        Text(
          'BUILD YOUR TRAIL MAP',
          style: TextStyle(
            fontSize: 18,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
            color: Esk8Theme.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Open Rides and save a recorded route as a private trail',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Esk8Theme.dim),
        ),
      ],
    ),
  );

  Widget _emptyWaypointState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Esk8Theme.border),
          ),
          child: Icon(Icons.place_outlined, size: 44, color: Esk8Theme.dim),
        ),
        const SizedBox(height: 24),
        Text(
          'NO POIS YET',
          style: TextStyle(
            fontSize: 18,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
            color: Esk8Theme.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Open a Trail and hold the map to mark places worth remembering',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Esk8Theme.dim),
        ),
      ],
    ),
  );

  /// One trip as a sharp bordered panel (no rounded Card), theme-reactive.
  Widget _tripRow(Map<String, dynamic> t, String unitStr, String speedUnitStr) {
    final startTime = DateTime.fromMillisecondsSinceEpoch(
      t['startTime'] as int,
    );
    final isComplete = t['endTime'] != null;
    final rawDist = t['distance'] as double;
    final distDisplay = widget.isMph ? (rawDist / 1609.34) : (rawDist / 1000.0);
    final rawMax = t['maxSpeed'] as double;
    final maxDisplay = widget.isMph ? (rawMax / 1.60934) : rawMax;
    final phoneGps = t['source'] == 'phone-gps';
    final sourceLabel = phoneGps ? 'PHONE GPS' : 'BOARD + GPS';
    final sourceIcon = phoneGps ? Icons.phone_android : Icons.bluetooth;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Esk8Theme.panel,
        child: InkWell(
          onTap: isComplete
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripPlaybackPage(
                        tripId: t['id'] as int,
                        isMph: widget.isMph,
                        tripData: t,
                      ),
                    ),
                  );
                }
              : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              border: Border.all(color: Esk8Theme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MMM d, yyyy · h:mm a').format(startTime),
                        style: TextStyle(
                          color: Esk8Theme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (!isComplete)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          'ONGOING',
                          style: TextStyle(
                            color: Esk8Theme.yellow,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.alt_route,
                        color: Esk8Theme.accent,
                        size: 20,
                      ),
                      tooltip: 'Create trail from ride',
                      onPressed: isComplete ? () => _createTrail(t) : null,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.ios_share,
                        color: Esk8Theme.accent,
                        size: 20,
                      ),
                      tooltip: 'Export GPX',
                      onPressed: () =>
                          TripBackup.exportGpx(t['id'] as int, startTime),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Esk8Theme.danger,
                        size: 20,
                      ),
                      tooltip: 'Delete',
                      onPressed: () => _deleteTrip(t['id'] as int),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(sourceIcon, size: 13, color: Esk8Theme.accent),
                    const SizedBox(width: 5),
                    Text(
                      sourceLabel,
                      style: TextStyle(
                        color: Esk8Theme.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _tripStat(
                          'DIST',
                          '${distDisplay.toStringAsFixed(2)} $unitStr',
                        ),
                      ),
                      Expanded(
                        child: _tripStat(
                          'MAX',
                          '${maxDisplay.toStringAsFixed(1)} $speedUnitStr',
                        ),
                      ),
                      Expanded(
                        child: _tripStat(
                          'TIME',
                          _formatDuration(t['startTime'], t['endTime']),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tripStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Esk8Theme.label,
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: Esk8Theme.textPrimary, fontSize: 13)),
    ],
  );

  Widget _trailRow(Trail trail) {
    final distance = trail.distanceM / (widget.isMph ? 1609.344 : 1000.0);
    final unit = widget.isMph ? 'mi' : 'km';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Esk8Theme.panel,
        child: InkWell(
          onTap: trail.id == null
              ? null
              : () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrailDetailPage(
                        trailId: trail.id!,
                        isMph: widget.isMph,
                      ),
                    ),
                  );
                  if (changed == true) _loadData();
                },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
            decoration: BoxDecoration(
              border: Border.all(color: Esk8Theme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Esk8Theme.border),
                  ),
                  child: Icon(Icons.alt_route, color: Esk8Theme.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trail.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Esk8Theme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${distance.toStringAsFixed(2)} $unit  ·  '
                        '${trail.surface.toUpperCase()}  ·  '
                        '${trail.difficulty.toUpperCase()}',
                        style: TextStyle(
                          color: Esk8Theme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${trail.pointCount} points · '
                        '${trail.segmentCount} segment${trail.segmentCount == 1 ? '' : 's'} · private',
                        style: TextStyle(color: Esk8Theme.dim, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete trail',
                  onPressed: () => _deleteTrail(trail),
                  icon: Icon(
                    Icons.delete_outline,
                    color: Esk8Theme.danger,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _waypointRow(Waypoint waypoint) {
    Trail? parentTrail;
    if (waypoint.trailId != null) {
      for (final trail in _trails) {
        if (trail.id == waypoint.trailId) {
          parentTrail = trail;
          break;
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Esk8Theme.panel,
        child: InkWell(
          onTap: parentTrail?.id == null
              ? null
              : () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrailDetailPage(
                        trailId: parentTrail!.id!,
                        isMph: widget.isMph,
                      ),
                    ),
                  );
                  if (changed == true) _loadData();
                },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              border: Border.all(color: Esk8Theme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Esk8Theme.accent, width: 2),
                  ),
                  child: Icon(
                    _waypointIcon(waypoint.type),
                    color: Esk8Theme.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        waypoint.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Esk8Theme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${waypoint.type.toUpperCase()}'
                        '${parentTrail == null ? '' : ' · ${parentTrail.name}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Esk8Theme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${waypoint.latitude.toStringAsFixed(5)}, '
                        '${waypoint.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          color: Esk8Theme.dim,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                if (parentTrail != null)
                  Icon(Icons.chevron_right, color: Esk8Theme.dim),
                IconButton(
                  tooltip: 'Delete waypoint',
                  onPressed: () => _deleteWaypoint(waypoint),
                  icon: Icon(
                    Icons.delete_outline,
                    color: Esk8Theme.danger,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

class _LibrarySectionButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _LibrarySectionButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? Esk8Theme.accent.withValues(alpha: 0.16)
        : Esk8Theme.scaffold,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Esk8Theme.accent : Esk8Theme.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$label · $count',
          style: TextStyle(
            color: selected ? Esk8Theme.accent : Esk8Theme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    ),
  );
}
