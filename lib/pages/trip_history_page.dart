import 'package:flutter/material.dart';
import '../database/trip_database.dart';
import '../services/trip_backup.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/esk8_theme.dart';
import 'trip_playback_page.dart';
import 'package:intl/intl.dart';

class TripHistoryPage extends StatefulWidget {
  final bool isMph;
  const TripHistoryPage({super.key, required this.isMph});

  @override
  State<TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<TripHistoryPage> {
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;
  String _dbSizeStr = 'Calculating…';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final trips = await TripDatabase.instance.getAllTrips();
    final sizeBytes = await TripDatabase.instance.getDatabaseSize();
    final mb = sizeBytes / (1024 * 1024);

    if (mounted) {
      setState(() {
        _trips = trips;
        _dbSizeStr = '${mb.toStringAsFixed(2)} MB';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTrip(int id) async {
    final ok = await confirmAction(
      context,
      title: 'Delete trip?',
      message: 'This permanently deletes the trip and its recorded telemetry. '
          'This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await TripDatabase.instance.deleteTrip(id);
    _loadData();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _export() async {
    try {
      final n = await TripBackup.export();
      _toast(n == 0 ? 'No rides to back up' : 'Backing up $n ride(s)…');
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _import() async {
    try {
      final n = await TripBackup.import();
      if (n > 0) {
        _loadData();
        _toast('Restored $n ride(s)');
      }
    } catch (e) {
      _toast('Import failed: $e');
    }
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

    return Scaffold(
      backgroundColor: Esk8Theme.scaffold,
      appBar: AppBar(
        backgroundColor: Esk8Theme.scaffold,
        title: const Text('Trip History',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
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
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text('DB $_dbSizeStr',
                  style: TextStyle(color: Esk8Theme.dim, fontSize: 12)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Esk8Theme.accent))
          : _trips.isEmpty
              ? _emptyState()
              : ListView.builder(
                  itemCount: _trips.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) =>
                      _tripRow(_trips[index], unitStr, speedUnitStr),
                ),
    );
  }

  /// Anchored empty state, matching the scan-home board treatment.
  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(border: Border.all(color: Esk8Theme.border)),
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
            Text('Recorded rides show up here',
                style: TextStyle(fontSize: 13, color: Esk8Theme.dim)),
          ],
        ),
      );

  /// One trip as a sharp bordered panel (no rounded Card), theme-reactive.
  Widget _tripRow(Map<String, dynamic> t, String unitStr, String speedUnitStr) {
    final startTime = DateTime.fromMillisecondsSinceEpoch(t['startTime'] as int);
    final isComplete = t['endTime'] != null;
    final rawDist = t['distance'] as double;
    final distDisplay = widget.isMph ? (rawDist / 1609.34) : (rawDist / 1000.0);
    final rawMax = t['maxSpeed'] as double;
    final maxDisplay = widget.isMph ? (rawMax / 1.60934) : rawMax;

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
            decoration:
                BoxDecoration(border: Border.all(color: Esk8Theme.border)),
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
                        child: Text('ONGOING',
                            style: TextStyle(
                                color: Esk8Theme.yellow,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1)),
                      ),
                    IconButton(
                      icon: Icon(Icons.ios_share, color: Esk8Theme.accent, size: 20),
                      tooltip: 'Export GPX',
                      onPressed: () => TripBackup.exportGpx(t['id'] as int, startTime),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Esk8Theme.danger, size: 20),
                      tooltip: 'Delete',
                      onPressed: () => _deleteTrip(t['id'] as int),
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
                              'DIST', '${distDisplay.toStringAsFixed(2)} $unitStr')),
                      Expanded(
                          child: _tripStat('MAX',
                              '${maxDisplay.toStringAsFixed(1)} $speedUnitStr')),
                      Expanded(
                          child: _tripStat('TIME',
                              _formatDuration(t['startTime'], t['endTime']))),
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
          Text(label,
              style: TextStyle(
                  color: Esk8Theme.label,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: Esk8Theme.textPrimary, fontSize: 13)),
        ],
      );
}
