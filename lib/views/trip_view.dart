import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../ble/esk8os_ble.dart';
import '../database/trip_database.dart';
import '../pages/trip_history_page.dart';

class TripView extends StatefulWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const TripView({super.key, required this.telemetry, required this.settings});

  @override
  State<TripView> createState() => _TripViewState();
}

class _TripViewState extends State<TripView> {
  final MapController _mapController = MapController();
  
  bool _isTracking = false;
  bool _locationReady = false;
  bool _followMode = true;
  double _currentZoom = 16.0;
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _telemetryTimer;
  final List<LatLng> _route = [];

  int? _currentTripId;

  // Comparison toggle
  bool _showComparison = false;

  // Trip stats (GPS)
  DateTime? _tripStartTime;
  double _gpsTripDistanceM = 0.0; // meters
  double _gpsMaxSpeed = 0.0; // km/h
  double _currentGpsSpeed = 0.0; // km/h

  // Trip stats (Board)
  double _boardStartRange = 0.0;
  double _boardTripMaxSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void didUpdateWidget(TripView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Track board max speed while a trip is active
    if (_isTracking && widget.telemetry != null) {
      if (widget.telemetry!.speed > _boardTripMaxSpeed) {
        // Schedule state update to avoid doing it during build phase if this somehow triggered it
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _boardTripMaxSpeed = widget.telemetry!.speed);
        });
      }
    }
  }

  /// Grab current location on load so the map centers on the user immediately
  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _currentPosition = latLng;
          _locationReady = true;
        });
        _mapController.move(latLng, _currentZoom);
      }
    } catch (_) {
      // Location unavailable — map stays on default center
    }
  }

  void _recenter() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _currentZoom);
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
    if (_isTracking) {
      // Stop tracking
      await _positionStream?.cancel();
      _telemetryTimer?.cancel();
      
      // Save trip end data
      if (_currentTripId != null) {
        await TripDatabase.instance.updateTrip(
          _currentTripId!, 
          DateTime.now().millisecondsSinceEpoch, 
          _gpsTripDistanceM, 
          _gpsMaxSpeed, 
          _boardTripMaxSpeed,
        );
      }

      setState(() {
        _isTracking = false;
        _currentTripId = null;
      });
    } else {
      // Request permissions if needed
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      // Set initial position
      final pos = await Geolocator.getCurrentPosition();
      final initialLatLng = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _route.clear();
        _route.add(initialLatLng);
        _currentPosition = initialLatLng;
        _isTracking = true;
        _followMode = true;
        
        // Reset GPS stats
        _tripStartTime = DateTime.now();
        _gpsTripDistanceM = 0.0;
        _gpsMaxSpeed = 0.0;
        _currentGpsSpeed = 0.0;

        // Capture Board starting stats
        _boardStartRange = widget.telemetry?.range ?? 0.0;
        _boardTripMaxSpeed = widget.telemetry?.speed ?? 0.0;
      });
      _mapController.move(initialLatLng, _currentZoom);

      // Create Trip in DB
      _currentTripId = await TripDatabase.instance.createTrip(_tripStartTime!.millisecondsSinceEpoch);

      // Start telemetry timer (Logs every 1 second regardless of movement)
      _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_currentTripId != null && _currentPosition != null && mounted) {
          final t = widget.telemetry;
          TripDatabase.instance.insertTelemetry({
            'tripId': _currentTripId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'lat': _currentPosition!.latitude,
            'lng': _currentPosition!.longitude,
            'gpsSpeed': _currentGpsSpeed,
            'boardSpeed': t?.speed ?? 0.0,
            'battery': t?.battery ?? 0,
            'voltage': t?.volts ?? 0.0,
            'watts': t?.watts ?? 0,
          });
        }
      });

      // Start listening
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((Position position) {
        final latLng = LatLng(position.latitude, position.longitude);
        final speedKmh = position.speed * 3.6; // m/s -> km/h

        // Calculate distance from last point
        if (_route.isNotEmpty) {
          final dist = const Distance().as(LengthUnit.Meter, _route.last, latLng);
          _gpsTripDistanceM += dist;
        }

        setState(() {
          _route.add(latLng);
          _currentPosition = latLng;
          _currentGpsSpeed = speedKmh;
          if (speedKmh > _gpsMaxSpeed) _gpsMaxSpeed = speedKmh;
        });

        if (_followMode) {
          _mapController.move(latLng, _currentZoom);
        }
      });
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
  void dispose() {
    _positionStream?.cancel();
    _telemetryTimer?.cancel();
    super.dispose();
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

    // ── GPS DISPLAY STATS ──
    final gpsTripDistDisplay = isMph ? (_gpsTripDistanceM / 1609.34) : (_gpsTripDistanceM / 1000.0);
    final gpsMaxSpeedDisplay = isMph ? (_gpsMaxSpeed / 1.60934) : _gpsMaxSpeed;
    final gpsCurrentSpeedDisplay = isMph ? (_currentGpsSpeed / 1.60934) : _currentGpsSpeed;

    // ── BOARD DISPLAY STATS ──
    final boardTripDist = _isTracking ? (telemetry.range - _boardStartRange) : telemetry.range;
    final boardMaxSpeed = _isTracking ? _boardTripMaxSpeed : telemetry.maxSpeed;
    
    // Display stats (We don't need to convert board stats as they are already in the correct unit from firmware/telemetry class, except firmware might send kmh and telemetry class converts. Assuming telemetry class properties are already unit-aware based on how we use them in DashView).
    // Actually, looking at DashView, `telemetry.speed` is already in the right units? Wait, telemetry usually sends exact units. 
    // Wait! Let's ensure board stats match the GPS conversion if needed, but since board speed is directly displayed elsewhere without conversion, we use it directly.

    final elapsed = _tripStartTime != null ? DateTime.now().difference(_tripStartTime!) : Duration.zero;

    return Stack(
      children: [
        // Map Layer
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPosition ?? const LatLng(37.7749, -122.4194),
            initialZoom: _currentZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                // Boost lightness and contrast matrix
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
            // Route polyline
            if (_route.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _route,
                    strokeWidth: 4.0,
                    color: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
            // Current position marker
            if (_currentPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition!,
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

        // Top-left: GPS status
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
                      color: _locationReady ? const Color(0xFF8B5CF6) : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _locationReady ? 'GPS LOCKED' : 'ACQUIRING GPS…',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: _locationReady ? Colors.white : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (_currentPosition != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xDD1E1E1E),
                    border: Border.all(color: const Color(0xFF333333)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}',
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
                      builder: (_) => TripHistoryPage(isMph: settings?.mph == true),
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
              // Compare Toggle
              if (_isTracking)
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

              if (_isTracking) ...[
                if (_showComparison) ...[
                  // Comparison Mode
                  _CompareStatCard(label: 'Speed ($speedUnitStr)', boardVal: telemetry.speed.toStringAsFixed(1), gpsVal: gpsCurrentSpeedDisplay.toStringAsFixed(1)),
                  const SizedBox(height: 6),
                  _CompareStatCard(label: 'Trip Dist ($unitStr)', boardVal: boardTripDist.toStringAsFixed(2), gpsVal: gpsTripDistDisplay.toStringAsFixed(2)),
                  const SizedBox(height: 6),
                  _CompareStatCard(label: 'Max Speed ($speedUnitStr)', boardVal: boardMaxSpeed.toStringAsFixed(1), gpsVal: gpsMaxSpeedDisplay.toStringAsFixed(1)),
                ] else ...[
                  // Default Board Mode
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
        if (_isTracking)
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
            backgroundColor: _isTracking ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
            onPressed: _toggleTracking,
            icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow, color: Colors.white),
            label: Text(
              _isTracking ? 'STOP' : 'START TRIP',
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
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
