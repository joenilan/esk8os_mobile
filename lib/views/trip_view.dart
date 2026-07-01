import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // Ticker for smooth map rotation
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../ble/esk8os_ble.dart';
import '../pages/trip_history_page.dart';
import '../services/app_prefs.dart';
import '../services/trip_recorder.dart';
import '../widgets/esk8_theme.dart';

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

class _TripViewState extends State<TripView>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final TripRecorder _rec = TripRecorder.instance;

  bool _locationReady = false;
  bool _statsExpanded = false; // collapsed = speed only; tap to show all stats
  bool _followMode = true;
  double _currentZoom = 16.0;
  // Persisted across page swipes / restarts (see AppPrefs).
  bool _headingUp = AppPrefs.mapHeadingUp;
  bool _mapLight = AppPrefs.mapLight;
  LatLng? _initialCenter;

  // Smooth marker: GPS fixes arrive ~every few metres, so we tween the marker
  // (and the followed camera) between fixes instead of snapping/teleporting.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(_onAnimTick);
  LatLng _mStart = const LatLng(0, 0), _mEnd = const LatLng(0, 0);
  LatLng? _smoothPos; // interpolated marker position currently displayed
  DateTime? _lastFixAt; // arrival time of the previous fix — paces the glide

  // Heading-up rotation: sensor handlers just set _targetHeading; a Ticker eases
  // the actually-rendered map rotation (_displayHeading) toward it every frame so
  // the map glides instead of snapping in discrete steps (the old jitter).
  StreamSubscription<CompassEvent>? _compassSub;
  double _targetHeading = 0; // desired heading (low-passed sensor input)
  double _displayHeading = 0; // currently-rendered map rotation
  Ticker? _rotTicker;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onRec);
    _compassSub = FlutterCompass.events?.listen(_onCompass);
    _rotTicker = createTicker(_onRotTick);
    if (_headingUp) _rotTicker!.start();
    _initLocation();
  }

  @override
  void dispose() {
    _anim.dispose();
    _rotTicker?.dispose();
    _compassSub?.cancel();
    _rec.removeListener(_onRec);
    // NB: do NOT stop the recorder here — recording must outlive this widget.
    super.dispose();
  }

  /// Each frame: ease the rendered map rotation toward the target heading so the
  /// map turns smoothly. Idles (no redraw) once it's essentially aligned.
  void _onRotTick(Duration _) {
    if (!_headingUp || !mounted) return;
    if (_angleDiff(_targetHeading, _displayHeading).abs() < 0.25) return;
    _displayHeading = _smoothAngle(_displayHeading, _targetHeading, 0.18);
    _mapController.rotate(-_displayHeading);
  }

  // Shortest signed difference a-b in [-180,180]; smooth a circular heading.
  static double _angleDiff(double a, double b) {
    var d = (a - b) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  static double _smoothAngle(double cur, double target, double alpha) =>
      (cur + _angleDiff(target, cur) * alpha + 360) % 360;

  void _onCompass(CompassEvent e) {
    // Compass drives rotation only when essentially stopped; once moving, GPS
    // course (in _onRec) takes over — it's unambiguous, unlike a magnetometer.
    // Just set the TARGET (low-passed to reject mag spikes); the ticker eases the
    // map toward it smoothly.
    if (!_headingUp || !mounted || _rec.gpsSpeedKmh > 3) return;
    final h = e.heading;
    if (h == null) return;
    _targetHeading = _smoothAngle(_targetHeading, h, 0.3);
  }

  /// Glide the marker from its current displayed spot to the new GPS fix, paced to
  /// the MEASURED gap between fixes. A fixed-duration tween teleports: when fixes
  /// outrun it (fast riding, distanceFilter 3 m → a fix every ~0.3 s) the marker
  /// rides a constant lag that snaps forward whenever fixes pause (a stop, tree
  /// cover, a GPS gap). Tweening over ~the last interval makes the marker arrive
  /// about when the next fix lands, so there's no accumulated lag left to snap.
  void _animateMarkerTo(LatLng dest) {
    // Ignore repeat notifications that don't move the target (pause/resume/stop):
    // re-tweening to the same point would corrupt the interval pacing below.
    if (dest.latitude == _mEnd.latitude && dest.longitude == _mEnd.longitude) {
      return;
    }
    final now = DateTime.now();
    final gapMs = _lastFixAt == null
        ? 900
        : now.difference(_lastFixAt!).inMilliseconds;
    _lastFixAt = now;
    // Clamp: the floor stops very frequent fixes from a frantic glide; the ceiling
    // keeps a post-gap catch-up brisk (not a slow multi-second crawl) yet still a
    // glide rather than a teleport.
    _anim.duration = Duration(milliseconds: gapMs.clamp(250, 1500));
    _mStart = _smoothPos ?? dest;
    _mEnd = dest;
    _anim.forward(from: 0);
  }

  void _onAnimTick() {
    final t = Curves.linear.transform(
      _anim.value,
    ); // steady glide between fixes
    final lat = _mStart.latitude + (_mEnd.latitude - _mStart.latitude) * t;
    final lng = _mStart.longitude + (_mEnd.longitude - _mStart.longitude) * t;
    _smoothPos = LatLng(lat, lng);
    if (_followMode) _mapController.move(_smoothPos!, _currentZoom);
    setState(() {}); // redraw marker at the interpolated position
  }

  void _toggleHeadingUp() {
    setState(() => _headingUp = !_headingUp);
    AppPrefs.mapHeadingUp = _headingUp;
    if (_headingUp) {
      _rotTicker?.start();
    } else {
      _rotTicker?.stop();
      _displayHeading = 0;
      _targetHeading = 0;
      _mapController.rotate(0); // back to north-up
    }
  }

  void _toggleMapLight() {
    setState(() => _mapLight = !_mapLight);
    AppPrefs.mapLight = _mapLight;
  }

  // Map-control chrome flips with the basemap: light controls over the light map,
  // dark controls over the dark map. Accent stays for highlights on both.
  Color get _ctlBg => _mapLight ? const Color(0xF2FAFAFA) : const Color(0xDD1E1E1E);
  Color get _ctlBorder =>
      _mapLight ? const Color(0xFFBEBEC6) : const Color(0xFF333333);
  Color get _ctlFg => _mapLight ? const Color(0xFF18181C) : Colors.white;
  Color get _ctlDim => _mapLight ? const Color(0xFF70707A) : Colors.grey;

  /// Recorder ticked (new GPS fix / start / stop): glide the marker + refresh.
  void _onRec() {
    if (!mounted) return;
    final fix = _rec.currentPosition;
    if (fix != null) {
      _animateMarkerTo(fix); // smooth glide (camera follows in _onAnimTick)
    }
    // While moving, GPS course (direction of travel) drives heading-up — far more
    // reliable than the magnetometer, and orientation-independent. Set the target;
    // the ticker eases the map toward it.
    if (_headingUp && _rec.gpsSpeedKmh > 3) {
      _targetHeading = _rec.heading;
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
    final p = _smoothPos ?? _rec.currentPosition ?? _initialCenter;
    if (p != null) {
      _mapController.move(p, _currentZoom);
      setState(() => _followMode = true);
    }
  }

  Future<void> _toggleTracking() async {
    if (_rec.isRecording) {
      await _rec.stop();
    } else {
      final ok = await _rec.start(
        widget.dev,
        isMph: widget.settings?.mph ?? true,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission/service required to record'),
          ),
        );
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

  Widget _miniStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Esk8Theme.number(17)),
      Text(
        label,
        style: TextStyle(
          fontSize: 8,
          color: Esk8Theme.dim,
          letterSpacing: 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  Widget _miniRow(String l1, String v1, String l2, String v2) => Row(
    children: [
      Expanded(child: _miniStat(l1, v1)),
      Expanded(child: _miniStat(l2, v2)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final telemetry = widget.telemetry;
    final settings = widget.settings;

    if (telemetry == null) {
      return const Center(
        child: Text(
          'Waiting for telemetry…',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final isMph = settings?.mph == true;
    final unitStr = isMph ? 'MI' : 'KM';
    final speedUnitStr = isMph ? 'MPH' : 'KM/H';

    final isTracking = _rec.isRecording;
    final route = _rec.route;
    final pos = _rec.currentPosition ?? _initialCenter;
    // Draw the traveled line ENDING at the smoothed marker (not the raw latest
    // fix), so the line tip and the marker glide together instead of the line
    // snapping ahead and the marker visibly chasing it.
    final linePoints = (_smoothPos != null && route.length >= 2)
        ? [...route.sublist(0, route.length - 1), _smoothPos!]
        : route;

    // ── TRIP DISTANCE + TIME come from the BOARD (canonical, matches the board
    // screen): wheel distance and moving-time, independent of the phone. GPS still
    // drives MAX/AVG/MOVE/CLIMB/route below. telemetry.trip is already in the
    // board's display unit; tmov is moving seconds.
    final boardTripDisplay = telemetry.trip;
    final boardMovingTime = Duration(seconds: telemetry.tripMovingSeconds);
    // ── TRIP STATS (GPS-measured, per recording) — all 0 until you start ──
    // GPS trip distance is shown as a compare against the board's wheel distance.
    final gpsTripDistDisplay = isMph
        ? (_rec.gpsDistanceM / 1609.34)
        : (_rec.gpsDistanceM / 1000.0);
    final gpsMaxSpeedDisplay = isMph
        ? (_rec.gpsMaxSpeedKmh / 1.60934)
        : _rec.gpsMaxSpeedKmh;
    final elapsed = _rec.elapsed;
    final gpsAvgKmh = elapsed.inSeconds > 0
        ? _rec.gpsDistanceM * 3.6 / elapsed.inSeconds
        : 0.0;
    final gpsAvgDisplay = isMph ? gpsAvgKmh / 1.60934 : gpsAvgKmh;
    final gpsMovingAvgDisplay = isMph
        ? _rec.gpsMovingAvgKmh / 1.60934
        : _rec.gpsMovingAvgKmh;
    final climbDisplay = isMph ? _rec.elevGainM * 3.28084 : _rec.elevGainM;
    final climbUnit = isMph ? 'FT' : 'M';

    return Stack(
      children: [
        // Map Layer
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: pos ?? const LatLng(37.7749, -122.4194),
            initialZoom: _currentZoom,
            // Free look-around: pan, pinch-zoom and rotate are all enabled now
            // (page navigation moves to the on-map prev/next buttons).
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.rotate |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.flingAnimation,
            ),
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture) {
                _currentZoom = camera.zoom;
                if (_followMode) setState(() => _followMode = false);
              }
            },
          ),
          children: [
            // Light vs dark basemap (persisted). Dark tiles get a brightness
            // bump; light tiles are used as-is.
            if (_mapLight)
              // Voyager = normal colours with readable roads/labels (light_all
              // was too washed-out).
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              )
            else
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  1.5,
                  0,
                  0,
                  0,
                  15,
                  0,
                  1.5,
                  0,
                  0,
                  15,
                  0,
                  0,
                  1.5,
                  0,
                  15,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
              ),
            if (linePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: linePoints,
                    strokeWidth: 4.0,
                    color: Esk8Theme.accent,
                  ),
                ],
              ),
            if ((_smoothPos ?? pos) != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _smoothPos ?? pos!,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Esk8Theme.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Esk8Theme.accent.withValues(alpha: 0.5),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _ctlBg,
                  border: Border.all(color: _ctlBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.gps_fixed,
                      size: 14,
                      color: (_locationReady || isTracking)
                          ? Esk8Theme.accent
                          : _ctlDim,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (_locationReady || isTracking)
                          ? 'GPS LOCKED'
                          : 'ACQUIRING GPS…',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: (_locationReady || isTracking)
                            ? _ctlFg
                            : _ctlDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (pos != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _ctlBg,
                    border: Border.all(color: _ctlBorder),
                  ),
                  child: Text(
                    '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: _ctlDim,
                      fontFamily: 'monospace',
                    ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _ctlBg,
                    border: Border.all(color: _ctlBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 14, color: _ctlFg),
                      const SizedBox(width: 6),
                      Text(
                        'HISTORY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: _ctlFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Top-right: ONE compact card. Collapsed = just speed (map stays the
        // star); tap it to expand the full trip-stats grid.
        Positioned(
          top: 48,
          right: 12,
          child: GestureDetector(
            onTap: () => setState(() => _statsExpanded = !_statsExpanded),
            child: Container(
              width: _statsExpanded ? 156 : 96,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: Esk8Theme.panelBox(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${telemetry.speed.toInt()}',
                        style: Esk8Theme.number(38),
                      ),
                      const SizedBox(width: 3),
                      Text(speedUnitStr, style: Esk8Theme.labelStyle),
                    ],
                  ),
                  Icon(
                    _statsExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Esk8Theme.dim,
                  ),
                  if (_statsExpanded) ...[
                    Divider(color: Esk8Theme.border, height: 6),
                    const SizedBox(height: 6),
                    _miniRow(
                      'TRIP $unitStr',
                      boardTripDisplay.toStringAsFixed(2),
                      'TIME',
                      _formatDuration(boardMovingTime),
                    ),
                    const SizedBox(height: 8),
                    // GPS compare (board wheel distance is canonical above; GPS may
                    // differ — different sensor). GPS TIME is wall-clock elapsed.
                    _miniRow(
                      'GPS $unitStr',
                      gpsTripDistDisplay.toStringAsFixed(2),
                      'GPS TIME',
                      _formatDuration(elapsed),
                    ),
                    const SizedBox(height: 8),
                    _miniRow(
                      'MAX',
                      gpsMaxSpeedDisplay.toStringAsFixed(1),
                      'AVG',
                      gpsAvgDisplay.toStringAsFixed(1),
                    ),
                    const SizedBox(height: 8),
                    _miniRow(
                      'MOVE',
                      gpsMovingAvgDisplay.toStringAsFixed(1),
                      'CLIMB $climbUnit',
                      climbDisplay.toStringAsFixed(0),
                    ),
                    const SizedBox(height: 8),
                    // Board-canonical efficiency + lifetime odometer.
                    _miniRow(
                      'EFF wh/${isMph ? 'mi' : 'km'}',
                      telemetry.efficiency.toStringAsFixed(1),
                      'ODO $unitStr',
                      telemetry.odometer.toStringAsFixed(1),
                    ),
                  ],
                ],
              ),
            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Esk8Theme.accent,
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
              _MapButton(
                icon: Icons.my_location,
                onTap: _recenter,
                highlighted: !_followMode,
                light: _mapLight,
              ),
              const SizedBox(height: 8),
              _MapButton(
                icon: _headingUp ? Icons.navigation : Icons.explore,
                onTap: _toggleHeadingUp,
                highlighted: _headingUp,
                light: _mapLight,
              ),
              const SizedBox(height: 8),
              _MapButton(
                icon: _mapLight ? Icons.dark_mode : Icons.light_mode,
                onTap: _toggleMapLight,
                highlighted: _mapLight,
                light: _mapLight,
              ),
            ],
          ),
        ),

        // FAB — Start/Stop (+ Pause/Resume while recording), bottom right
        Positioned(
          bottom: 48,
          right: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTracking) ...[
                FloatingActionButton(
                  heroTag: 'pause',
                  backgroundColor: const Color(0xDD1A1A1A),
                  onPressed: () => _rec.isPaused ? _rec.resume() : _rec.pause(),
                  child: Icon(
                    _rec.isPaused ? Icons.play_arrow : Icons.pause,
                    color: Esk8Theme.accent,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              FloatingActionButton.extended(
                heroTag: 'startstop',
                backgroundColor: isTracking
                    ? const Color(0xFFEF4444)
                    : Esk8Theme.accent,
                onPressed: _toggleTracking,
                icon: Icon(
                  isTracking ? Icons.stop : Icons.play_arrow,
                  color: Colors.white,
                ),
                label: Text(
                  isTracking
                      ? (_rec.isPaused ? 'PAUSED' : 'STOP')
                      : 'START TRIP',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;
  final bool light;

  const _MapButton({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    // Chrome flips with the basemap: light button over the light map, dark over dark.
    final bg = light ? const Color(0xF2FAFAFA) : const Color(0xDD1E1E1E);
    final bd = light ? const Color(0xFFBEBEC6) : const Color(0xFF333333);
    final fg = light ? const Color(0xFF18181C) : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: highlighted ? Esk8Theme.accent : bd),
        ),
        child: Icon(
          icon,
          color: highlighted ? Esk8Theme.accent : fg,
          size: 20,
        ),
      ),
    );
  }
}
