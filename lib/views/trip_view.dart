import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../ble/esk8os_ble.dart';
import '../pages/trip_history_page.dart';
import '../services/trip_recorder.dart';

/// Live ride map + trip controls. Recording itself lives in [TripRecorder]
/// (app-level singleton) so it survives page swipes / screen-off / backgrounding;
/// this view just observes the recorder and drives start/stop.
class TripView extends StatefulWidget {
  final Esk8Device dev;
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const TripView({
    super.key,
    required this.dev,
    required this.telemetry,
    required this.settings,
  });

  @override
  State<TripView> createState() => _TripViewState();
}

class _TripViewState extends State<TripView> {
  final MapController _mapController = MapController();
  final TripRecorder _rec = TripRecorder.instance;

  bool _locationReady = false;
  bool _followMode = true;
  double _currentZoom = 16.0;
  bool _showComparison = false;
  LatLng? _initialCenter;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onRec);
    _initLocation();
  }

  @override
  void dispose() {
    _rec.removeListener(_onRec);
    // NB: do NOT stop the recorder here — recording must outlive this widget.
    super.dispose();
  }

  /// Recorder ticked (new GPS fix / start / stop): follow the camera and refresh.
  void _onRec() {
    if (!mounted) return;
    if (_followMode && _rec.isRecording && _rec.currentPosition != null) {
      _mapController.move(_rec.currentPosition!, _currentZoom);
    }
    setState(() {});
  }

  /// Center the map on the user at load (only matters before a trip starts).
  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _initialCenter = latLng;
          _locationReady = true;
        });
        _mapController.move(latLng, _currentZoom);
      }
    } catch (_) {
      // Location unavailable — map stays on default center
    }
  }

  void _recenter() {
    final p = _rec.currentPosition ?? _initialCenter;
    if (p != null) {
      _mapController.move(p, _currentZoom);
      setState(() => _followMode = true);
    }
  }

  void _zoomIn() {
    _currentZoom = (_currentZoom + 1).clamp(3.0, 19.0);
    _mapController.move(_mapController.camera.center, _currentZoom);
  }

  void _zoomOut() {
    _currentZoom = (_currentZoom - 1).clamp(3.0, 19.0);
    _mapController.move(_mapController.camera.center, _currentZoom);
  }

  Future<void> _toggleTracking() async {
    if (_rec.isRecording) {
      await _rec.stop();
    } else {
      final ok = await _rec.start(widget.dev);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Location permission/service required to record'),
        ));
        return;
      }
      if (_rec.currentPosition != null) {
        _mapController.move(_rec.currentPosition!, _currentZoom);
        setState(() => _followMode = true);
      }
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = widget.telemetry;
    final settings = widget.settings;

    if (telemetry == null) {
      return const Center(child: Text('Waiting for telemetry…', style: TextStyle(color: Colors.white)));
    }

    final isMph = settings?.mph == true;
    final unitStr = isMph ? 'MI' : 'KM';
    final speedUnitStr = isMph ? 'MPH' : 'KM/H';

    final isTracking = _rec.isRecording;
    final route = _rec.route;
    final pos = _rec.currentPosition ?? _initialCenter;

    // ── GPS DISPLAY STATS ──
    final gpsTripDistDisplay = isMph ? (_rec.gpsDistanceM / 1609.34) : (_rec.gpsDistanceM / 1000.0);
    final gpsMaxSpeedDisplay = isMph ? (_rec.gpsMaxSpeedKmh / 1.60934) : _rec.gpsMaxSpeedKmh;
    final gpsCurrentSpeedDisplay = isMph ? (_rec.gpsSpeedKmh / 1.60934) : _rec.gpsSpeedKmh;

    // ── BOARD DISPLAY STATS ── (already unit-correct from firmware)
    final boardTripDist = isTracking ? (telemetry.range - _rec.boardStartRange) : telemetry.range;
    final boardMaxSpeed = isTracking ? _rec.boardMaxSpeed : telemetry.maxSpeed;
    final elapsed = _rec.elapsed;

    return Stack(
      children: [
        // Map Layer
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: pos ?? const LatLng(37.7749, -122.4194),
            initialZoom: _currentZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
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
            if (route.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route,
                    strokeWidth: 4.0,
                    color: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
            if (pos != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: pos,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                            blurRadius: 8,
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

        // Top-left: GPS status + history
        Positioned(
          top: 48,
          left: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xDD1E1E1E),
                  border: Border.all(color: const Color(0xFF333333)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.gps_fixed,
                      size: 14,
                      color: (_locationReady || isTracking) ? const Color(0xFF8B5CF6) : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (_locationReady || isTracking) ? 'GPS LOCKED' : 'ACQUIRING GPS…',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: (_locationReady || isTracking) ? Colors.white : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (pos != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xDD1E1E1E),
                    border: Border.all(color: const Color(0xFF333333)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripHistoryPage(isMph: isMph),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xDD1E1E1E),
                    border: Border.all(color: const Color(0xFF333333)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'HISTORY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Top-right: Stats panel
        Positioned(
          top: 48,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isTracking)
                GestureDetector(
                  onTap: () => setState(() => _showComparison = !_showComparison),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _showComparison ? const Color(0xFF8B5CF6) : const Color(0xDD1E1E1E),
                      border: Border.all(color: _showComparison ? const Color(0xFF8B5CF6) : const Color(0xFF333333)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'COMPARE GPS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: _showComparison ? Colors.white : Colors.grey,
                      ),
                    ),
                  ),
                ),
              if (isTracking) ...[
                if (_showComparison) ...[
                  _CompareStatCard(label: 'Speed ($speedUnitStr)', boardVal: telemetry.speed.toStringAsFixed(1), gpsVal: gpsCurrentSpeedDisplay.toStringAsFixed(1)),
                  const SizedBox(height: 6),
                  _CompareStatCard(label: 'Trip Dist ($unitStr)', boardVal: boardTripDist.toStringAsFixed(2), gpsVal: gpsTripDistDisplay.toStringAsFixed(2)),
                  const SizedBox(height: 6),
                  _CompareStatCard(label: 'Max Speed ($speedUnitStr)', boardVal: boardMaxSpeed.toStringAsFixed(1), gpsVal: gpsMaxSpeedDisplay.toStringAsFixed(1)),
                ] else ...[
                  _CamStatCard(label: 'Speed', value: telemetry.speed.toStringAsFixed(1), unit: speedUnitStr),
                  const SizedBox(height: 6),
                  _CamStatCard(label: 'Trip Dist', value: boardTripDist.toStringAsFixed(2), unit: unitStr),
                  const SizedBox(height: 6),
                  _CamStatCard(label: 'Max Speed', value: boardMaxSpeed.toStringAsFixed(1), unit: speedUnitStr),
                ],
                const SizedBox(height: 6),
                _CamStatCard(label: 'Elapsed', value: _formatDuration(elapsed), unit: ''),
              ] else ...[
                _CamStatCard(label: 'Board Dist', value: telemetry.range.toStringAsFixed(1), unit: unitStr),
                const SizedBox(height: 6),
                _CamStatCard(label: 'Board Max', value: telemetry.maxSpeed.toStringAsFixed(1), unit: speedUnitStr),
              ],
            ],
          ),
        ),

        // Recording banner (top center)
        if (isTracking)
          Positioned(
            top: 48,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '● RECORDING',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),

        // Map controls (bottom left)
        Positioned(
          bottom: 48,
          left: 16,
          child: Column(
            children: [
              _MapButton(icon: Icons.add, onTap: _zoomIn),
              const SizedBox(height: 8),
              _MapButton(icon: Icons.remove, onTap: _zoomOut),
              const SizedBox(height: 16),
              _MapButton(
                icon: Icons.my_location,
                onTap: _recenter,
                highlighted: !_followMode,
              ),
            ],
          ),
        ),

        // FAB — Start/Stop Trip (bottom right)
        Positioned(
          bottom: 48,
          right: 16,
          child: FloatingActionButton.extended(
            backgroundColor: isTracking ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
            onPressed: _toggleTracking,
            icon: Icon(isTracking ? Icons.stop : Icons.play_arrow, color: Colors.white),
            label: Text(
              isTracking ? 'STOP' : 'START TRIP',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  const _MapButton({required this.icon, required this.onTap, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xDD1E1E1E),
          border: Border.all(
            color: highlighted ? const Color(0xFF8B5CF6) : const Color(0xFF333333),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: highlighted ? const Color(0xFF8B5CF6) : Colors.white, size: 20),
      ),
    );
  }
}

class _CamStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _CamStatCard({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: const Color(0xDD1E1E1E),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.bebasNeue(
                  fontSize: 24,
                  fontWeight: FontWeight.normal,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CompareStatCard extends StatelessWidget {
  final String label;
  final String boardVal;
  final String gpsVal;

  const _CompareStatCard({required this.label, required this.boardVal, required this.gpsVal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: const Color(0xDD1E1E1E),
        border: Border.all(color: const Color(0xFF8B5CF6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(boardVal, style: GoogleFonts.bebasNeue(fontSize: 22, fontWeight: FontWeight.normal, color: Colors.white, letterSpacing: 1.5)),
                  const Text('BOARD', style: TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 24, color: const Color(0xFF333333)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(gpsVal, style: GoogleFonts.bebasNeue(fontSize: 22, fontWeight: FontWeight.normal, color: const Color(0xFF8B5CF6), letterSpacing: 1.5)),
                  const Text('GPS', style: TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
