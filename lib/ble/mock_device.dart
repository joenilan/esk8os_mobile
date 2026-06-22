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

  BoardSettings _settings = const BoardSettings(
    mph: true,
    theme: 'CYBER',
    poles: 14,
    wheelMm: 105,
    gear: 2.5,
    batterySeries: 12,
    profile: 0,
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
      _watts = max(0, (500 + 400 * sin(time * 2)).toInt()); // 100W to 900W
      _volts = 46.0 + 2.0 * cos(time * 0.5); // Voltage sag
      
      if (_speed > _maxSpeed) _maxSpeed = _speed;
      _range += (_speed / 3600.0) * 0.2; // roughly simulate distance
      _wattHours += (_watts / 3600.0 * 0.2).toInt();

      _telemetry.add(Telemetry(
        speed: _speed,
        battery: _battery,
        volts: _volts,
        watts: _watts,
        motorTempC: _motorTemp,
        escTempC: _escTemp,
        range: _range,
        maxSpeed: _maxSpeed,
        wattHours: _wattHours,
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
    );
  }

  @override
  Future<void> sendCommand(String command) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
