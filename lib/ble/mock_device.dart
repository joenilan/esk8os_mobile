import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'esk8os_ble.dart';

class MockDevice implements Esk8Device {
  @override
  String get name => 'Mock EVEE';

  final _connectionState = StreamController<DeviceConnectionState>.broadcast();
  bool _isConnected = false;

  @override
  Stream<DeviceConnectionState> get connectionState => _connectionState.stream;

  @override
  bool get isReady => _isConnected;

  Timer? _telemetryTimer;
  final _telemetry = StreamController<Telemetry>.broadcast();

  Timer? _bmsTimer;
  final _bms = StreamController<BmsData>.broadcast();

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
  double _maxMotorA = 0.0;
  double _maxBattA = 0.0;
  double _regenWh = 0;
  double _avgSpeed = 0.0;
  double _trip = 0.0;
  double _odometer = 412.5;
  final int _startMs = DateTime.now().millisecondsSinceEpoch;
  int _samples = 0;
  double _speedSum = 0.0;
  final Set<String> _mockOverrides = {};

  BoardSettings _settings = const BoardSettings(
    hardware: 'tdisplay-s3',
    display: 'tft',
    ui: 'full',
    hasButtons: true,
    mph: true,
    theme: 'CYBER',
    poles: 14,
    wheelMm: 203,
    wheelOverrideMm: 0,
    gear: 4.5,
    batterySeries: 10,
    profile: 0,
    packAh: 32.0,
    homeCellV: 3.20,
    stopCellV: 3.00,
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
    vehicleLabel: '',
    vehicleCustomIcon: 0,
    // Mimic fw 0.9.5+ on-board adaptive calibration so the settings page's
    // "Device-learned calibration" tile shows in mock mode.
    hasBoardCal: true,
    calPackROhm: 45,
    calTypicalAmps: 16.4,
    calWhPerMile: 0,
    calPackWh: 0,
    firmwareVersion: 'v0.10.1 mock',
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
      if (motorAmps > _maxMotorA) _maxMotorA = motorAmps;
      if (batteryAmps > _maxBattA) _maxBattA = batteryAmps;
      final eff = _trip > 0.05 ? (_wattHours / _trip) : 22.0;

      _telemetry.add(
        Telemetry(
          live: true,
          vescConnected: false,
          batteryLive: true,
          batterySource: 'demo',
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
          maxBatteryAmps: _maxBattA,
          maxMotorAmps: _maxMotorA,
        ),
      );
    });

    // 1 Hz synthetic Daly pack — mirrors the firmware's simulateBms(): a 10S
    // pack with a normal ~10 mV spread plus the physically verified Level-1
    // high-state warning, matching the installed 10S UART-K pack.
    _bmsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _bms.add(_mockBms());
    });
  }

  BmsData _mockBms() {
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final wave = sin(time * 0.3);
    final soc = (70 + 15 * wave).round();
    final nominal = (3600 + (soc - 55) / 30.0 * 400).round();
    final cells = <int>[];
    for (var c = 0; c < 10; c++) {
      cells.add(nominal + ((c * 7) % 11) - 5);
    }
    final minMv = cells.reduce(min);
    final maxMv = cells.reduce(max);
    final packV = cells.fold<int>(0, (a, b) => a + b) / 1000.0;
    final t0 = 26 + (4 * wave).round();
    final t1 = 28 + (3 * wave).round();
    return BmsData(
      link: true,
      freshnessMask: BmsData.allFreshMask,
      alarmLevel: 1,
      rawFaultBytes: '11000000000000',
      packVolts: packV,
      current: -(10 + 8 * wave), // discharging
      soc: soc,
      remainingAh: 32.0 * soc / 100.0,
      cycles: 42,
      cellCount: 10,
      cellsMv: cells,
      minMv: minMv,
      minCell: cells.indexOf(minMv) + 1,
      maxMv: maxMv,
      maxCell: cells.indexOf(maxMv) + 1,
      deltaMv: maxMv - minMv,
      temps: [t0, t1],
      tempMin: min(t0, t1),
      tempMax: max(t0, t1),
      chargeMos: true,
      dischargeMos: true,
      fault: true,
      ocWarnA: 36.0,
      ocProtect1A: 45.0,
      ocProtect1DelayMs: 1000,
      ocProtect2A: 60.0,
      ocProtect2DelayMs: 500,
      ocAgeSec: 8,
    );
  }

  @override
  Future<void> disconnect() async {
    _telemetryTimer?.cancel();
    _bmsTimer?.cancel();
    _isConnected = false;
    _connectionState.add(DeviceConnectionState.disconnected);
  }

  @override
  Stream<Telemetry> telemetry() => _telemetry.stream;

  @override
  bool get hasBms => true;

  @override
  Stream<BmsData> bms() => _bms.stream;

  @override
  Future<BoardSettings?> readSettings() async {
    await _loadSettings(); // restore the rider/units/etc you set last time
    await Future.delayed(const Duration(milliseconds: 100));
    return _settings;
  }

  @override
  Future<BaseConfig?> readBaseConfig() async {
    await Future.delayed(const Duration(milliseconds: 60));
    // Mirrors a real dual-FW6.5 capture so the tier UI is exercisable in mock.
    return BaseConfig(
      valid: true,
      cells: 10,
      packAh: 32.0,
      cutStartV: 32.0,
      cutEndV: 30.0,
      poles: 14,
      gearRatio: 4.5,
      wheelMm: 203,
      motorAmpMax: 57,
      battAmpMax: 15,
      battAmpRegen: -5,
      src: {
        'cells': _mockOverrides.contains('cells') ? 'r' : 'v',
        'ah': _mockOverrides.contains('packAh') ? 'r' : 'v',
        'home': _mockOverrides.contains('homeCell') ? 'r' : 'v',
        'stop': _mockOverrides.contains('stopCell') ? 'r' : 'v',
        'whmi': _mockOverrides.contains('whmi') ? 'r' : 'd',
        'wheel': _mockOverrides.contains('wheelmm') ? 'r' : 'v',
      },
    );
  }

  @override
  Future<void> writeSettings(Map<String, dynamic> partial) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (partial.containsKey('bat_s')) _mockOverrides.add('cells');
    if (partial.containsKey('packAh')) _mockOverrides.add('packAh');
    if (partial.containsKey('homeCell')) _mockOverrides.add('homeCell');
    if (partial.containsKey('stopCell')) _mockOverrides.add('stopCell');
    if (partial.containsKey('whmi')) _mockOverrides.add('whmi');
    if (partial.containsKey('wheelmm')) {
      if ((partial['wheelmm'] as int) > 0) {
        _mockOverrides.add('wheelmm');
      } else {
        _mockOverrides.remove('wheelmm');
      }
    }
    _settings = BoardSettings(
      hardware: _settings.hardware,
      display: _settings.display,
      ui: _settings.ui,
      hasButtons: _settings.hasButtons,
      mph: partial['mph'] ?? _settings.mph,
      theme: partial['theme'] ?? _settings.theme,
      poles: _settings.poles,
      wheelMm: (partial['wheelmm'] != null && (partial['wheelmm'] as int) > 0)
          ? partial['wheelmm']
          : _settings.wheelMm,
      wheelOverrideMm: partial['wheelmm'] ?? _settings.wheelOverrideMm,
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
      vehicleLabel: partial['vlabel'] ?? _settings.vehicleLabel,
      vehicleCustomIcon: partial['vicon'] ?? _settings.vehicleCustomIcon,
      hasBoardCal: _settings.hasBoardCal,
      calPackROhm: _settings.calPackROhm,
      calTypicalAmps: _settings.calTypicalAmps,
      calWhPerMile: _settings.calWhPerMile,
      calPackWh: _settings.calPackWh,
      firmwareVersion: _settings.firmwareVersion,
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
      wheelOverrideMm: _settings.wheelOverrideMm,
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
      vehicleLabel: m['vlabel'] ?? _settings.vehicleLabel,
      vehicleCustomIcon: m['vicon'] ?? _settings.vehicleCustomIcon,
      hasBoardCal: _settings.hasBoardCal,
      calPackROhm: _settings.calPackROhm,
      calTypicalAmps: _settings.calTypicalAmps,
      calWhPerMile: _settings.calWhPerMile,
      calPackWh: _settings.calPackWh,
      firmwareVersion: _settings.firmwareVersion,
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
        'vlabel': _settings.vehicleLabel,
        'vicon': _settings.vehicleCustomIcon,
      }),
    );
  }

  @override
  Future<void> sendCommand(String command) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!command.startsWith('UNSET:')) return;
    final key = command.substring(6);
    final fallback = switch (key) {
      'cells' => <String, dynamic>{'bat_s': 10},
      'packAh' => <String, dynamic>{'packAh': 32.0},
      'homeCell' => <String, dynamic>{'homeCell': 3.20},
      'stopCell' => <String, dynamic>{'stopCell': 3.00},
      'whmi' => <String, dynamic>{'whmi': 20.0},
      'wheelmm' => <String, dynamic>{'wheelmm': 0},
      _ => const <String, dynamic>{},
    };
    if (fallback.isEmpty) return;
    await writeSettings(fallback);
    _mockOverrides.remove(key);
  }
}
