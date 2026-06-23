import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../database/trip_database.dart';
import '../services/trip_share.dart';
import '../widgets/esk8_theme.dart';

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
  bool _showGraphs = false;

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

  /// Per-metric charts across the whole trip, with a marker at the scrubber.
  Widget _buildGraphs() {
    final isMph = widget.isMph;
    final spdUnit = isMph ? 'mph' : 'km/h';
    final climbUnit = isMph ? 'ft' : 'm';
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 190), // room for scrubber
      children: [
        _metricChart('Speed', spdUnit, Esk8Theme.accent, (r) => (r['boardSpeed'] as num).toDouble()),
        _metricChart('Elevation', climbUnit, const Color(0xFF4FC3F7),
            (r) => ((r['altitude'] as num?)?.toDouble() ?? 0) * (isMph ? 3.28084 : 1)),
        _metricChart('Power', 'W', const Color(0xFF66BB6A), (r) => (r['watts'] as num).toDouble()),
        _metricChart('Voltage', 'V', Esk8Theme.yellow, (r) => (r['voltage'] as num).toDouble()),
        _metricChart('Battery', '%', const Color(0xFFEF5350), (r) => (r['battery'] as num).toDouble()),
      ],
    );
  }

  Widget _metricChart(String label, String unit, Color color, double Function(Map<String, dynamic>) valueOf) {
    final vals = [for (final r in _telemetry) valueOf(r)];
    final spots = [for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i])];
    double minY = vals.reduce(min), maxY = vals.reduce(max);
    if (maxY - minY < 1) maxY = minY + 1;
    final pad = (maxY - minY) * 0.1;
    final cur = vals[_currentIndex.clamp(0, vals.length - 1)];
    return Container(
      height: 170,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: Esk8Theme.panelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label.toUpperCase(), style: Esk8Theme.labelStyle),
              Text('${cur.toStringAsFixed(1)} $unit', style: Esk8Theme.number(20, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (vals.length - 1).toDouble().clamp(1, double.infinity),
              minY: minY - pad,
              maxY: maxY + pad,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
                ),
              ],
              extraLinesData: ExtraLinesData(
                verticalLines: [VerticalLine(x: _currentIndex.toDouble(), color: Colors.white54, strokeWidth: 1)],
              ),
            )),
          ),
        ],
      ),
    );
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
        actions: [
          IconButton(
            icon: Icon(_showGraphs ? Icons.map : Icons.show_chart, color: const Color(0xFFB950D7)),
            tooltip: _showGraphs ? 'Map' : 'Graphs',
            onPressed: () => setState(() => _showGraphs = !_showGraphs),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share, color: Color(0xFFB950D7)),
            tooltip: 'Share trip card',
            onPressed: () => TripShare.shareSummary(context, widget.tripData, widget.isMph),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_showGraphs) _buildGraphs() else FlutterMap(
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
