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

/// Telemetry payload (spec §3): one JSON object pushed at 5 Hz. Speed/range/max
/// are in whatever unit the board is configured for ([Settings.mph]).
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
      );
}

/// Board configuration (spec §4). `poles`, `wheel`, and `gear` are READ-ONLY —
/// they're derived from the selected wheel preset; write [profile] to switch
/// presets. Writable fields: [mph], [theme], [batterySeries], [profile].
class BoardSettings {
  final bool mph;
  final String theme;
  final int poles; // read-only
  final int wheelMm; // read-only
  final double gear; // read-only
  final int batterySeries; // bat_s
  final int profile;

  const BoardSettings({
    required this.mph,
    required this.theme,
    required this.poles,
    required this.wheelMm,
    required this.gear,
    required this.batterySeries,
    required this.profile,
  });

  factory BoardSettings.fromJson(Map<String, dynamic> j) => BoardSettings(
        mph: j['mph'] == true,
        theme: (j['theme'] ?? '').toString(),
        poles: _i(j['poles']),
        wheelMm: _i(j['wheel']),
        gear: _d(j['gear']),
        batterySeries: _i(j['bat_s']),
        profile: _i(j['profile']),
      );

  /// Build a partial-update map for the writable fields only. Pass just what you
  /// want to change — the firmware applies partial updates.
  static Map<String, dynamic> writeJson({
    bool? mph,
    String? theme,
    int? batterySeries,
    int? profile,
  }) {
    final m = <String, dynamic>{};
    if (mph != null) m['mph'] = mph;
    if (theme != null) m['theme'] = theme;
    if (batterySeries != null) m['bat_s'] = batterySeries;
    if (profile != null) m['profile'] = profile;
    return m;
  }
}

double _d(dynamic v) => v is num ? v.toDouble() : 0.0;
int _i(dynamic v) => v is num ? v.toInt() : 0;
