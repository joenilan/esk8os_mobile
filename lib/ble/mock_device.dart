import 'dart:async';
import 'dart:math';

import 'esk8os_ble.dart';

class MockDevice implements Esk8Device {
  @override
  String get name => 'Mock ESK8 Board';

  final _connectionState = StreamController<DeviceConnectionState>.broadcast();
  bool _isConnected = false;

  @override
  Stream<DeviceConnectionState> get connectionState => _connectionState.stream;

  @override
  bool get isReady => _isConnected;

  Timer? _telemetryTimer;
  final _telemetry = StreamController<Telemetry>.broadcast();

  // Mock state
  double _speed = 0.0;
  final int _battery = 100;
  double _volts = 48.0;
  int _watts = 0;
  final int _motorTemp = 25;
  final int _escTemp = 30;
  double _range = 0.0;
  double _maxSpeed = 0.0;
  int _wattHours = 0;
  // fw 0.9.0 expansion
  double _minVolts = 50.4;
  int _peakWatts = 0;
  int _regenWh = 0;
  double _avgSpeed = 0.0;
  double _trip = 0.0;
  double _odometer = 412.5;
  final int _startMs = DateTime.now().millisecondsSinceEpoch;
  int _samples = 0;
  double _speedSum = 0.0;

  BoardSettings _settings = const BoardSettings(
    mph: true,
    theme: 'CYBER',
    poles: 14,
    wheelMm: 105,
    gear: 2.5,
    batterySeries: 12,
    profile: 0,
    packAh: 16.5,
    stopCellV: 3.30,
    whPerMile: 22,
    brightness: 100,
    demo: false,
    rider: 'JOE',
  );

  @override
  Future<void> connect() async {
    _connectionState.add(DeviceConnectionState.connecting);
    await Future.delayed(const Duration(seconds: 1));
    _isConnected = true;
    _connectionState.add(DeviceConnectionState.connected);

    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      // Generate some fluctuating sine-wave data
      final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
      
      _speed = max(0, 15 + 10 * sin(time)); // Fluctuates between 5 and 25
      _watts = (500 + 400 * sin(time * 2)).toInt(); // can dip negative -> regen
      _volts = 46.0 + 2.0 * cos(time * 0.5); // Voltage sag

      if (_speed > _maxSpeed) _maxSpeed = _speed;
      if (_volts < _minVolts) _minVolts = _volts;
      if (_watts > _peakWatts) _peakWatts = _watts;
      _trip += (_speed / 3600.0) * 0.2; // distance this tick (display unit)
      _odometer += (_speed / 3600.0) * 0.2;
      _range = max(0, 18.0 - _trip); // remaining range counts down
      _wattHours += (max(0, _watts) / 3600.0 * 0.2).toInt();
      if (_watts < 0) _regenWh += (-_watts / 3600.0 * 0.2).toInt();
      _samples++;
      _speedSum += _speed;
      _avgSpeed = _speedSum / _samples;

      final motorAmps = max(0.0, _watts / max(1.0, _volts) * 1.15);
      final batteryAmps = _watts / max(1.0, _volts);
      final eff = _trip > 0.05 ? (_wattHours / _trip).round() : 22;

      _telemetry.add(Telemetry(
        speed: _speed,
        battery: _battery,
        volts: _volts,
        watts: max(0, _watts),
        motorTempC: _motorTemp,
        escTempC: _escTemp,
        range: _range,
        maxSpeed: _maxSpeed,
        wattHours: _wattHours,
        batteryTempC: 28,
        batteryAmps: batteryAmps,
        motorAmps: motorAmps,
        duty: (_speed / 25.0 * 90).clamp(0, 100).toInt(),
        peakWatts: _peakWatts,
        regenWh: _regenWh,
        minVolts: _minVolts,
        avgSpeed: _avgSpeed,
        trip: _trip,
        odometer: _odometer,
        estRange: 18.0,
        efficiency: eff,
        fault: 0,
        rideSeconds: (DateTime.now().millisecondsSinceEpoch - _startMs) ~/ 1000,
      ));
    });
  }

  @override
  Future<void> disconnect() async {
    _telemetryTimer?.cancel();
    _isConnected = false;
    _connectionState.add(DeviceConnectionState.disconnected);
  }

  @override
  Stream<Telemetry> telemetry() => _telemetry.stream;

  @override
  Future<BoardSettings?> readSettings() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _settings;
  }

  @override
  Future<void> writeSettings(Map<String, dynamic> partial) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _settings = BoardSettings(
      mph: partial['mph'] ?? _settings.mph,
      theme: partial['theme'] ?? _settings.theme,
      poles: _settings.poles,
      wheelMm: _settings.wheelMm,
      gear: _settings.gear,
      batterySeries: partial['bat_s'] ?? _settings.batterySeries,
      profile: partial['profile'] ?? _settings.profile,
      packAh: (partial['packAh'] as num?)?.toDouble() ?? _settings.packAh,
      stopCellV: (partial['stopCell'] as num?)?.toDouble() ?? _settings.stopCellV,
      whPerMile: (partial['whmi'] as num?)?.toInt() ?? _settings.whPerMile,
      brightness: (partial['bright'] as num?)?.toInt() ?? _settings.brightness,
      demo: partial['demo'] ?? _settings.demo,
      rider: partial['rider'] ?? _settings.rider,
    );
  }

  @override
  Future<void> sendCommand(String command) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
