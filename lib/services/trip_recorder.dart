import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../ble/esk8os_ble.dart';
import '../database/trip_database.dart';

/// App-level trip recorder. Lives OUTSIDE the widget tree (singleton) so a trip
/// keeps recording when you swipe to another page, the screen sleeps, or the app
/// is backgrounded — the GPS stream runs under an Android foreground service that
/// keeps the process (and thus the BLE telemetry stream) alive.
///
/// It owns its own GPS + telemetry subscriptions and writes 1 Hz rows to the
/// trip DB. The UI observes it via [ChangeNotifier] and reads the getters.
class TripRecorder extends ChangeNotifier {
  TripRecorder._();
  static final TripRecorder instance = TripRecorder._();

  bool _isRecording = false;
  bool get isRecording => _isRecording;
  bool _starting = false; // guard: ignore repeat taps while start() is in flight

  int? _tripId;
  DateTime? _startTime;
  Duration get elapsed =>
      _startTime == null ? Duration.zero : DateTime.now().difference(_startTime!);

  final List<LatLng> _route = [];
  List<LatLng> get route => List.unmodifiable(_route);
  LatLng? _currentPosition;
  LatLng? get currentPosition => _currentPosition;

  // GPS-derived stats
  double _gpsDistanceM = 0; // meters
  double get gpsDistanceM => _gpsDistanceM;
  double _gpsMaxSpeedKmh = 0;
  double get gpsMaxSpeedKmh => _gpsMaxSpeedKmh;
  double _gpsSpeedKmh = 0;
  double get gpsSpeedKmh => _gpsSpeedKmh;
  // GPS course over ground (degrees, 0 = north). Held at the last good value
  // when stopped, since heading is meaningless at ~0 speed.
  double _heading = 0;
  double get heading => _heading;

  // Board-derived stats (from BLE telemetry)
  double _boardStartRange = -1; // sentinel: captured on first sample after start
  double get boardStartRange => _boardStartRange < 0 ? 0 : _boardStartRange;
  double _boardMaxSpeed = 0;
  double get boardMaxSpeed => _boardMaxSpeed;
  Telemetry? _latestTelemetry;
  Telemetry? get latestTelemetry => _latestTelemetry;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<Telemetry>? _telSub;
  Timer? _logTimer;

  /// Ensure (foreground) location permission. Returns false if denied or the
  /// location service is off. Background ('always') is requested best-effort so
  /// recording survives the app being swiped away, but foreground + the service
  /// already covers screen-off / pocketed.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  /// Start recording. [device] supplies board telemetry. Returns false if
  /// location permission/service is unavailable.
  Future<bool> start(Esk8Device device) async {
    if (_isRecording || _starting) return true; // ignore repeat taps
    _starting = true;
    if (!await ensurePermission()) {
      _starting = false;
      return false;
    }

    // Seed from the cached last-known fix (instant) rather than blocking on a
    // fresh cold GPS fix — the position stream below delivers fresh fixes within
    // a second, and recording flips on NOW so the button responds immediately.
    final last = await Geolocator.getLastKnownPosition();
    _route.clear();
    _currentPosition = last != null ? LatLng(last.latitude, last.longitude) : null;
    if (_currentPosition != null) _route.add(_currentPosition!);
    _gpsDistanceM = 0;
    _gpsMaxSpeedKmh = 0;
    _gpsSpeedKmh = 0;
    _boardStartRange = -1;
    _boardMaxSpeed = _latestTelemetry?.speed ?? 0;
    _startTime = DateTime.now();
    _tripId = await TripDatabase.instance.createTrip(_startTime!.millisecondsSinceEpoch);
    _isRecording = true;
    _starting = false;
    notifyListeners();

    // Board telemetry — kept fresh + max tracked even when no view shows it.
    _telSub = device.telemetry().listen((t) {
      _latestTelemetry = t;
      if (_boardStartRange < 0) _boardStartRange = t.range;
      if (t.speed > _boardMaxSpeed) _boardMaxSpeed = t.speed;
    });

    // GPS with a foreground service so location + the app survive backgrounding.
    final LocationSettings settings = (defaultTargetPlatform == TargetPlatform.android)
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'ESK8OS — recording trip',
              notificationText: 'Tracking your ride',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3);

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((position) {
      final p = LatLng(position.latitude, position.longitude);
      if (_route.isNotEmpty) {
        _gpsDistanceM += const Distance().as(LengthUnit.Meter, _route.last, p);
      }
      _route.add(p);
      _currentPosition = p;
      _gpsSpeedKmh = position.speed * 3.6; // m/s -> km/h
      if (_gpsSpeedKmh > _gpsMaxSpeedKmh) _gpsMaxSpeedKmh = _gpsSpeedKmh;
      if (position.speed > 0.8 && position.heading >= 0) _heading = position.heading;
      notifyListeners();
    });

    // Log one row per second regardless of motion.
    _logTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final id = _tripId;
      final p = _currentPosition;
      if (id == null || p == null) return;
      final t = _latestTelemetry;
      TripDatabase.instance.insertTelemetry({
        'tripId': id,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'lat': p.latitude,
        'lng': p.longitude,
        'gpsSpeed': _gpsSpeedKmh,
        'boardSpeed': t?.speed ?? 0.0,
        'battery': t?.battery ?? 0,
        'voltage': t?.volts ?? 0.0,
        'watts': t?.watts ?? 0,
      });
    });
    return true;
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    await _posSub?.cancel();
    _posSub = null;
    await _telSub?.cancel();
    _telSub = null;
    _logTimer?.cancel();
    _logTimer = null;

    final id = _tripId;
    if (id != null) {
      await TripDatabase.instance.updateTrip(
        id,
        DateTime.now().millisecondsSinceEpoch,
        _gpsDistanceM,
        _gpsMaxSpeedKmh,
        _boardMaxSpeed,
      );
    }
    _isRecording = false;
    _tripId = null;
    notifyListeners();
  }
}
