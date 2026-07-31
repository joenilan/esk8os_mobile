import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../ble/esk8os_ble.dart';
import 'ride_distance_fusion.dart';
import '../database/trip_database.dart';
import 'app_prefs.dart';
import 'ride_position_filter.dart';
import 'trip_fg_service.dart';

enum TripRecordingState { idle, starting, recording, paused, stopping, error }

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
  TripRecordingState _state = TripRecordingState.idle;
  TripRecordingState get state => _state;
  bool get isBusy =>
      _state == TripRecordingState.starting ||
      _state == TripRecordingState.stopping;
  String? _lastError;
  String? get lastError => _lastError;

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
    if (!_isRecording || _paused || isBusy) return;
    _paused = true;
    _state = TripRecordingState.paused;
    _pauseStartedMs = DateTime.now().millisecondsSinceEpoch;
    _lastFixMs = 0; // don't count the pause gap as moving time
    _updateFgNotification();
    notifyListeners();
  }

  void resume() {
    if (!_isRecording || !_paused || isBusy) return;
    _pausedAccumMs += DateTime.now().millisecondsSinceEpoch - _pauseStartedMs;
    _paused = false;
    _state = TripRecordingState.recording;
    _updateFgNotification();
    notifyListeners();
  }

  // ── Foreground service (the persistent notification + its buttons) ─────────
  bool _fgInited = false;
  bool _fgRunning = false;
  bool _fgCallbackRegistered = false;

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
    if (!_fgCallbackRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_onFgData);
      _fgCallbackRegistered = true;
    }
    await FlutterForegroundTask.startService(
      serviceId: 4242,
      notificationTitle: 'EVEE — recording',
      notificationText: 'Tap to open',
      notificationButtons: _fgButtons(),
      callback: startTripTaskCallback,
    );
    _fgRunning = true;
  }

  void _updateFgNotification() {
    if (!_isRecording) return;
    FlutterForegroundTask.updateService(
      notificationTitle: _paused ? 'EVEE — paused' : 'EVEE — recording',
      notificationText: 'Tap to open',
      notificationButtons: _fgButtons(),
    );
  }

  Future<void> _stopFgService() async {
    if (_fgCallbackRegistered) {
      FlutterForegroundTask.removeTaskDataCallback(_onFgData);
      _fgCallbackRegistered = false;
    }
    if (!_fgRunning) return;
    try {
      await FlutterForegroundTask.stopService();
    } finally {
      _fgRunning = false;
    }
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
  bool _routeAnchorStale =
      false; // set while paused; next fix restarts the polyline
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
  final RidePositionFilter _positionFilter = RidePositionFilter();
  RidePositionRejection _lastPositionRejection = RidePositionRejection.none;
  RidePositionRejection get lastPositionRejection => _lastPositionRejection;
  int _lastAcceptedGpsMs = 0;
  bool _gpsStreamFailed = false;

  /// A recent accepted stream fix exists. A cached launch position is useful
  /// for centering the map, but is never treated as live ride evidence.
  bool get gpsLive =>
      !_gpsStreamFailed &&
      _lastAcceptedGpsMs != 0 &&
      DateTime.now().millisecondsSinceEpoch - _lastAcceptedGpsMs < 15000;

  bool get gpsHealthy =>
      gpsLive && _lastPositionRejection == RidePositionRejection.none;

  String get gpsQualityLabel {
    if (_gpsStreamFailed) return 'GPS UNAVAILABLE';
    if (_lastAcceptedGpsMs == 0) return 'ACQUIRING GPS…';
    if (!gpsLive) return 'GPS SIGNAL LOST';
    return switch (_lastPositionRejection) {
      RidePositionRejection.none => 'GPS READY',
      RidePositionRejection.invalid => 'GPS INVALID',
      RidePositionRejection.inaccurate => 'GPS LOW ACCURACY',
      RidePositionRejection.stale => 'GPS STALE',
      RidePositionRejection.implausibleJump => 'GPS JUMP FILTERED',
    };
  }

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
  BmsData? _latestBms;
  BmsData? get latestBms => _latestBms;
  Esk8Device? _device;

  /// The source selected when this recording began. It never changes midway
  /// through a ride, even if a vehicle connects or disconnects later.
  bool get recordingUsesBoard => _isRecording && _device != null;
  bool get recordingUsesPhoneOnly => _isRecording && _device == null;
  String get recordingSource =>
      recordingUsesPhoneOnly ? 'phone-gps' : 'board-assisted';

  // --- source accuracy: the board is authoritative for speed/distance while
  // it's actually feeding live data; if it drops (BLE lost, powered off, VESC
  // asleep) the numbers fall back to GPS so they stay real instead of freezing.
  int _lastTelemetryMs = 0;
  int _lastBmsMs = 0;
  bool _boardEverLive = false; // did a live board drive this ride at all?
  final RideDistanceFusion _distanceFusion = RideDistanceFusion();

  /// Board telemetry is live (a fresh, real frame within the last ~3 s).
  bool get boardLive {
    final t = _latestTelemetry;
    if (t == null || !t.live) return false;
    return DateTime.now().millisecondsSinceEpoch - _lastTelemetryMs < 3000;
  }

  /// Board speed normalised to km/h (telemetry.speed is in the board's unit).
  double get _boardSpeedKmh {
    final t = _latestTelemetry;
    if (t == null) return 0;
    return (t.mph ?? true) ? t.speed * _kmPerMile : t.speed;
  }

  /// The speed to trust right now — board when live, then a fresh accepted GPS
  /// fix. Never keep presenting a stale last-known speed after both sources go.
  double get effectiveSpeedKmh => boardLive
      ? _boardSpeedKmh
      : gpsLive
      ? _gpsSpeedKmh
      : 0;

  /// Which source is currently driving [effectiveSpeedKmh].
  String get speedSource => boardLive
      ? 'BOARD'
      : gpsLive
      ? 'GPS'
      : 'NONE';

  /// Monotonic trip distance. Board wheel odometry is preferred only after its
  /// counter proves that it advances; GPS covers a stuck, reset, or absent board
  /// counter without making the displayed trip jump backwards.
  double get effectiveTripKm => _distanceFusion.distanceKm;
  String get distanceSource => switch (_distanceFusion.source) {
    RideDistanceSource.board => 'BOARD',
    RideDistanceSource.gps => 'GPS',
    RideDistanceSource.none => 'NONE',
  };
  Duration get effectiveMovingTime => distanceSource == 'BOARD'
      ? Duration(seconds: _latestTelemetry?.tripMovingSeconds ?? 0)
      : Duration(milliseconds: _movingMs);

  /// Best max-speed estimate: board max when a board rode with us, else GPS max.
  double get effectiveMaxKmh => _boardEverLive
      ? ((_latestTelemetry?.mph ?? true)
            ? _boardMaxSpeed * _kmPerMile
            : _boardMaxSpeed)
      : _gpsMaxSpeedKmh;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<Telemetry>? _telSub;
  StreamSubscription<BmsData>? _bmsSub;
  Timer? _logTimer;
  Future<void> _dbQueue = Future<void>.value();
  String? _storageError;
  String? get storageError => _storageError;
  bool get storageHealthy => _storageError == null;

  void _enqueueDbWrite(Future<void> Function() operation) {
    _dbQueue = _dbQueue.then((_) => operation()).catchError((
      Object error,
      StackTrace _,
    ) {
      _storageError = error.toString();
      notifyListeners();
    });
  }

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

  /// Start recording. When [device] is null, the ride is intentionally
  /// phone-only: GPS owns speed, route, distance, elevation, and elapsed time,
  /// while every board/BMS field remains unavailable.
  Future<bool> start(Esk8Device? device, {bool isMph = true}) async {
    if (_isRecording || _state == TripRecordingState.starting) {
      return true; // ignore repeat taps
    }
    if (_state == TripRecordingState.stopping) return false;
    _state = TripRecordingState.starting;
    _lastError = null;
    notifyListeners();
    try {
      if (!await ensurePermission()) {
        _lastError =
            'Location Services and location permission are required to record.';
        _state = TripRecordingState.idle;
        notifyListeners();
        return false;
      }

      // Seed from the cached last-known fix (instant) rather than blocking on a
      // fresh cold GPS fix — the position stream below delivers fresh fixes within
      // a second, and recording flips on NOW so the button responds immediately.
      final last = await Geolocator.getLastKnownPosition();
      final seed = last == null ? null : _positionSample(last);
      final usableSeed = seed != null && RidePositionFilter.usableSeed(seed);
      _route.clear();
      _positionFilter.reset();
      _lastPositionRejection = RidePositionRejection.none;
      _currentPosition = usableSeed ? seed.point : null;
      // Do not put the cached fix into the recorded route. Even a valid seed
      // can be two minutes old and far from the actual start location.
      _lastAcceptedGpsMs = 0;
      _gpsStreamFailed = false;
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
      _boardMaxSpeed = 0;
      _lastTelemetryMs = 0;
      _lastBmsMs = 0;
      _latestTelemetry = null;
      _latestBms = null;
      _boardEverLive = false;
      _distanceFusion.reset();
      _boardTripMiles = 0;
      _boardWattHours = 0;
      _boardRegenWh = 0;
      _boardEffWhMi = 0;
      _storageError = null;
      _dbQueue = Future<void>.value();
      _startTime = DateTime.now();
      _tripId = await TripDatabase.instance.createTrip(
        _startTime!.millisecondsSinceEpoch,
        source: device == null ? 'phone-gps' : 'board-assisted',
      );
      _device = device;
      _isRecording = true;
      _state = TripRecordingState.recording;
      await WakelockPlus.enable();
      await _startFgService(); // persistent notification + buttons + keep-alive
      notifyListeners();

      if (device != null) {
        // A new board-backed app trip = a new board session. The lifetime
        // odometer is untouched. A phone-only ride sends no BLE commands.
        device.sendCommand(Esk8Commands.tripReset).catchError((_) {});

        // Board telemetry — kept fresh + max tracked even when no view shows it.
        _telSub = device.telemetry().listen((t) {
          _latestTelemetry = t;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          _lastTelemetryMs = nowMs;
          if (t.live) {
            _boardEverLive = true;
            if (_boardStartRange < 0) _boardStartRange = t.range;
            if (t.speed > _boardMaxSpeed) _boardMaxSpeed = t.speed;
            _captureBoardRangeStats(t, isMph: t.mph ?? isMph);
          }
          _distanceFusion.update(
            gpsKm: _gpsDistanceM / 1000.0,
            gpsLive: gpsLive,
            boardKm: _boardTripMiles * _kmPerMile,
            boardLive: t.live,
            nowMs: nowMs,
          );
          notifyListeners();
        });
        // Optional Daly stream. The board remains the single BMS radio owner;
        // the phone only persists the board's 0006 snapshots.
        if (device.hasBms) {
          _bmsSub = device.bms().listen((b) {
            _latestBms = b;
            _lastBmsMs = DateTime.now().millisecondsSinceEpoch;
          });
        }
      }

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
        final assessment = _positionFilter.assess(_positionSample(position));
        if (!assessment.accepted) {
          if (_lastPositionRejection != assessment.rejection) {
            _lastPositionRejection = assessment.rejection;
            notifyListeners();
          }
          return;
        }
        _gpsStreamFailed = false;
        _lastAcceptedGpsMs = DateTime.now().millisecondsSinceEpoch;
        _lastPositionRejection = RidePositionRejection.none;
        final p = LatLng(position.latitude, position.longitude);
        if (assessment.startsNewSegment && _route.isNotEmpty) {
          _routeAnchorStale = true;
        }
        // Paused: keep the marker live but freeze all trip accumulation. Mark the
        // route anchor stale so distance moved WHILE paused isn't credited to the
        // trip in one jump on the first post-resume fix.
        if (_paused) {
          _currentPosition = p;
          _gpsSpeedKmh = _nonNegativeSpeedMps(position) * 3.6;
          _lastFixMs = 0;
          _routeAnchorStale = true;
          notifyListeners();
          return;
        }
        if (_routeAnchorStale) {
          // First fix after a pause: restart the polyline here, count no distance.
          _routeAnchorStale = false;
          _route.add(p);
          _currentPosition = p;
          _gpsSpeedKmh = _nonNegativeSpeedMps(position) * 3.6;
          notifyListeners();
          return;
        }
        if (_route.isNotEmpty) {
          _gpsDistanceM += const Distance().as(
            LengthUnit.Meter,
            _route.last,
            p,
          );
        }
        // Moving-time accumulation (for moving-average): count the gap since the
        // last fix only while actually rolling (>~3 km/h).
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final speedMps = _nonNegativeSpeedMps(position);
        if (_lastFixMs != 0 && speedMps * 3.6 > 3) {
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
        _gpsSpeedKmh = speedMps * 3.6; // m/s -> km/h
        if (_gpsSpeedKmh > _gpsMaxSpeedKmh) _gpsMaxSpeedKmh = _gpsSpeedKmh;
        if (speedMps > 0.8 && position.heading >= 0) {
          _heading = position.heading;
        }
        _distanceFusion.update(
          gpsKm: _gpsDistanceM / 1000.0,
          gpsLive: true,
          boardKm: _boardTripMiles * _kmPerMile,
          boardLive: boardLive,
          nowMs: nowMs,
        );
        notifyListeners();
      }, onError: _onGpsStreamError);

      // Log one row per second regardless of motion.
      var tick = 0;
      _logTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final id = _tripId;
        final p = _currentPosition;
        if (id == null || p == null || _paused || !gpsHealthy) return;
        final t = _latestTelemetry;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final telemetryFresh = t != null && nowMs - _lastTelemetryMs < 3000;
        final driveFresh = telemetryFresh && t.live;
        final batteryFresh = telemetryFresh && t.batteryLive;
        final b = _latestBms;
        final bmsFresh = b != null && nowMs - _lastBmsMs < 3000;
        final row = <String, dynamic>{
          'tripId': id,
          'timestamp': nowMs,
          'lat': p.latitude,
          'lng': p.longitude,
          'gpsSpeed': _gpsSpeedKmh,
          'boardSpeed': driveFresh ? t.speed : 0.0,
          'battery': batteryFresh ? t.battery : 0,
          'voltage': batteryFresh ? t.volts : 0.0,
          'watts': driveFresh ? t.watts : 0,
          'altitude': _altitude,
          'bmsJson': bmsFresh ? b.toStorageJson() : null,
        };
        // Checkpoint the trip summary every ~10 s so a hard kill (OS, crash, swipe)
        // still leaves a complete, up-to-date trip — never lose more than ~10 s.
        final checkpoint = ++tick % 10 == 0;
        final gpsDistanceM = _gpsDistanceM;
        final gpsMaxSpeedKmh = _gpsMaxSpeedKmh;
        final boardMaxSpeed = _boardMaxSpeed;
        final elevGainM = _elevGainM;
        final boardDistanceMi = _boardTripMiles;
        final wattHours = _boardWattHours;
        final regenWh = _boardRegenWh;
        final effWhMi = _boardEffWhMi;
        _enqueueDbWrite(() async {
          await TripDatabase.instance.insertTelemetry(row);
          if (checkpoint) {
            await TripDatabase.instance.updateTrip(
              id,
              nowMs,
              gpsDistanceM,
              gpsMaxSpeedKmh,
              boardMaxSpeed,
              elevGainM: elevGainM,
              boardDistanceMi: boardDistanceMi,
              wattHours: wattHours,
              regenWh: regenWh,
              effWhMi: effWhMi,
            );
          }
        });
      });
      return true;
    } catch (error) {
      await _rollbackFailedStart(error);
      return false;
    }
  }

  Future<void> _rollbackFailedStart(Object error) async {
    _logTimer?.cancel();
    _logTimer = null;
    try {
      await _posSub?.cancel();
    } catch (_) {}
    _posSub = null;
    try {
      await _telSub?.cancel();
    } catch (_) {}
    _telSub = null;
    try {
      await _bmsSub?.cancel();
    } catch (_) {}
    _bmsSub = null;
    try {
      await _stopFgService();
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await _dbQueue;

    final id = _tripId;
    if (id != null) {
      try {
        // A failed start has not begun the 1 Hz logger. Remove only the new
        // empty shell row so it cannot appear as a phantom production ride.
        await TripDatabase.instance.deleteTrip(id);
      } catch (_) {}
    }
    _tripId = null;
    _device = null;
    _isRecording = false;
    _paused = false;
    _lastError = 'Could not start trip recording: $error';
    _state = TripRecordingState.error;
    notifyListeners();
  }

  void _onGpsStreamError(Object error, StackTrace stackTrace) {
    if (!_isRecording || _state == TripRecordingState.stopping) return;
    _gpsStreamFailed = true;
    _lastError = 'GPS stream stopped: $error';
    notifyListeners();
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
    if (!_isRecording || _state == TripRecordingState.stopping) return;
    _state = TripRecordingState.stopping;
    notifyListeners();

    Object? cleanupError;
    Future<void> attempt(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error) {
        cleanupError ??= error;
      }
    }

    // Stop producing work first, then drain every queued row before the final
    // summary. This guarantees Stop cannot race a late 1 Hz insert/checkpoint.
    _logTimer?.cancel();
    _logTimer = null;
    await attempt(() async => WakelockPlus.disable());
    await attempt(_stopFgService);
    await attempt(() async => _posSub?.cancel());
    _posSub = null;
    await attempt(() async => _telSub?.cancel());
    _telSub = null;
    await attempt(() async => _bmsSub?.cancel());
    _bmsSub = null;
    await _dbQueue;

    final id = _tripId;
    if (id != null) {
      await attempt(
        () => TripDatabase.instance.updateTrip(
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
        ),
      );
    }
    final device = _device;
    _isRecording = false;
    _paused = false;
    _tripId = null;
    _device = null;
    if (cleanupError != null) {
      _lastError = 'Trip stopped with a cleanup error: $cleanupError';
      _state = TripRecordingState.error;
    } else if (_storageError != null) {
      _lastError = 'Trip storage reported an error: $_storageError';
      _state = TripRecordingState.error;
    } else {
      _state = TripRecordingState.idle;
    }
    notifyListeners();
    if (device != null) {
      unawaited(_autoLearnRangeModel(device));
    }
  }

  Future<void> _autoLearnRangeModel(Esk8Device device) async {
    if (!AppPrefs.autoLearnRange) return;
    // fw 0.9.5+ learns its range model on-board (consumption AND pack IR /
    // deliverable energy, which the app can't measure). Never push whmi over
    // it — this path only calibrates older firmware that can't self-learn.
    try {
      final s = await device.readSettings();
      if (s != null && s.hasBoardCal) return;
    } catch (_) {
      return; // can't confirm the firmware generation -> don't write blind
    }
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

  static double _nonNegativeSpeedMps(Position position) =>
      position.speed < 0 ? 0 : position.speed;

  static RidePositionSample _positionSample(Position position) =>
      RidePositionSample(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        speedMps: position.speed,
        speedAccuracyMps: position.speedAccuracy,
        observedAt: position.timestamp,
      );
}
