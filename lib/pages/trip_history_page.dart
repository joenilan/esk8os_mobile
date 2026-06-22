import 'package:flutter/material.dart';
import '../database/trip_database.dart';
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
    await TripDatabase.instance.deleteTrip(id);
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Trip History', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                'DB Size: $_dbSizeStr',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
          : _trips.isEmpty
              ? const Center(child: Text('No trips recorded yet.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _trips.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final t = _trips[index];
                    final startTime = DateTime.fromMillisecondsSinceEpoch(t['startTime'] as int);
                    final isComplete = t['endTime'] != null;

                    final rawDist = t['distance'] as double;
                    final distDisplay = widget.isMph ? (rawDist / 1609.34) : (rawDist / 1000.0);
                    final rawMax = t['maxSpeed'] as double;
                    final maxDisplay = widget.isMph ? (rawMax / 1.60934) : rawMax;

                    return Card(
                      color: const Color(0xDD1E1E1E),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Color(0xFF333333)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
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
                        title: Text(
                          DateFormat('MMM d, yyyy - h:mm a').format(startTime),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Dist: ${distDisplay.toStringAsFixed(2)} $unitStr', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              Text('Max: ${maxDisplay.toStringAsFixed(1)} $speedUnitStr', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              Text('Time: ${_formatDuration(t['startTime'], t['endTime'])}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _deleteTrip(t['id'] as int),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
