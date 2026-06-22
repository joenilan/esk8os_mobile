/// ESK8OS companion BLE contract — mirrors `docs/companion_api_spec.md` in the
/// firmware repo (Esk8OS). Pure Dart (no plugin imports) so it stays testable.
library;

/// Custom companion service + characteristic UUIDs (spec §2).
class Esk8Uuids {
  static const String service = '5043697a-0000-4682-93cb-33bb0a149f7e';
  static const String telemetry = '5043697a-0001-4682-93cb-33bb0a149f7e'; // NOTIFY
  static const String settings = '5043697a-0002-4682-93cb-33bb0a149f7e'; // READ | WRITE
  static const String command = '5043697a-0003-4682-93cb-33bb0a149f7e'; // WRITE
}

/// Command strings written to the command characteristic (spec §5).
class Esk8Commands {
  static const String tripReset = 'TRIP_RESET';
  static const String pageNext = 'PAGE_NEXT';
  static const String pagePrev = 'PAGE_PREV';

  /// Jump the board to an absolute page index (board PageId enum:
  /// 0=HUD 1=DASH 2=POWER 3=TRIP 4=SETTINGS 5=SYSTEM 6=GRAPHS 7=LOGS).
  static String pageSet(int boardPage) => 'PAGE_SET:$boardPage';
  static const String bridgeMode = 'BRIDGE_MODE';
  static const String wifiExportStart = 'WIFI_EXPORT_START';
  static const String wifiExportStop = 'WIFI_EXPORT_STOP';
  static const String reboot = 'REBOOT';
}

/// The board's WiFi AP for the hybrid log/OTA transfer (spec §6). The board
/// raises this after WIFI_EXPORT_START (or in bridge mode); the user joins it and
/// the app fetches over HTTP.
class Esk8WifiExport {
  static const String ssid = 'ESK8-BRIDGE';
  static const String password = 'esk8bridge';
  static const String baseUrl = 'http://192.168.4.1';
}

/// Telemetry payload (spec §3): one JSON object pushed at 5 Hz. All speed/range/
/// distance/efficiency values arrive already converted to the board's display
/// unit (mph+mi when [BoardSettings.mph], else km/h+km) — do **not** re-convert.
/// `efficiency` is Wh/mi (mph) or Wh/km.
///
/// The first nine fields predate fw 0.9.0; the rest were added in the payload
/// expansion and default to 0 so an older board (or DB-replayed sample) that
/// omits them still parses cleanly.
class Telemetry {
  final double speed; // spd
  final int battery; // bat (%)
  final double volts; // v
  final int watts; // w
  final int motorTempC; // mtr_t
  final int escTempC; // esc_t
  final double range; // rng
  final double maxSpeed; // max_s
  final int wattHours; // wh
  // --- fw 0.9.0 payload expansion ---
  final int batteryTempC; // btemp
  final double batteryAmps; // bata
  final double motorAmps; // mota
  final int duty; // duty (%)
  final int peakWatts; // pkw
  final int regenWh; // whr
  final double minVolts; // minv
  final double avgSpeed; // avs
  final double trip; // trip (display unit)
  final double odometer; // odo (display unit)
  final double estRange; // est (display unit, full charge)
  final int efficiency; // eff (Wh/mi or Wh/km)
  final int fault; // fault (VESC fault code, 0 = none)
  final int rideSeconds; // rtime (s since power-on)

  const Telemetry({
    required this.speed,
    required this.battery,
    required this.volts,
    required this.watts,
    required this.motorTempC,
    required this.escTempC,
    required this.range,
    required this.maxSpeed,
    required this.wattHours,
    this.batteryTempC = 0,
    this.batteryAmps = 0.0,
    this.motorAmps = 0.0,
    this.duty = 0,
    this.peakWatts = 0,
    this.regenWh = 0,
    this.minVolts = 0.0,
    this.avgSpeed = 0.0,
    this.trip = 0.0,
    this.odometer = 0.0,
    this.estRange = 0.0,
    this.efficiency = 0,
    this.fault = 0,
    this.rideSeconds = 0,
  });

  factory Telemetry.fromJson(Map<String, dynamic> j) => Telemetry(
        speed: _d(j['spd']),
        battery: _i(j['bat']),
        volts: _d(j['v']),
        watts: _i(j['w']),
        motorTempC: _i(j['mtr_t']),
        escTempC: _i(j['esc_t']),
        range: _d(j['rng']),
        maxSpeed: _d(j['max_s']),
        wattHours: _i(j['wh']),
        batteryTempC: _i(j['btemp']),
        batteryAmps: _d(j['bata']),
        motorAmps: _d(j['mota']),
        duty: _i(j['duty']),
        peakWatts: _i(j['pkw']),
        regenWh: _i(j['whr']),
        minVolts: _d(j['minv']),
        avgSpeed: _d(j['avs']),
        trip: _d(j['trip']),
        odometer: _d(j['odo']),
        estRange: _d(j['est']),
        efficiency: _i(j['eff']),
        fault: _i(j['fault']),
        rideSeconds: _i(j['rtime']),
      );
}

/// Board configuration (spec §4). `poles`, `wheel`, and `gear` are READ-ONLY —
/// they're derived from the selected wheel preset; write [profile] to switch
/// presets. Writable fields: [mph], [theme], [batterySeries], [profile],
/// [packAh], [stopCellV], [whPerMile], [brightness], [demo]. The battery/range
/// tuning fields and [brightness]/[demo] were added in fw 0.9.0 and default to 0
/// /false when read from an older board.
class BoardSettings {
  final bool mph;
  final String theme;
  final int poles; // read-only
  final int wheelMm; // read-only
  final double gear; // read-only
  final int batterySeries; // bat_s
  final int profile;
  // --- fw 0.9.0 ---
  final double packAh; // packAh
  final double stopCellV; // stopCell
  final int whPerMile; // whmi
  final int brightness; // bright (%)
  final bool demo; // demo
  final String rider; // rider

  const BoardSettings({
    required this.mph,
    required this.theme,
    required this.poles,
    required this.wheelMm,
    required this.gear,
    required this.batterySeries,
    required this.profile,
    this.packAh = 0.0,
    this.stopCellV = 0.0,
    this.whPerMile = 0,
    this.brightness = 100,
    this.demo = false,
    this.rider = '',
  });

  factory BoardSettings.fromJson(Map<String, dynamic> j) => BoardSettings(
        mph: j['mph'] == true,
        theme: (j['theme'] ?? '').toString(),
        poles: _i(j['poles']),
        wheelMm: _i(j['wheel']),
        gear: _d(j['gear']),
        batterySeries: _i(j['bat_s']),
        profile: _i(j['profile']),
        packAh: _d(j['packAh']),
        stopCellV: _d(j['stopCell']),
        whPerMile: _i(j['whmi']),
        brightness: j.containsKey('bright') ? _i(j['bright']) : 100,
        demo: j['demo'] == true,
        rider: (j['rider'] ?? '').toString(),
      );

  /// Build a partial-update map for the writable fields only. Pass just what you
  /// want to change — the firmware applies partial updates.
  static Map<String, dynamic> writeJson({
    bool? mph,
    String? theme,
    int? batterySeries,
    int? profile,
    double? packAh,
    double? stopCellV,
    int? whPerMile,
    int? brightness,
    bool? demo,
    String? rider,
  }) {
    final m = <String, dynamic>{};
    if (mph != null) m['mph'] = mph;
    if (theme != null) m['theme'] = theme;
    if (batterySeries != null) m['bat_s'] = batterySeries;
    if (profile != null) m['profile'] = profile;
    if (packAh != null) m['packAh'] = packAh;
    if (stopCellV != null) m['stopCell'] = stopCellV;
    if (whPerMile != null) m['whmi'] = whPerMile;
    if (brightness != null) m['bright'] = brightness;
    if (demo != null) m['demo'] = demo;
    if (rider != null) m['rider'] = rider;
    return m;
  }
}

double _d(dynamic v) => v is num ? v.toDouble() : 0.0;
int _i(dynamic v) => v is num ? v.toInt() : 0;

enum DeviceConnectionState { disconnected, connecting, connected, disconnecting }

abstract class Esk8Device {
  String get name;
  Stream<DeviceConnectionState> get connectionState;
  bool get isReady;

  Future<void> connect();
  Future<void> disconnect();
  
  Stream<Telemetry> telemetry();
  
  Future<BoardSettings?> readSettings();
  Future<void> writeSettings(Map<String, dynamic> partial);
  Future<void> sendCommand(String command);
}

