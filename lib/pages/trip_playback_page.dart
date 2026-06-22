import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../database/trip_database.dart';

class TripPlaybackPage extends StatefulWidget {
  final int tripId;
  final bool isMph;
  final Map<String, dynamic> tripData;

  const TripPlaybackPage({super.key, required this.tripId, required this.isMph, required this.tripData});

  @override
  State<TripPlaybackPage> createState() => _TripPlaybackPageState();
}

class _TripPlaybackPageState extends State<TripPlaybackPage> {
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _telemetry = [];
  List<LatLng> _route = [];
  bool _isLoading = true;

  int _currentIndex = 0;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadTelemetry();
  }

  Future<void> _loadTelemetry() async {
    final data = await TripDatabase.instance.getTripTelemetry(widget.tripId);
    if (mounted) {
      setState(() {
        _telemetry = data;
        _route = data.map((t) => LatLng(t['lat'] as double, t['lng'] as double)).toList();
        _isLoading = false;
      });

      if (_route.isNotEmpty) {
        // Delay map fit bounds slightly so map is ready
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            final bounds = LatLngBounds.fromPoints(_route);
            if (bounds.southWest.latitude == bounds.northEast.latitude && 
                bounds.southWest.longitude == bounds.northEast.longitude) {
              _mapController.move(_route.first, 16.0);
            } else {
              _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
            }
          }
        });
      }
    }
  }

  void _togglePlayback() {
    if (_telemetry.isEmpty) return;
    setState(() {
      _isPlaying = !_isPlaying;
    });
    if (_isPlaying) {
      if (_currentIndex >= _telemetry.length - 1) {
        _currentIndex = 0;
      }
      _playLoop();
    }
  }

  Future<void> _playLoop() async {
    while (_isPlaying && _currentIndex < _telemetry.length - 1) {
      // In a real app we'd interpolate smoothly based on timestamp differences,
      // but to keep it simple and responsive we'll just step through points.
      // We can step faster than real-time to watch a long trip quickly.
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted || !_isPlaying) break;
      
      setState(() {
        _currentIndex++;
        // Optional: Follow the marker during playback
        // _mapController.move(_route[_currentIndex], _mapController.camera.zoom);
      });
    }
    if (_currentIndex >= _telemetry.length - 1) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  void dispose() {
    _isPlaying = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
      );
    }

    if (_telemetry.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: const Color(0xFF1E1E1E), title: const Text('Playback')),
        body: const Center(child: Text('No telemetry data for this trip.', style: TextStyle(color: Colors.grey))),
      );
    }

    final currentData = _telemetry[_currentIndex];
    final currentPos = _route[_currentIndex];
    final timestamp = DateTime.fromMillisecondsSinceEpoch(currentData['timestamp'] as int);

    final speedUnitStr = widget.isMph ? 'mph' : 'km/h';
    final rawGpsSpeed = currentData['gpsSpeed'] as double;
    final rawBoardSpeed = currentData['boardSpeed'] as double;

    final gpsSpeedDisplay = widget.isMph ? (rawGpsSpeed / 1.60934) : rawGpsSpeed;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Trip Playback', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _route.isNotEmpty ? _route.first : const LatLng(0, 0),
              initialZoom: 16,
            ),
            children: [
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  1.5, 0, 0, 0, 15,
                  0, 1.5, 0, 0, 15,
                  0, 0, 1.5, 0, 15,
                  0, 0, 0, 1, 0,
                ]),
                child: TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _route,
                    strokeWidth: 4.0,
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                  ),
                  Polyline(
                    points: _route.sublist(0, _currentIndex + 1),
                    strokeWidth: 4.0,
                    color: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: currentPos,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF8B5CF6), width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.8),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Playback controls (Bottom)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              decoration: const BoxDecoration(
                color: Color(0xDD1E1E1E),
                border: Border(top: BorderSide(color: Color(0xFF333333))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatColumn('Time', DateFormat('h:mm:ss a').format(timestamp)),
                      _StatColumn('GPS Speed', '${gpsSpeedDisplay.toStringAsFixed(1)} $speedUnitStr'),
                      _StatColumn('Board Speed', '${rawBoardSpeed.toStringAsFixed(1)} $speedUnitStr'),
                      _StatColumn('Battery', '${currentData['battery']}%'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: const Color(0xFF8B5CF6), size: 32),
                        onPressed: _togglePlayback,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: const Color(0xFF8B5CF6),
                            inactiveTrackColor: const Color(0xFF333333),
                            thumbColor: Colors.white,
                            overlayColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: _currentIndex.toDouble(),
                            min: 0,
                            max: (_telemetry.length - 1).toDouble(),
                            onChanged: (val) {
                              setState(() {
                                _currentIndex = val.toInt();
                                _isPlaying = false;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w300)),
      ],
    );
  }
}
