/// ESK8OS companion BLE contract — mirrors `docs/companion_api_spec.md` in the
/// firmware repo (Esk8OS). Pure Dart (no plugin imports) so it stays testable.
library;

/// Custom companion service + characteristic UUIDs (spec §2).
class Esk8Uuids {
  static const String service = '5043697a-0000-4682-93cb-33bb0a149f7e';
  static const String telemetry =
      '5043697a-0001-4682-93cb-33bb0a149f7e'; // NOTIFY
  static const String settings =
      '5043697a-0002-4682-93cb-33bb0a149f7e'; // READ | WRITE
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
  static const String bridgeExit = 'BRIDGE_EXIT';
  static const String bridgeToggle = 'BRIDGE_TOGGLE';
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
  final bool live; // live: current telemetry fields are from demo or VESC
  final bool vescConnected; // vesc: recent VESC packet received
  final bool? mph; // mph: board display units for this telemetry frame
  final double speed; // spd
  final int battery; // bat (%)
  final double volts; // v
  final int watts; // w
  final int motorTempC; // mtr_t
  final int escTempC; // esc_t
  final double range; // rng
  final double maxSpeed; // max_s
  final double wattHours; // wh
  // --- fw 0.9.0 payload expansion ---
  final int batteryTempC; // btemp
  final double batteryAmps; // bata
  final double motorAmps; // mota
  final int duty; // duty (%)
  final int peakWatts; // pkw (live peak-hold W — "peak now")
  final int maxWattsSession; // mpw (session max W — "max ride")
  final double regenWh; // whr
  final double minVolts; // minv
  final double avgSpeed; // avs
  final double trip; // trip (display unit)
  final double odometer; // odo (display unit)
  final double estRange; // est (display unit, full charge)
  final double limpRange; // lrng (display unit, emergency/limp floor)
  final double limpEstRange; // lest (display unit, full charge to limp floor)
  final double efficiency; // eff (Wh/mi or Wh/km)
  final double
  minLoadedVolts; // minvl (lowest loaded/discharge voltage this session)
  final double maxBatteryAmps; // mba
  final double cellVolts; // cellv (loaded V/cell)
  final int rangeWarning; // rwarn: 0 ok, 1 turn-home, 2 sag, 3 limp
  final int sagEvents; // sagc
  final int homeVoltageSeconds; // thome
  final int limpVoltageSeconds; // tlimp
  final int fault; // fault (VESC fault code, 0 = none)
  final int rideSeconds; // rtime (board uptime this boot, s)
  final int
  tripMovingSeconds; // tmov (trip moving-time, s rolling) — board-authoritative
  // --- remote input + diagnostics ---
  final double
  throttle; // ppm: decoded remote throttle -1..1 (<0 brake, >0 accel)
  final bool remoteConnected; // ppmok: valid remote signal present
  final int lastFault; // lfault: most recent VESC fault, latched
  final bool slaveOnline; // slave: 2nd motor responding over CAN
  final double masterMotorAmps; // m1a
  final double slaveMotorAmps; // m2a
  final String vescFw; // fw: VESC firmware version "major.minor"

  const Telemetry({
    this.live = true,
    this.vescConnected = true,
    this.mph,
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
    this.maxWattsSession = 0,
    this.regenWh = 0.0,
    this.minVolts = 0.0,
    this.avgSpeed = 0.0,
    this.trip = 0.0,
    this.odometer = 0.0,
    this.estRange = 0.0,
    this.limpRange = 0.0,
    this.limpEstRange = 0.0,
    this.efficiency = 0.0,
    this.minLoadedVolts = 0.0,
    this.maxBatteryAmps = 0.0,
    this.cellVolts = 0.0,
    this.rangeWarning = 0,
    this.sagEvents = 0,
    this.homeVoltageSeconds = 0,
    this.limpVoltageSeconds = 0,
    this.fault = 0,
    this.rideSeconds = 0,
    this.tripMovingSeconds = 0,
    this.throttle = 0.0,
    this.remoteConnected = false,
    this.lastFault = 0,
    this.slaveOnline = false,
    this.masterMotorAmps = 0.0,
    this.slaveMotorAmps = 0.0,
    this.vescFw = '',
  });

  factory Telemetry.fromJson(Map<String, dynamic> j) => Telemetry(
    live: j.containsKey('live') ? j['live'] == true : true,
    vescConnected: j.containsKey('vesc') ? j['vesc'] == true : true,
    mph: j.containsKey('mph') ? j['mph'] == true : null,
    speed: _d(j['spd']),
    battery: _i(j['bat']),
    volts: _d(j['v']),
    watts: _i(j['w']),
    motorTempC: _i(j['mtr_t']),
    escTempC: _i(j['esc_t']),
    range: _d(j['rng']),
    maxSpeed: _d(j['max_s']),
    wattHours: _d(j['wh']),
    batteryTempC: _i(j['btemp']),
    batteryAmps: _d(j['bata']),
    motorAmps: _d(j['mota']),
    duty: _i(j['duty']),
    peakWatts: _i(j['pkw']),
    maxWattsSession: _i(j['mpw']),
    regenWh: _d(j['whr']),
    minVolts: _d(j['minv']),
    avgSpeed: _d(j['avs']),
    trip: _d(j['trip']),
    odometer: _d(j['odo']),
    estRange: _d(j['est']),
    limpRange: _d(j['lrng']),
    limpEstRange: _d(j['lest']),
    efficiency: _d(j['eff']),
    minLoadedVolts: _d(j['minvl']),
    maxBatteryAmps: _d(j['mba']),
    cellVolts: _d(j['cellv']),
    rangeWarning: _i(j['rwarn']),
    sagEvents: _i(j['sagc']),
    homeVoltageSeconds: _i(j['thome']),
    limpVoltageSeconds: _i(j['tlimp']),
    fault: _i(j['fault']),
    rideSeconds: _i(j['rtime']),
    tripMovingSeconds: _i(j['tmov']),
    throttle: _d(j['ppm']),
    remoteConnected: j['ppmok'] == true,
    lastFault: _i(j['lfault']),
    slaveOnline: j['slave'] == true,
    masterMotorAmps: _d(j['m1a']),
    slaveMotorAmps: _d(j['m2a']),
    vescFw: (j['fw'] ?? '').toString(),
  );
}

/// Board configuration (spec §4). `poles`, `wheel`, and `gear` are READ-ONLY —
/// they're derived from the selected wheel preset; write [profile] to switch
/// presets. Writable fields: [mph], [theme], [batterySeries], [profile],
/// [packAh], [stopCellV], [whPerMile], [brightness], [demo], [hudFace],
/// [batteryFocus]. Newer fields default sensibly when read from older boards.
class BoardSettings {
  final String hardware; // hw: tdisplay-s3 | esp32s3-oled | esp32s3-headless
  final String display; // display: tft | oled | none
  final String ui; // ui: full | mini | headless
  final bool hasButtons; // buttons
  final bool mph;
  final String theme;
  final int poles; // read-only
  final int wheelMm; // read-only
  final double gear; // read-only
  final int batterySeries; // bat_s
  final int profile;
  // --- fw 0.9.0 ---
  final double packAh; // packAh
  final double homeCellV; // homeCell
  final double stopCellV; // stopCell
  final double whPerMile; // whmi
  final int brightness; // bright (%)
  final bool statusRgb; // rgb
  final bool oledInvert; // oled_inv
  final bool demo; // demo
  final String rider; // rider
  final String hudFace; // hud: speed | battery | volts | watts | safety
  final String batteryFocus; // bfocus: pct | volts
  final String deviceName; // name: BLE advertised name (settable; distinguishes boards)
  final int vehicleType; // vtype: 0=skate 1=ebike 2=scooter 3=moped 4=car 5=other

  const BoardSettings({
    this.hardware = 'tdisplay-s3',
    this.display = 'tft',
    this.ui = 'full',
    this.hasButtons = true,
    required this.mph,
    required this.theme,
    required this.poles,
    required this.wheelMm,
    required this.gear,
    required this.batterySeries,
    required this.profile,
    this.packAh = 0.0,
    this.homeCellV = 0.0,
    this.stopCellV = 0.0,
    this.whPerMile = 0.0,
    this.brightness = 100,
    this.statusRgb = true,
    this.oledInvert = false,
    this.demo = false,
    this.rider = '',
    this.hudFace = 'speed',
    this.batteryFocus = 'pct',
    this.deviceName = 'ESK8-BLE',
    this.vehicleType = 0,
  });

  factory BoardSettings.fromJson(Map<String, dynamic> j) => BoardSettings(
    hardware: (j['hw'] ?? 'tdisplay-s3').toString(),
    display: _settingString(j['display'], {'tft', 'oled', 'none'}, 'tft'),
    ui: _settingString(j['ui'], {'full', 'mini', 'headless'}, 'full'),
    hasButtons: j.containsKey('buttons') ? j['buttons'] == true : true,
    mph: j['mph'] == true,
    theme: (j['theme'] ?? '').toString(),
    poles: _i(j['poles']),
    wheelMm: _i(j['wheel']),
    gear: _d(j['gear']),
    batterySeries: _i(j['bat_s']),
    profile: _i(j['profile']),
    packAh: _d(j['packAh']),
    homeCellV: _d(j['homeCell']),
    stopCellV: _d(j['stopCell']),
    whPerMile: _d(j['whmi']),
    brightness: j.containsKey('bright') ? _i(j['bright']) : 100,
    statusRgb: j.containsKey('rgb') ? j['rgb'] == true : true,
    oledInvert: j['oled_inv'] == true,
    demo: j['demo'] == true,
    rider: (j['rider'] ?? '').toString(),
    hudFace: _settingString(j['hud'], {
      'speed',
      'battery',
      'volts',
      'watts',
      'safety',
    }, 'speed'),
    batteryFocus: _settingString(j['bfocus'], {'pct', 'volts'}, 'pct'),
    deviceName: (j['name'] ?? 'ESK8-BLE').toString(),
    vehicleType: _i(j['vtype']),
  );

  /// Build a partial-update map for the writable fields only. Pass just what you
  /// want to change — the firmware applies partial updates.
  static Map<String, dynamic> writeJson({
    bool? mph,
    String? theme,
    int? batterySeries,
    int? profile,
    double? packAh,
    double? homeCellV,
    double? stopCellV,
    double? whPerMile,
    int? brightness,
    bool? statusRgb,
    bool? oledInvert,
    bool? demo,
    String? rider,
    String? hudFace,
    String? batteryFocus,
    String? deviceName,
    int? vehicleType,
  }) {
    final m = <String, dynamic>{};
    if (mph != null) m['mph'] = mph;
    if (theme != null) m['theme'] = theme;
    if (batterySeries != null) m['bat_s'] = batterySeries;
    if (profile != null) m['profile'] = profile;
    if (packAh != null) m['packAh'] = packAh;
    if (homeCellV != null) m['homeCell'] = homeCellV;
    if (stopCellV != null) m['stopCell'] = stopCellV;
    if (whPerMile != null) m['whmi'] = whPerMile;
    if (brightness != null) m['bright'] = brightness;
    if (statusRgb != null) m['rgb'] = statusRgb;
    if (oledInvert != null) m['oled_inv'] = oledInvert;
    if (demo != null) m['demo'] = demo;
    if (rider != null) m['rider'] = rider;
    if (hudFace != null) m['hud'] = hudFace;
    if (batteryFocus != null) m['bfocus'] = batteryFocus;
    if (deviceName != null) m['name'] = deviceName;
    if (vehicleType != null) m['vtype'] = vehicleType;
    return m;
  }

  BoardSettings copyWith({bool? mph}) => BoardSettings(
    hardware: hardware,
    display: display,
    ui: ui,
    hasButtons: hasButtons,
    mph: mph ?? this.mph,
    theme: theme,
    poles: poles,
    wheelMm: wheelMm,
    gear: gear,
    batterySeries: batterySeries,
    profile: profile,
    packAh: packAh,
    homeCellV: homeCellV,
    stopCellV: stopCellV,
    whPerMile: whPerMile,
    brightness: brightness,
    statusRgb: statusRgb,
    oledInvert: oledInvert,
    demo: demo,
    rider: rider,
    hudFace: hudFace,
    batteryFocus: batteryFocus,
    deviceName: deviceName,
    vehicleType: vehicleType,
  );
}

double _d(dynamic v) => v is num ? v.toDouble() : 0.0;
int _i(dynamic v) => v is num ? v.toInt() : 0;
String _settingString(dynamic v, Set<String> allowed, String fallback) {
  final s = (v ?? '').toString().toLowerCase();
  return allowed.contains(s) ? s : fallback;
}

enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

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
