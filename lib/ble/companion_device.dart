import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'esk8os_ble.dart';

/// Scanning + connection wrapper around flutter_blue_plus for the ESK8OS
/// companion service. Build one [CompanionDevice] per connected board.
class CompanionScanner {
  /// Request the runtime BLE permissions needed to scan/connect. On Android 12+
  /// that's scan + connect; on older Android, location. No-ops elsewhere.
  static Future<bool> requestPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    // We can scan with scan+connect even if location is denied (neverForLocation).
    final scan = results[Permission.bluetoothScan];
    final connect = results[Permission.bluetoothConnect];
    return (scan == null || scan.isGranted || scan.isLimited) &&
        (connect == null || connect.isGranted || connect.isLimited);
  }

  /// Live scan results, filtered to boards advertising the companion service.
  static Stream<List<ScanResult>> results() => FlutterBluePlus.scanResults;

  static Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  static Future<void> start({Duration timeout = const Duration(seconds: 15)}) {
    return FlutterBluePlus.startScan(
      withServices: [Guid(Esk8Uuids.service)],
      timeout: timeout,
    );
  }

  static Future<void> stop() => FlutterBluePlus.stopScan();
}

/// A connected ESK8OS board: owns the GATT characteristics and exposes the
/// telemetry stream plus settings/command helpers.
class CompanionDevice {
  final BluetoothDevice device;
  BluetoothCharacteristic? _telemetry;
  BluetoothCharacteristic? _settings;
  BluetoothCharacteristic? _command;

  CompanionDevice(this.device);

  String get name =>
      device.platformName.isNotEmpty ? device.platformName : device.remoteId.str;

  Stream<BluetoothConnectionState> get connectionState =>
      device.connectionState;

  bool get isReady => _telemetry != null && _settings != null && _command != null;

  /// Connect, raise the MTU so JSON notifies aren't truncated, discover services,
  /// and bind the three companion characteristics.
  Future<void> connect() async {
    // flutter_blue_plus 2.x requires declaring a license at connect; nonprofit =
    // free tier for personal/hobby use (this app). Switch to commercial if sold.
    await device.connect(
      timeout: const Duration(seconds: 15),
      license: License.nonprofit,
    );
    // Best-effort large MTU (spec §7). Some stacks negotiate automatically.
    try {
      await device.requestMtu(512);
    } catch (_) {/* non-fatal */}

    final services = await device.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid == Guid(Esk8Uuids.service),
      orElse: () => throw StateError('ESK8OS companion service not found'),
    );
    for (final c in svc.characteristics) {
      if (c.uuid == Guid(Esk8Uuids.telemetry)) _telemetry = c;
      if (c.uuid == Guid(Esk8Uuids.settings)) _settings = c;
      if (c.uuid == Guid(Esk8Uuids.command)) _command = c;
    }
    if (!isReady) {
      throw StateError('ESK8OS companion characteristics missing');
    }
  }

  Future<void> disconnect() => device.disconnect();

  /// 5 Hz telemetry. Enables notifications and decodes each JSON notify.
  Stream<Telemetry> telemetry() async* {
    final c = _telemetry!;
    await c.setNotifyValue(true);
    yield* c.onValueReceived.map(_decodeTelemetry).where((t) => t != null).cast<Telemetry>();
  }

  static Telemetry? _decodeTelemetry(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final obj = jsonDecode(utf8.decode(bytes));
      if (obj is Map<String, dynamic>) return Telemetry.fromJson(obj);
    } catch (_) {/* partial/garbled notify — skip */}
    return null;
  }

  /// Read the board's current configuration.
  Future<BoardSettings?> readSettings() async {
    final bytes = await _settings!.read();
    if (bytes.isEmpty) return null;
    try {
      final obj = jsonDecode(utf8.decode(bytes));
      if (obj is Map<String, dynamic>) return BoardSettings.fromJson(obj);
    } catch (_) {/* ignore */}
    return null;
  }

  /// Write a partial settings update (see [BoardSettings.writeJson]).
  Future<void> writeSettings(Map<String, dynamic> partial) async {
    final bytes = utf8.encode(jsonEncode(partial));
    await _settings!.write(bytes); // settings char is WRITE (with response)
  }

  /// Send an ASCII command string (see [Esk8Commands]).
  Future<void> sendCommand(String cmd) async {
    await _command!.write(utf8.encode(cmd), withoutResponse: true);
  }
}
