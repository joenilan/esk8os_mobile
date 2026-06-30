import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

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
  double _wattHours = 0;
  // fw 0.9.0 expansion
  double _minVolts = 50.4;
  int _peakWatts = 0;
  double _regenWh = 0;
  double _avgSpeed = 0.0;
  double _trip = 0.0;
  double _odometer = 412.5;
  final int _startMs = DateTime.now().millisecondsSinceEpoch;
  int _samples = 0;
  double _speedSum = 0.0;

  BoardSettings _settings = const BoardSettings(
    hardware: 'tdisplay-s3',
    display: 'tft',
    ui: 'full',
    hasButtons: true,
    mph: true,
    theme: 'CYBER',
    poles: 14,
    wheelMm: 105,
    gear: 2.5,
    batterySeries: 12,
    profile: 0,
    packAh: 16.5,
    homeCellV: 3.40,
    stopCellV: 3.30,
    whPerMile: 22.0,
    brightness: 100,
    statusRgb: true,
    oledInvert: false,
    demo: false,
    rider: 'JOE',
    hudFace: 'speed',
    batteryFocus: 'pct',
    deviceName: "Joe's Deck",
    vehicleType: 1, // E-Bike (shows a non-default icon in mock mode)
  );

  @override
  Future<void> connect() async {
    _connectionState.add(DeviceConnectionState.connecting);
    await Future.delayed(const Duration(seconds: 1));
    _isConnected = true;
    _connectionState.add(DeviceConnectionState.connected);

    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      // Generate some fluctuating sine-wave data
      final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

      // Realistic, varied speed (~2–37) so the readouts move and the max isn't a
      // misleading constant 25.
      _speed = max(0, 19 + 13 * sin(time * 0.55) + 5 * sin(time * 2.3));
      _watts = (500 + 400 * sin(time * 2)).toInt(); // can dip negative -> regen
      _volts = 46.0 + 2.0 * cos(time * 0.5); // Voltage sag

      if (_speed > _maxSpeed) _maxSpeed = _speed;
      if (_volts < _minVolts) _minVolts = _volts;
      if (_watts > _peakWatts) _peakWatts = _watts;
      _trip += (_speed / 3600.0) * 0.2; // distance this tick (display unit)
      _odometer += (_speed / 3600.0) * 0.2;
      _range = max(0, 18.0 - _trip); // remaining range counts down
      _wattHours += max(0, _watts) / 3600.0 * 0.2;
      if (_watts < 0) _regenWh += -_watts / 3600.0 * 0.2;
      _samples++;
      _speedSum += _speed;
      _avgSpeed = _speedSum / _samples;

      final motorAmps = max(0.0, _watts / max(1.0, _volts) * 1.15);
      final batteryAmps = _watts / max(1.0, _volts);
      final eff = _trip > 0.05 ? (_wattHours / _trip) : 22.0;

      _telemetry.add(
        Telemetry(
          live: true,
          vescConnected: true,
          mph: _settings.mph,
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
          duty: (_speed / 40.0 * 100).clamp(0, 100).toInt(),
          peakWatts: _peakWatts,
          regenWh: _regenWh,
          minVolts: _minVolts,
          avgSpeed: _avgSpeed,
          trip: _trip,
          odometer: _odometer,
          estRange: 18.0,
          limpRange: _range + 2.0,
          limpEstRange: 20.0,
          efficiency: eff,
          fault: 0,
          rideSeconds:
              (DateTime.now().millisecondsSinceEpoch - _startMs) ~/ 1000,
          // Remote + diagnostics so DIAG / the HUD throttle bar animate in mock mode:
          // throttle tracks power (accel when drawing, brake when regen).
          throttle: (_watts / 900.0).clamp(-1.0, 1.0),
          remoteConnected: true,
          lastFault: 0,
          slaveOnline: true,
          masterMotorAmps: motorAmps / 2,
          slaveMotorAmps: motorAmps / 2,
          vescFw: '6.2',
          maxWattsSession: _peakWatts,
        ),
      );
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
    await _loadSettings(); // restore the rider/units/etc you set last time
    await Future.delayed(const Duration(milliseconds: 100));
    return _settings;
  }

  @override
  Future<void> writeSettings(Map<String, dynamic> partial) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _settings = BoardSettings(
      hardware: _settings.hardware,
      display: _settings.display,
      ui: _settings.ui,
      hasButtons: _settings.hasButtons,
      mph: partial['mph'] ?? _settings.mph,
      theme: partial['theme'] ?? _settings.theme,
      poles: _settings.poles,
      wheelMm: _settings.wheelMm,
      gear: _settings.gear,
      batterySeries: partial['bat_s'] ?? _settings.batterySeries,
      profile: partial['profile'] ?? _settings.profile,
      packAh: (partial['packAh'] as num?)?.toDouble() ?? _settings.packAh,
      homeCellV:
          (partial['homeCell'] as num?)?.toDouble() ?? _settings.homeCellV,
      stopCellV:
          (partial['stopCell'] as num?)?.toDouble() ?? _settings.stopCellV,
      whPerMile: (partial['whmi'] as num?)?.toDouble() ?? _settings.whPerMile,
      brightness: (partial['bright'] as num?)?.toInt() ?? _settings.brightness,
      statusRgb: partial['rgb'] ?? _settings.statusRgb,
      oledInvert: partial['oled_inv'] ?? _settings.oledInvert,
      demo: partial['demo'] ?? _settings.demo,
      rider: partial['rider'] ?? _settings.rider,
      hudFace: partial['hud'] ?? _settings.hudFace,
      batteryFocus: partial['bfocus'] ?? _settings.batteryFocus,
      deviceName: partial['name'] ?? _settings.deviceName,
      vehicleType: partial['vtype'] ?? _settings.vehicleType,
    );
    await _saveSettings(); // mock persists like the real board's NVS
  }

  // Mock settings survive app restarts/updates (the real board uses NVS; this
  // mirrors that so testing doesn't reset rider/units every time.)
  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('mock_settings');
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    _settings = BoardSettings(
      hardware: _settings.hardware,
      display: _settings.display,
      ui: _settings.ui,
      hasButtons: _settings.hasButtons,
      mph: m['mph'] ?? _settings.mph,
      theme: m['theme'] ?? _settings.theme,
      poles: _settings.poles,
      wheelMm: _settings.wheelMm,
      gear: _settings.gear,
      batterySeries: m['bat_s'] ?? _settings.batterySeries,
      profile: m['profile'] ?? _settings.profile,
      packAh: (m['packAh'] as num?)?.toDouble() ?? _settings.packAh,
      homeCellV: (m['homeCell'] as num?)?.toDouble() ?? _settings.homeCellV,
      stopCellV: (m['stopCell'] as num?)?.toDouble() ?? _settings.stopCellV,
      whPerMile: (m['whmi'] as num?)?.toDouble() ?? _settings.whPerMile,
      brightness: (m['bright'] as num?)?.toInt() ?? _settings.brightness,
      statusRgb: m['rgb'] ?? _settings.statusRgb,
      oledInvert: m['oled_inv'] ?? _settings.oledInvert,
      demo: m['demo'] ?? _settings.demo,
      rider: m['rider'] ?? _settings.rider,
      hudFace: m['hud'] ?? _settings.hudFace,
      batteryFocus: m['bfocus'] ?? _settings.batteryFocus,
      deviceName: m['name'] ?? _settings.deviceName,
      vehicleType: m['vtype'] ?? _settings.vehicleType,
    );
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'mock_settings',
      jsonEncode({
        'mph': _settings.mph,
        'theme': _settings.theme,
        'bat_s': _settings.batterySeries,
        'profile': _settings.profile,
        'packAh': _settings.packAh,
        'homeCell': _settings.homeCellV,
        'stopCell': _settings.stopCellV,
        'whmi': _settings.whPerMile,
        'bright': _settings.brightness,
        'rgb': _settings.statusRgb,
        'oled_inv': _settings.oledInvert,
        'demo': _settings.demo,
        'rider': _settings.rider,
        'hud': _settings.hudFace,
        'bfocus': _settings.batteryFocus,
        'name': _settings.deviceName,
        'vtype': _settings.vehicleType,
      }),
    );
  }

  @override
  Future<void> sendCommand(String command) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
