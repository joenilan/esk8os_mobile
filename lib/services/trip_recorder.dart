import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../ble/esk8os_ble.dart';
import '../database/trip_database.dart';
import 'app_prefs.dart';
import 'trip_fg_service.dart';

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
  static const double _kmPerMile = 1.609344;

  bool _isRecording = false;
  bool get isRecording => _isRecording;
  bool _starting =
      false; // guard: ignore repeat taps while start() is in flight

  int? _tripId;
  DateTime? _startTime;

  // Pause/resume — elapsed and all trip stats freeze while paused.
  bool _paused = false;
  bool get isPaused => _paused;
  int _pausedAccumMs = 0;
  int _pauseStartedMs = 0;

  Duration get elapsed {
    if (_startTime == null) return Duration.zero;
    var ms =
        DateTime.now().difference(_startTime!).inMilliseconds - _pausedAccumMs;
    if (_paused) ms -= DateTime.now().millisecondsSinceEpoch - _pauseStartedMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  void pause() {
    if (!_isRecording || _paused) return;
    _paused = true;
    _pauseStartedMs = DateTime.now().millisecondsSinceEpoch;
    _lastFixMs = 0; // don't count the pause gap as moving time
    _updateFgNotification();
    notifyListeners();
  }

  void resume() {
    if (!_isRecording || !_paused) return;
    _pausedAccumMs += DateTime.now().millisecondsSinceEpoch - _pauseStartedMs;
    _paused = false;
    _updateFgNotification();
    notifyListeners();
  }

  // ── Foreground service (the persistent notification + its buttons) ─────────
  bool _fgInited = false;

  void _initFg() {
    if (_fgInited) return;
    _fgInited = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'esk8_trip',
        channelName: 'Trip recording',
        channelDescription: 'Shows while a ride is being recorded',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  List<NotificationButton> _fgButtons() => [
    NotificationButton(
      id: _paused ? 'resume' : 'pause',
      text: _paused ? 'Resume' : 'Pause',
    ),
    const NotificationButton(id: 'stop', text: 'Stop'),
  ];

  Future<void> _startFgService() async {
    _initFg();
    await FlutterForegroundTask.requestNotificationPermission();
    FlutterForegroundTask.addTaskDataCallback(_onFgData);
    await FlutterForegroundTask.startService(
      serviceId: 4242,
      notificationTitle: 'ESK8OS — recording',
      notificationText: 'Tap to open',
      notificationButtons: _fgButtons(),
      callback: startTripTaskCallback,
    );
  }

  void _updateFgNotification() {
    if (!_isRecording) return;
    FlutterForegroundTask.updateService(
      notificationTitle: _paused ? 'ESK8OS — paused' : 'ESK8OS — recording',
      notificationText: 'Tap to open',
      notificationButtons: _fgButtons(),
    );
  }

  Future<void> _stopFgService() async {
    FlutterForegroundTask.removeTaskDataCallback(_onFgData);
    await FlutterForegroundTask.stopService();
  }

  /// Button taps arrive here (relayed from the service isolate).
  void _onFgData(Object data) {
    if (data is! Map) return;
    switch (data['action']) {
      case 'pause':
        pause();
        break;
      case 'resume':
        resume();
        break;
      case 'stop':
        stop();
        break;
    }
  }

  final List<LatLng> _route = [];
  bool _routeAnchorStale = false; // set while paused; next fix restarts the polyline
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
  // Moving-only stats (excludes time spent stopped at lights etc).
  int _movingMs = 0;
  int _lastFixMs = 0;
  double get gpsMovingAvgKmh =>
      _movingMs > 1000 ? _gpsDistanceM * 3.6 / (_movingMs / 1000.0) : 0.0;
  // Elevation. GPS altitude is jittery, so gain uses a 2 m deadband/anchor.
  double _altitude = 0;
  bool _haveAlt = false;
  double _elevGainM = 0;
  double get elevGainM => _elevGainM;
  // GPS course over ground (degrees, 0 = north). Held at the last good value
  // when stopped, since heading is meaningless at ~0 speed.
  double _heading = 0;
  double get heading => _heading;

  // Board-derived stats (from BLE telemetry)
  double _boardStartRange =
      -1; // sentinel: captured on first sample after start
  double get boardStartRange => _boardStartRange < 0 ? 0 : _boardStartRange;
  double _boardMaxSpeed = 0;
  double get boardMaxSpeed => _boardMaxSpeed;
  double _boardTripMiles = 0;
  double _boardWattHours = 0;
  double _boardRegenWh = 0;
  double _boardEffWhMi = 0;
  Telemetry? _latestTelemetry;
  Telemetry? get latestTelemetry => _latestTelemetry;
  Esk8Device? _device;

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
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  /// Start recording. [device] supplies board telemetry. Returns false if
  /// location permission/service is unavailable.
  Future<bool> start(Esk8Device device, {bool isMph = true}) async {
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
    _currentPosition = last != null
        ? LatLng(last.latitude, last.longitude)
        : null;
    if (_currentPosition != null) _route.add(_currentPosition!);
    _gpsDistanceM = 0;
    _gpsMaxSpeedKmh = 0;
    _gpsSpeedKmh = 0;
    _movingMs = 0;
    _lastFixMs = 0;
    _haveAlt = false;
    _elevGainM = 0;
    _paused = false;
    _pausedAccumMs = 0;
    _routeAnchorStale = false;
    _boardStartRange = -1;
    _boardMaxSpeed = _latestTelemetry?.speed ?? 0;
    _boardTripMiles = 0;
    _boardWattHours = 0;
    _boardRegenWh = 0;
    _boardEffWhMi = 0;
    _startTime = DateTime.now();
    _tripId = await TripDatabase.instance.createTrip(
      _startTime!.millisecondsSinceEpoch,
    );
    _device = device;
    _isRecording = true;
    _starting = false;
    // A new app trip = a new board session: zero the board's trip too (the
    // lifetime odometer is untouched). And keep the screen awake while riding.
    device.sendCommand(Esk8Commands.tripReset).catchError((_) {});
    WakelockPlus.enable();
    await _startFgService(); // persistent notification + buttons + keep-alive
    notifyListeners();

    // Board telemetry — kept fresh + max tracked even when no view shows it.
    _telSub = device.telemetry().listen((t) {
      _latestTelemetry = t;
      if (_boardStartRange < 0) _boardStartRange = t.range;
      if (t.speed > _boardMaxSpeed) _boardMaxSpeed = t.speed;
      _captureBoardRangeStats(t, isMph: t.mph ?? isMph);
    });

    // GPS. The flutter_foreground_task location service (started above) keeps
    // location + the app alive in the background, so geolocator doesn't run its
    // own second foreground service/notification here.
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((
      position,
    ) {
      final p = LatLng(position.latitude, position.longitude);
      // Paused: keep the marker live but freeze all trip accumulation. Mark the
      // route anchor stale so distance moved WHILE paused isn't credited to the
      // trip in one jump on the first post-resume fix.
      if (_paused) {
        _currentPosition = p;
        _gpsSpeedKmh = position.speed * 3.6;
        _lastFixMs = 0;
        _routeAnchorStale = true;
        notifyListeners();
        return;
      }
      // Reject low-quality fixes: urban-canyon jitter (30 m+ error circles)
      // inflates distance while stopped and can spike max speed.
      if (position.accuracy > 20) return;
      if (_routeAnchorStale) {
        // First fix after a pause: restart the polyline here, count no distance.
        _routeAnchorStale = false;
        _route.add(p);
        _currentPosition = p;
        _gpsSpeedKmh = position.speed * 3.6;
        notifyListeners();
        return;
      }
      if (_route.isNotEmpty) {
        _gpsDistanceM += const Distance().as(LengthUnit.Meter, _route.last, p);
      }
      // Moving-time accumulation (for moving-average): count the gap since the
      // last fix only while actually rolling (>~3 km/h).
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastFixMs != 0 && position.speed * 3.6 > 3) {
        final dt = nowMs - _lastFixMs;
        if (dt > 0 && dt < 5000) _movingMs += dt;
      }
      _lastFixMs = nowMs;
      // Elevation gain with a 2 m anchor/deadband to reject GPS altitude noise.
      final alt = position.altitude;
      if (!_haveAlt) {
        _altitude = alt;
        _haveAlt = true;
      } else if (alt - _altitude > 2.0) {
        _elevGainM += alt - _altitude;
        _altitude = alt;
      } else if (alt - _altitude < -2.0) {
        _altitude = alt;
      }
      _route.add(p);
      _currentPosition = p;
      _gpsSpeedKmh = position.speed * 3.6; // m/s -> km/h
      if (_gpsSpeedKmh > _gpsMaxSpeedKmh) _gpsMaxSpeedKmh = _gpsSpeedKmh;
      if (position.speed > 0.8 && position.heading >= 0) {
        _heading = position.heading;
      }
      notifyListeners();
    });

    // Log one row per second regardless of motion.
    var tick = 0;
    _logTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final id = _tripId;
      final p = _currentPosition;
      if (id == null || p == null || _paused) return;
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
        'altitude': _altitude,
      });
      // Checkpoint the trip summary every ~10 s so a hard kill (OS, crash, swipe)
      // still leaves a complete, up-to-date trip — never lose more than ~10 s.
      if (++tick % 10 == 0) {
        TripDatabase.instance.updateTrip(
          id,
          DateTime.now().millisecondsSinceEpoch,
          _gpsDistanceM,
          _gpsMaxSpeedKmh,
          _boardMaxSpeed,
          elevGainM: _elevGainM,
          boardDistanceMi: _boardTripMiles,
          wattHours: _boardWattHours,
          regenWh: _boardRegenWh,
          effWhMi: _boardEffWhMi,
        );
      }
    });
    return true;
  }

  void _captureBoardRangeStats(Telemetry t, {required bool isMph}) {
    _boardTripMiles = isMph ? t.trip : t.trip / _kmPerMile;
    _boardWattHours = t.wattHours;
    _boardRegenWh = t.regenWh;
    final netWh = _boardWattHours - _boardRegenWh;
    if (_boardTripMiles >= 0.01 && netWh > 0) {
      _boardEffWhMi = netWh / _boardTripMiles;
    }
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    WakelockPlus.disable(); // let the screen sleep again
    await _stopFgService(); // dismiss the notification + stop the service
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
        elevGainM: _elevGainM,
        boardDistanceMi: _boardTripMiles,
        wattHours: _boardWattHours,
        regenWh: _boardRegenWh,
        effWhMi: _boardEffWhMi,
      );
      await _autoLearnRangeModel();
    }
    _isRecording = false;
    _tripId = null;
    _device = null;
    notifyListeners();
  }

  Future<void> _autoLearnRangeModel() async {
    final device = _device;
    if (device == null || !AppPrefs.autoLearnRange) return;
    final trips = await TripDatabase.instance.getRecentRangeCalibrationTrips();
    double miles = 0;
    double wh = 0;
    var valid = 0;
    for (final trip in trips) {
      final tripMiles = _num(trip['boardDistanceMi']);
      final usedWh = _num(trip['wattHours']) - _num(trip['regenWh']);
      final eff = _num(trip['effWhMi']);
      if (tripMiles < 2.0 || usedWh < 20.0 || eff < 14.0 || eff > 40.0) {
        continue;
      }
      miles += tripMiles;
      wh += usedWh;
      valid++;
    }
    if (valid == 0 || miles <= 0 || wh <= 0) return;
    final learned = double.parse(
      (wh / miles).clamp(14.0, 40.0).toStringAsFixed(1),
    );
    try {
      await device.writeSettings(BoardSettings.writeJson(whPerMile: learned));
    } catch (_) {
      // Trip data is already saved; calibration can be applied next time.
    }
  }

  static double _num(dynamic value) => value is num ? value.toDouble() : 0.0;
}
