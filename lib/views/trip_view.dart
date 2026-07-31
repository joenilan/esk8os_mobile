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
import '../widgets/confirm_dialog.dart';
import '../widgets/esk8_theme.dart';

/// Live ride map + trip controls. Recording itself lives in [TripRecorder]
/// (app-level singleton) so it survives page swipes / screen-off / backgrounding;
/// this view just observes the recorder and drives start/stop.
class TripView extends StatefulWidget {
  final Esk8Device? dev;
  final Telemetry? telemetry;
  final BoardSettings? settings;
  final bool? isMphOverride;

  const TripView({
    super.key,
    this.dev,
    required this.telemetry,
    required this.settings,
    this.isMphOverride,
  });

  @override
  State<TripView> createState() => _TripViewState();
}

class _TripViewState extends State<TripView>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const Telemetry _phoneOnlyTelemetry = Telemetry(
    live: false,
    vescConnected: false,
    batteryLive: false,
    batterySource: 'none',
    speed: 0,
    battery: 0,
    volts: 0,
    watts: 0,
    motorTempC: 0,
    escTempC: 0,
    range: 0,
    maxSpeed: 0,
    wattHours: 0,
  );

  final MapController _mapController = MapController();
  final TripRecorder _rec = TripRecorder.instance;

  bool _locationReady = false;
  bool _followMode = true;
  double _currentZoom = 16.0;
  // Persisted across page swipes / restarts (see AppPrefs).
  bool _headingUp = AppPrefs.mapHeadingUp;
  bool _mapLight = AppPrefs.mapLight;
  LatLng? _initialCenter;

  // Smooth marker: GPS fixes arrive ~every few metres, so we tween the marker
  // (and the followed camera) between fixes instead of snapping/teleporting.
  // The interpolated position is a ValueNotifier so each animation frame only
  // rebuilds the marker layer — a page-level setState at ~60 fps rebuilt the
  // whole map (full-route polyline included), which janked on long rides.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(_onAnimTick);
  LatLng _mStart = const LatLng(0, 0), _mEnd = const LatLng(0, 0);
  final ValueNotifier<LatLng?> _smoothPos = ValueNotifier(null);
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
    _smoothPos.dispose();
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
    _mStart = _smoothPos.value ?? dest;
    _mEnd = dest;
    _anim.forward(from: 0);
  }

  void _onAnimTick() {
    final t = Curves.linear.transform(
      _anim.value,
    ); // steady glide between fixes
    final lat = _mStart.latitude + (_mEnd.latitude - _mStart.latitude) * t;
    final lng = _mStart.longitude + (_mEnd.longitude - _mStart.longitude) * t;
    final p = LatLng(lat, lng);
    _smoothPos.value = p; // rebuilds only the marker layer (no page setState)
    if (_followMode) _mapController.move(p, _currentZoom);
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
  Color get _ctlBg =>
      _mapLight ? const Color(0xF2FAFAFA) : const Color(0xDD1E1E1E);
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

      // Seed from the last known fix first — it's instant, so the map opens
      // roughly on the rider instead of a default city that then jumps when the
      // live fix lands.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && _initialCenter == null) {
        setState(() => _initialCenter = LatLng(last.latitude, last.longitude));
      }

      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        final hadCenter = _initialCenter != null;
        setState(() {
          _initialCenter = latLng;
          _locationReady = true;
        });
        // Only recenter if we didn't already open on the rider (cold start) or
        // we're actively following — avoids a visible "jump" on a fresh fix.
        if (!hadCenter || _followMode) {
          _mapController.move(latLng, _currentZoom);
        }
      }
    } catch (_) {
      // Location unavailable — map stays on default center
    }
  }

  void _recenter() {
    final p = _smoothPos.value ?? _rec.currentPosition ?? _initialCenter;
    if (p != null) {
      _mapController.move(p, _currentZoom);
      setState(() => _followMode = true);
    }
  }

  Future<void> _toggleTracking() async {
    if (_rec.isBusy) return;
    if (_rec.isRecording) {
      final stop = await confirmAction(
        context,
        title: 'Finish this ride?',
        message:
            'EVEE will save the final route and stats, then stop GPS recording. '
            'Use Pause if you plan to continue this ride.',
        confirmLabel: 'Finish ride',
      );
      if (!stop) return;
      await _rec.stop();
    } else {
      final ok = await _rec.start(
        widget.dev,
        isMph: widget.settings?.mph ?? true,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _rec.lastError ??
                  'Location permission/service required to record',
            ),
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

  Future<void> _showRideDetails({
    required bool hasBoard,
    required Telemetry telemetry,
    required bool isMph,
    required LatLng? position,
    required String gpsStatus,
    required String speedSource,
    required double boardTripDisplay,
    required Duration boardMovingTime,
    required double boardMaxSpeedDisplay,
    required double boardAvgDisplay,
    required double boardMovingAvgDisplay,
    required double gpsSpeedDisplay,
    required double gpsTripDisplay,
    required double gpsMaxSpeedDisplay,
    required double gpsAvgDisplay,
    required double gpsMovingAvgDisplay,
    required Duration phoneElapsed,
    required double climbDisplay,
    required String climbUnit,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _RideDetailsSheet(
        hasBoard: hasBoard,
        telemetry: telemetry,
        isMph: isMph,
        position: position,
        gpsStatus: gpsStatus,
        speedSource: speedSource,
        storageError: _rec.storageError,
        boardTripDisplay: boardTripDisplay,
        boardMovingTime: boardMovingTime,
        boardMaxSpeedDisplay: boardMaxSpeedDisplay,
        boardAvgDisplay: boardAvgDisplay,
        boardMovingAvgDisplay: boardMovingAvgDisplay,
        gpsSpeedDisplay: gpsSpeedDisplay,
        gpsTripDisplay: gpsTripDisplay,
        gpsMaxSpeedDisplay: gpsMaxSpeedDisplay,
        gpsAvgDisplay: gpsAvgDisplay,
        gpsMovingAvgDisplay: gpsMovingAvgDisplay,
        phoneElapsed: phoneElapsed,
        climbDisplay: climbDisplay,
        climbUnit: climbUnit,
        onHistory: () {
          Navigator.pop(sheetContext);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TripHistoryPage(isMph: isMph)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isTracking = _rec.isRecording;
    // A recording's source is fixed at Start. Connecting a vehicle midway
    // through a phone ride must not silently relabel that ride as board-backed.
    final hasBoard = isTracking ? _rec.recordingUsesBoard : widget.dev != null;
    final telemetry = hasBoard
        ? (_rec.latestTelemetry ?? widget.telemetry ?? _phoneOnlyTelemetry)
        : _phoneOnlyTelemetry;
    final settings = widget.settings;
    final isMph =
        settings?.mph ??
        (hasBoard ? telemetry.mph : null) ??
        widget.isMphOverride ??
        AppPrefs.preferredMph;
    final unitStr = isMph ? 'MI' : 'KM';
    final speedUnitStr = isMph ? 'MPH' : 'KM/H';

    final recordingState = _rec.state;
    final recorderBusy = _rec.isBusy;
    final gpsDegraded = isTracking && !_rec.gpsHealthy;
    final route = _rec.route;
    final pos = _rec.currentPosition ?? _initialCenter;
    // Draw the traveled line ENDING at the smoothed marker (not the raw latest
    // fix), so the line tip and the marker glide together instead of the line
    // snapping ahead and the marker visibly chasing it. (The tip now advances
    // per GPS fix rather than per animation frame — the polyline is too heavy
    // to rebuild at 60 fps on a long ride.)
    final smoothNow = _smoothPos.value;
    final linePoints = (smoothNow != null && route.length >= 2)
        ? [...route.sublist(0, route.length - 1), smoothNow]
        : route;

    // Preserve the raw board and GPS values as separate evidence. The glance
    // card uses the recorder's monotonic fusion so a live-but-stuck/reset board
    // trip counter cannot freeze or erase the phone trip.
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
    final gpsSpeedDisplay = isMph
        ? (_rec.gpsSpeedKmh / 1.60934)
        : _rec.gpsSpeedKmh;
    final effectiveTripDisplay = isTracking
        ? (isMph ? _rec.effectiveTripKm / 1.60934 : _rec.effectiveTripKm)
        : (hasBoard ? boardTripDisplay : gpsTripDistDisplay);
    final effectiveTripSource = isTracking
        ? _rec.distanceSource
        : (hasBoard ? 'BOARD' : 'GPS');
    final effectiveMovingTime = isTracking
        ? _rec.effectiveMovingTime
        : (hasBoard ? boardMovingTime : _rec.elapsed);
    // Big speed number: the trusted source. While recording, the recorder
    // picks board-when-live / GPS-when-not; when idle, the live board feed.
    final bool boardLive = _rec.isRecording ? _rec.boardLive : telemetry.live;
    final bool gpsLive = _rec.isRecording && _rec.gpsLive;
    final double effSpeedKmh = _rec.isRecording
        ? _rec.effectiveSpeedKmh
        : ((telemetry.mph ?? true)
              ? telemetry.speed * 1.60934
              : telemetry.speed);
    final double bigSpeedDisplay = isMph ? effSpeedKmh / 1.60934 : effSpeedKmh;
    final bool speedAvailable = boardLive || gpsLive;
    final String speedSource = boardLive
        ? 'BOARD'
        : gpsLive
        ? 'GPS'
        : '--';
    final elapsed = _rec.elapsed;
    // Averages need a few seconds of elapsed time to be meaningful — dividing a
    // little distance by a ~1 s window otherwise spikes to absurd values in the
    // first moments of a ride. Hold at 0 until the window is trustworthy.
    const int avgMinSec = 5;
    final gpsAvgKmh = elapsed.inSeconds >= avgMinSec
        ? _rec.gpsDistanceM * 3.6 / elapsed.inSeconds
        : 0.0;
    final gpsAvgDisplay = isMph ? gpsAvgKmh / 1.60934 : gpsAvgKmh;
    final gpsMovingAvgDisplay = isMph
        ? _rec.gpsMovingAvgKmh / 1.60934
        : _rec.gpsMovingAvgKmh;
    final boardMaxSpeedDisplay = _rec.boardMaxSpeed;
    final elapsedHours = elapsed.inMilliseconds / 3600000.0;
    final boardMovingHours = boardMovingTime.inMilliseconds / 3600000.0;
    final boardAvgDisplay = elapsed.inSeconds >= avgMinSec && elapsedHours > 0
        ? boardTripDisplay / elapsedHours
        : 0.0;
    final boardMovingAvgDisplay = boardMovingHours > 0
        ? boardTripDisplay / boardMovingHours
        : 0.0;
    final climbDisplay = isMph ? _rec.elevGainM * 3.28084 : _rec.elevGainM;
    final climbUnit = isMph ? 'FT' : 'M';
    final gpsStatus = isTracking
        ? _rec.gpsQualityLabel
        : _locationReady
        ? 'GPS READY'
        : 'ACQUIRING GPS…';
    final recordingLabel = !_rec.storageHealthy
        ? 'STORAGE WARNING'
        : switch (recordingState) {
            TripRecordingState.starting => 'PREPARING RIDE',
            TripRecordingState.recording => 'RECORDING',
            TripRecordingState.paused => 'RIDE PAUSED',
            TripRecordingState.stopping => 'SAVING RIDE',
            TripRecordingState.error => 'RECORDER NEEDS ATTENTION',
            TripRecordingState.idle => 'READY TO RIDE',
          };
    final recordingColor = !_rec.storageHealthy
        ? Esk8Theme.danger
        : switch (recordingState) {
            TripRecordingState.recording => Esk8Theme.accent,
            TripRecordingState.paused => Esk8Theme.yellow,
            TripRecordingState.starting ||
            TripRecordingState.stopping => Esk8Theme.orange,
            TripRecordingState.error => Esk8Theme.danger,
            TripRecordingState.idle => _ctlDim,
          };

    return Stack(
      children: [
        // Map layer — build only once we have a fix (the last-known seed is
        // near-instant) so it opens ON the rider, not a default city that then
        // jumps when the live fix lands.
        if (pos != null)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: pos,
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
              // Marker rebuilds alone on each glide frame — everything above
              // (tiles, polyline) only rebuilds on page setState (per GPS fix).
              ValueListenableBuilder<LatLng?>(
                valueListenable: _smoothPos,
                builder: (_, smooth, _) => MarkerLayer(
                  markers: [
                    Marker(
                      point: smooth ?? pos,
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
              ),
              // Tile-license requirement: OSM data + CARTO basemap attribution.
              SimpleAttributionWidget(
                source: Text(
                  '© OpenStreetMap contributors · © CARTO',
                  style: TextStyle(
                    fontSize: 10,
                    color: _mapLight ? Colors.black54 : Colors.white54,
                  ),
                ),
                backgroundColor: _mapLight
                    ? const Color(0xAAFFFFFF)
                    : const Color(0xAA1E1E1E),
              ),
            ],
          )
        else
          Positioned.fill(
            child: Container(
              color: _mapLight ? const Color(0xFFE8E8EA) : Esk8Theme.scaffold,
            ),
          ),

        // One glanceable ride surface: source/state, speed, canonical board
        // distance/time, and battery. Tap for diagnostics and GPS comparison.
        Positioned(
          top: 44,
          left: 16,
          right: 16,
          child: _RideGlanceCard(
            background: _ctlBg,
            border: _ctlBorder,
            foreground: _ctlFg,
            dim: _ctlDim,
            stateLabel: recordingLabel,
            stateColor: recordingColor,
            gpsLabel: gpsStatus,
            gpsDegraded: gpsDegraded,
            speed: speedAvailable ? bigSpeedDisplay.toInt().toString() : '--',
            speedUnit: speedUnitStr,
            speedSource: speedSource,
            trip: effectiveTripDisplay.toStringAsFixed(2),
            tripUnit: unitStr,
            tripLabel: '$effectiveTripSource TRIP',
            movingTime: _formatDuration(effectiveMovingTime),
            timeLabel: effectiveTripSource == 'BOARD' ? 'MOVING' : 'GPS MOVING',
            battery: telemetry.batteryLive ? '${telemetry.battery}%' : '--',
            batterySource: hasBoard ? telemetry.batterySourceLabel : 'NO BOARD',
            onTap: () => _showRideDetails(
              hasBoard: hasBoard,
              telemetry: telemetry,
              isMph: isMph,
              position: pos,
              gpsStatus: gpsStatus,
              speedSource: speedSource,
              boardTripDisplay: boardTripDisplay,
              boardMovingTime: boardMovingTime,
              boardMaxSpeedDisplay: boardMaxSpeedDisplay,
              boardAvgDisplay: boardAvgDisplay,
              boardMovingAvgDisplay: boardMovingAvgDisplay,
              gpsSpeedDisplay: gpsSpeedDisplay,
              gpsTripDisplay: gpsTripDistDisplay,
              gpsMaxSpeedDisplay: gpsMaxSpeedDisplay,
              gpsAvgDisplay: gpsAvgDisplay,
              gpsMovingAvgDisplay: gpsMovingAvgDisplay,
              phoneElapsed: elapsed,
              climbDisplay: climbDisplay,
              climbUnit: climbUnit,
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
              if (isTracking && !recorderBusy) ...[
                Material(
                  color: _ctlBg,
                  child: InkWell(
                    onTap: () => _rec.isPaused ? _rec.resume() : _rec.pause(),
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: _ctlBorder),
                      ),
                      child: Icon(
                        _rec.isPaused ? Icons.play_arrow : Icons.pause,
                        color: Esk8Theme.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Sharp filled primary CTA — board look, no rounded FAB.
              Material(
                color: recorderBusy
                    ? Esk8Theme.dim
                    : isTracking
                    ? const Color(0xFFEF4444)
                    : Esk8Theme.accent,
                child: InkWell(
                  onTap: recorderBusy ? null : _toggleTracking,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 15,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          recorderBusy
                              ? Icons.hourglass_top
                              : isTracking
                              ? Icons.stop
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          recordingState == TripRecordingState.starting
                              ? 'STARTING…'
                              : recordingState == TripRecordingState.stopping
                              ? 'SAVING…'
                              : isTracking
                              ? 'FINISH RIDE'
                              : 'START TRIP',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            fontSize: 15,
                          ),
                        ),
                      ],
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

  @override
  bool get wantKeepAlive => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RideGlanceCard extends StatelessWidget {
  final Color background;
  final Color border;
  final Color foreground;
  final Color dim;
  final String stateLabel;
  final Color stateColor;
  final String gpsLabel;
  final bool gpsDegraded;
  final String speed;
  final String speedUnit;
  final String speedSource;
  final String trip;
  final String tripUnit;
  final String tripLabel;
  final String movingTime;
  final String timeLabel;
  final String battery;
  final String batterySource;
  final VoidCallback onTap;

  const _RideGlanceCard({
    required this.background,
    required this.border,
    required this.foreground,
    required this.dim,
    required this.stateLabel,
    required this.stateColor,
    required this.gpsLabel,
    required this.gpsDegraded,
    required this.speed,
    required this.speedUnit,
    required this.speedSource,
    required this.trip,
    required this.tripUnit,
    required this.tripLabel,
    required this.movingTime,
    required this.timeLabel,
    required this.battery,
    required this.batterySource,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: stateColor, width: 4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    stateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: stateColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  gpsDegraded ? Icons.gps_off : Icons.gps_fixed,
                  size: 13,
                  color: gpsDegraded ? Esk8Theme.orange : dim,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    gpsLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: gpsDegraded ? Esk8Theme.orange : dim,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.battery_5_bar, size: 15, color: foreground),
                const SizedBox(width: 4),
                Text(
                  battery,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  batterySource,
                  style: TextStyle(
                    color: dim,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 16, color: dim),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: border, height: 1),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            speed,
                            style: Esk8Theme.number(46, color: foreground),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              speedUnit,
                              style: TextStyle(
                                color: dim,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              speedSource,
                              style: TextStyle(
                                color: speedSource == 'GPS'
                                    ? Esk8Theme.orange
                                    : dim,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: border),
                Expanded(
                  flex: 4,
                  child: _GlanceMetric(
                    value: trip,
                    unit: tripUnit,
                    label: tripLabel,
                    foreground: foreground,
                    dim: dim,
                  ),
                ),
                Container(width: 1, height: 40, color: border),
                Expanded(
                  flex: 4,
                  child: _GlanceMetric(
                    value: movingTime,
                    label: timeLabel,
                    foreground: foreground,
                    dim: dim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _GlanceMetric extends StatelessWidget {
  final String value;
  final String? unit;
  final String label;
  final Color foreground;
  final Color dim;

  const _GlanceMetric({
    required this.value,
    this.unit,
    required this.label,
    required this.foreground,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: Esk8Theme.number(20, color: foreground)),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: TextStyle(
                    color: dim,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: dim,
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    ),
  );
}

class _RideDetailsSheet extends StatelessWidget {
  final bool hasBoard;
  final Telemetry telemetry;
  final bool isMph;
  final LatLng? position;
  final String gpsStatus;
  final String speedSource;
  final String? storageError;
  final double boardTripDisplay;
  final Duration boardMovingTime;
  final double boardMaxSpeedDisplay;
  final double boardAvgDisplay;
  final double boardMovingAvgDisplay;
  final double gpsSpeedDisplay;
  final double gpsTripDisplay;
  final double gpsMaxSpeedDisplay;
  final double gpsAvgDisplay;
  final double gpsMovingAvgDisplay;
  final Duration phoneElapsed;
  final double climbDisplay;
  final String climbUnit;
  final VoidCallback onHistory;

  const _RideDetailsSheet({
    required this.hasBoard,
    required this.telemetry,
    required this.isMph,
    required this.position,
    required this.gpsStatus,
    required this.speedSource,
    required this.storageError,
    required this.boardTripDisplay,
    required this.boardMovingTime,
    required this.boardMaxSpeedDisplay,
    required this.boardAvgDisplay,
    required this.boardMovingAvgDisplay,
    required this.gpsSpeedDisplay,
    required this.gpsTripDisplay,
    required this.gpsMaxSpeedDisplay,
    required this.gpsAvgDisplay,
    required this.gpsMovingAvgDisplay,
    required this.phoneElapsed,
    required this.climbDisplay,
    required this.climbUnit,
    required this.onHistory,
  });

  static String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final unit = isMph ? 'MI' : 'KM';
    final speedUnit = isMph ? 'MPH' : 'KM/H';
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: BoxDecoration(
          color: Esk8Theme.panel,
          border: Border(top: BorderSide(color: Esk8Theme.border)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(width: 42, height: 4, color: Esk8Theme.border),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.route, color: Esk8Theme.accent),
                  const SizedBox(width: 10),
                  const Text(
                    'RIDE DETAILS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Esk8Theme.dim),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _EvidenceChip(
                    icon: Icons.speed,
                    label: 'SPEED · $speedSource',
                  ),
                  _EvidenceChip(icon: Icons.gps_fixed, label: gpsStatus),
                  if (hasBoard)
                    _EvidenceChip(
                      icon: Icons.battery_5_bar,
                      label:
                          'BATTERY · ${telemetry.batterySourceLabel}${telemetry.batteryLive ? ' ${telemetry.battery}%' : ''}',
                    )
                  else
                    const _EvidenceChip(
                      icon: Icons.phone_android,
                      label: 'PHONE-ONLY RIDE',
                    ),
                ],
              ),
              if (storageError != null) ...[
                const SizedBox(height: 12),
                _WarningPanel(
                  title: 'TRIP STORAGE WARNING',
                  message: storageError!,
                ),
              ],
              if (hasBoard) ...[
                const SizedBox(height: 20),
                const _DetailsHeader('BOARD · ODOMETRY EVIDENCE'),
                const SizedBox(height: 10),
                _DetailsGrid(
                  children: [
                    _DetailsMetric(
                      label: 'TRIP',
                      value: boardTripDisplay.toStringAsFixed(2),
                      unit: unit,
                    ),
                    _DetailsMetric(
                      label: 'MOVING TIME',
                      value: _duration(boardMovingTime),
                    ),
                    _DetailsMetric(
                      label: 'MAX',
                      value: boardMaxSpeedDisplay.toStringAsFixed(1),
                      unit: speedUnit,
                    ),
                    _DetailsMetric(
                      label: 'AVG / ELAPSED',
                      value: boardAvgDisplay.toStringAsFixed(1),
                      unit: speedUnit,
                    ),
                    _DetailsMetric(
                      label: 'AVG / MOVING',
                      value: boardMovingAvgDisplay.toStringAsFixed(1),
                      unit: speedUnit,
                    ),
                    _DetailsMetric(
                      label: 'EFFICIENCY',
                      value: telemetry.efficiency.toStringAsFixed(1),
                      unit: 'WH/${isMph ? 'MI' : 'KM'}',
                    ),
                    _DetailsMetric(
                      label: 'RANGE',
                      value: telemetry.batteryLive
                          ? telemetry.range.toStringAsFixed(1)
                          : '--',
                      unit: unit,
                    ),
                    _DetailsMetric(
                      label: 'ODOMETER',
                      value: telemetry.odometer.toStringAsFixed(1),
                      unit: unit,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              _DetailsHeader(
                hasBoard
                    ? 'PHONE GPS · ROUTE EVIDENCE'
                    : 'PHONE GPS · PRIMARY RIDE SOURCE',
              ),
              const SizedBox(height: 10),
              _DetailsGrid(
                children: [
                  _DetailsMetric(
                    label: 'SPEED',
                    value: gpsSpeedDisplay.toStringAsFixed(1),
                    unit: speedUnit,
                  ),
                  _DetailsMetric(
                    label: 'DISTANCE',
                    value: gpsTripDisplay.toStringAsFixed(2),
                    unit: unit,
                  ),
                  _DetailsMetric(
                    label: 'ELAPSED',
                    value: _duration(phoneElapsed),
                  ),
                  _DetailsMetric(
                    label: 'MAX',
                    value: gpsMaxSpeedDisplay.toStringAsFixed(1),
                    unit: speedUnit,
                  ),
                  _DetailsMetric(
                    label: 'AVG / ELAPSED',
                    value: gpsAvgDisplay.toStringAsFixed(1),
                    unit: speedUnit,
                  ),
                  _DetailsMetric(
                    label: 'AVG / MOVING',
                    value: gpsMovingAvgDisplay.toStringAsFixed(1),
                    unit: speedUnit,
                  ),
                  _DetailsMetric(
                    label: 'CLIMB',
                    value: climbDisplay.toStringAsFixed(0),
                    unit: climbUnit,
                  ),
                ],
              ),
              if (position != null) ...[
                const SizedBox(height: 18),
                Text(
                  '${position!.latitude.toStringAsFixed(5)}, '
                  '${position!.longitude.toStringAsFixed(5)}',
                  style: TextStyle(
                    color: Esk8Theme.dim,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onHistory,
                icon: const Icon(Icons.history),
                label: const Text('OPEN LIBRARY'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  final List<Widget> children;

  const _DetailsGrid({required this.children});

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 2.25,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    children: children,
  );
}

class _DetailsMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;

  const _DetailsMetric({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Esk8Theme.scaffold,
      border: Border.all(color: Esk8Theme.border),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: Esk8Theme.number(20)),
              if (unit != null) ...[
                const SizedBox(width: 5),
                Text(
                  unit!,
                  style: TextStyle(
                    color: Esk8Theme.dim,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: Esk8Theme.labelStyle),
      ],
    ),
  );
}

class _DetailsHeader extends StatelessWidget {
  final String text;

  const _DetailsHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Esk8Theme.dim,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    ),
  );
}

class _EvidenceChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _EvidenceChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Esk8Theme.scaffold,
      border: Border.all(color: Esk8Theme.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Esk8Theme.accent, size: 14),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
  );
}

class _WarningPanel extends StatelessWidget {
  final String title;
  final String message;

  const _WarningPanel({required this.title, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Esk8Theme.danger.withValues(alpha: 0.12),
      border: Border.all(color: Esk8Theme.danger),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Esk8Theme.danger,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}

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
        child: Icon(icon, color: highlighted ? Esk8Theme.accent : fg, size: 20),
      ),
    );
  }
}
