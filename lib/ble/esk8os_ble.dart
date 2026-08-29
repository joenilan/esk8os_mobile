/// ESK8OS companion BLE contract — mirrors `docs/companion_api_spec.md` in the
/// firmware repo (Esk8OS). Pure Dart (no plugin imports) so it stays testable.
library;

import 'dart:convert';

/// Custom companion service + characteristic UUIDs (spec §2).
class Esk8Uuids {
  static const String service = '5043697a-0000-4682-93cb-33bb0a149f7e';
  static const String telemetry =
      '5043697a-0001-4682-93cb-33bb0a149f7e'; // NOTIFY (5 Hz core)
  static const String settings =
      '5043697a-0002-4682-93cb-33bb0a149f7e'; // READ | WRITE
  static const String command = '5043697a-0003-4682-93cb-33bb0a149f7e'; // WRITE

  /// 1 Hz session/trip stats (fw 0.9.4+). Older firmware sends everything on
  /// [telemetry]; the merge in CompanionDevice handles both.
  static const String session =
      '5043697a-0004-4682-93cb-33bb0a149f7e'; // NOTIFY

  /// VESC-read base config + per-value provenance (fw 0.10.1+, spec §2b).
  static const String baseConf = '5043697a-0005-4682-93cb-33bb0a149f7e'; // READ

  /// Daly BMS pack + per-cell (spec §2c). Present only on BMS-build boards;
  /// absent = no BMS integration, so the app hides the pack view.
  static const String bms =
      '5043697a-0006-4682-93cb-33bb0a149f7e'; // NOTIFY 1 Hz
}

/// The board's three-tier config surface (characteristic 0005, fw 0.10.1+):
/// what the ESC's own mcconf says (base tier) and which tier each effective
/// settings value currently comes from. Read-only.
class BaseConfig {
  final bool valid; // false = no firmware-matched mcconf ever parsed
  final int cells;
  final double packAh;
  final double cutStartV, cutEndV; // pack volts (VESC ramps between them)
  final int poles;
  final double gearRatio; // wheel:motor, e.g. 72/16 = 4.5
  final int wheelMm;
  final double motorAmpMax, battAmpMax, battAmpRegen;

  /// Export AP actually up (moved here from settings, fw 0.10.9+). The console
  /// page polls this after WIFI_EXPORT_START to know the network is really up.
  final bool wifiOn;

  /// Per-field source: 'r' rider override, 'v' VESC base, 'd' generic default.
  /// Keys: cells, ah, home, stop, whmi, wheel.
  final Map<String, String> src;

  const BaseConfig({
    required this.valid,
    this.wifiOn = false,
    this.cells = 0,
    this.packAh = 0,
    this.cutStartV = 0,
    this.cutEndV = 0,
    this.poles = 0,
    this.gearRatio = 0,
    this.wheelMm = 0,
    this.motorAmpMax = 0,
    this.battAmpMax = 0,
    this.battAmpRegen = 0,
    this.src = const {},
  });

  factory BaseConfig.fromJson(Map<String, dynamic> j) => BaseConfig(
    valid: j['valid'] == true,
    wifiOn: j['wifiOn'] == true,
    cells: (j['cells'] as num?)?.toInt() ?? 0,
    packAh: (j['ah'] as num?)?.toDouble() ?? 0,
    cutStartV: (j['cutS'] as num?)?.toDouble() ?? 0,
    cutEndV: (j['cutE'] as num?)?.toDouble() ?? 0,
    poles: (j['poles'] as num?)?.toInt() ?? 0,
    gearRatio: (j['gear'] as num?)?.toDouble() ?? 0,
    wheelMm: (j['wheel'] as num?)?.toInt() ?? 0,
    motorAmpMax: (j['motA'] as num?)?.toDouble() ?? 0,
    battAmpMax: (j['batA'] as num?)?.toDouble() ?? 0,
    battAmpRegen: (j['regA'] as num?)?.toDouble() ?? 0,
    src: (j['src'] is Map)
        ? (j['src'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
        : const {},
  );

  /// Human label for a src code, for chips next to settings fields.
  static String sourceLabel(String? code) => switch (code) {
    'r' => 'YOUR OVERRIDE',
    'v' => 'FROM VESC',
    _ => 'DEFAULT',
  };
}

/// Daly BMS snapshot (characteristic 0006, spec §2c). The per-cell voltages the
/// VESC can't provide — the reason to read the BMS at all. Only BMS-build boards
/// send it; [Esk8Device.hasBms] tells the app whether to show the pack view.
///
/// A stale cell (its 0x95 frame dropped) keeps its old mV but its [cellStale]
/// bit is set — render it as unknown, never as a live reading.
class BmsData {
  static const int freshnessPack = 0;
  static const int freshnessMinMaxVoltage = 1;
  static const int freshnessMinMaxTemperature = 2;
  static const int freshnessMos = 3;
  static const int freshnessStatus = 4;
  static const int freshnessCells = 5;
  static const int freshnessTemperatures = 6;
  static const int freshnessBalance = 7;
  static const int freshnessFaults = 8;
  static const int allFreshMask = 0x1ff;

  final bool link; // link: BMS answered within the staleness window
  /// `fv`; null means legacy firmware where link-level freshness is authoritative.
  final int? freshnessMask;

  /// `al`; null means an older unclassified `flt` payload.
  final int? alarmLevel;

  /// `fb`; raw seven 0x98 bytes. Null when legacy firmware omitted the evidence.
  final String? rawFaultBytes;

  /// `lfb` / `lfa`; most recent non-zero 0x98 frame this board boot and its age.
  final String? lastRawFaultBytes;
  final int? lastFaultAgeSec;

  /// `oc` / `oca`; the pack's own read-only discharge-overcurrent settings as
  /// `[warning_A, protection1_A, protection1_delay_ms, protection2_A,
  /// protection2_delay_ms]` (CRC-validated Modbus reads of DALY 0x145..0x149)
  /// plus the age of that read. Null means the read has not succeeded — never
  /// invent defaults. Diagnostics only; the firmware exposes no BMS write path.
  final double? ocWarnA;
  final double? ocProtect1A;
  final int? ocProtect1DelayMs;
  final double? ocProtect2A;
  final int? ocProtect2DelayMs;
  final int? ocAgeSec;

  final double packVolts; // pv
  final double current; // cur: + charging, - discharging
  final int soc; // soc (%)
  final double remainingAh; // rah
  final int cycles; // cyc
  final int cellCount; // n
  final List<int> cellsMv; // cv: per-cell millivolts, index 0 = cell 1
  final int balMask; // bal: bit c set = cell (c+1) balancing
  final int staleMask; // st: bit c set = cell (c+1) mV is stale
  final int minMv, minCell; // mn / mnc (1-based)
  final int maxMv, maxCell; // mx / mxc (1-based)
  final int deltaMv; // dv: max - min, the imbalance to watch
  final List<int> temps; // t (°C)
  final int tempMin, tempMax; // tmn / tmx
  final bool chargeMos; // cmos
  final bool dischargeMos; // dmos
  final bool fault; // flt

  const BmsData({
    this.link = false,
    this.freshnessMask,
    this.alarmLevel,
    this.rawFaultBytes,
    this.lastRawFaultBytes,
    this.lastFaultAgeSec,
    this.ocWarnA,
    this.ocProtect1A,
    this.ocProtect1DelayMs,
    this.ocProtect2A,
    this.ocProtect2DelayMs,
    this.ocAgeSec,
    this.packVolts = 0,
    this.current = 0,
    this.soc = 0,
    this.remainingAh = 0,
    this.cycles = 0,
    this.cellCount = 0,
    this.cellsMv = const [],
    this.balMask = 0,
    this.staleMask = 0,
    this.minMv = 0,
    this.minCell = 0,
    this.maxMv = 0,
    this.maxCell = 0,
    this.deltaMv = 0,
    this.temps = const [],
    this.tempMin = 0,
    this.tempMax = 0,
    this.chargeMos = false,
    this.dischargeMos = false,
    this.fault = false,
  });

  bool groupFresh(int bit) =>
      link && (freshnessMask == null || (freshnessMask! & (1 << bit)) != 0);

  bool get packFresh => groupFresh(freshnessPack);
  bool get minMaxVoltageFresh => groupFresh(freshnessMinMaxVoltage);
  bool get mosFresh => groupFresh(freshnessMos);
  bool get statusFresh => groupFresh(freshnessStatus);
  bool get cellsFresh => groupFresh(freshnessCells);
  bool get temperaturesFresh =>
      groupFresh(freshnessTemperatures) ||
      groupFresh(freshnessMinMaxTemperature);
  bool get balanceFresh => groupFresh(freshnessBalance);
  bool get faultsFresh => groupFresh(freshnessFaults);

  /// Normalized severity for presentation. Legacy `flt:true` remains a serious
  /// unclassified alert; an explicitly stale fault group is level 3.
  int get effectiveAlarmLevel {
    if (!link) return 3;
    if (freshnessMask != null && !faultsFresh) return 3;
    final level = alarmLevel;
    if (level == null) return fault ? 2 : 0;
    return level >= 0 && level <= 3 ? level : 2;
  }

  static String? faultLabel(String? raw) {
    if (raw == null || raw.length != 14) return null;
    final byte2 = int.tryParse(raw.substring(4, 6), radix: 16);
    if (byte2 == null) return null;
    if ((byte2 & 0x08) != 0) return 'DISCHARGE OVERCURRENT PROTECTION';
    if ((byte2 & 0x04) != 0) return 'DISCHARGE OVERCURRENT WARNING';
    return null;
  }

  String get alarmLabel {
    final exact = faultLabel(rawFaultBytes);
    if (exact != null) return exact;
    return switch (effectiveAlarmLevel) {
      0 => 'OK',
      1 => 'WARNING',
      2 => alarmLevel == null ? 'UNCLASSIFIED ALERT' : 'ALERT',
      _ => 'FAULT DATA STALE',
    };
  }

  String? get lastFaultLabel => faultLabel(lastRawFaultBytes);

  /// True once the board has published a verified discharge-O/C settings read.
  bool get ocSettingsValid => ocWarnA != null;

  bool cellBalancing(int i) => balanceFresh && (balMask & (1 << i)) != 0;
  bool cellStale(int i) => !cellsFresh || (staleMask & (1 << i)) != 0;

  /// A mathematical minimum is normal. Only call it weak once the pack spread
  /// reaches the firmware's meaningful 50 mV threshold.
  bool cellWeak(int i) =>
      minMaxVoltageFresh &&
      !cellStale(i) &&
      (i + 1) == minCell &&
      deltaMv >= 50;

  /// Compact wire-compatible representation used when a BMS snapshot is stored
  /// alongside a 1 Hz trip row. Keeping the characteristic's field names makes
  /// backups self-describing and lets future readers reuse [BmsData.fromJson].
  Map<String, dynamic> toJson() {
    if (!link) return const {'link': false};
    return {
      'link': true,
      if (freshnessMask != null) 'fv': freshnessMask,
      if (alarmLevel != null) 'al': alarmLevel,
      'pv': packVolts,
      'cur': current,
      'soc': soc,
      'rah': remainingAh,
      'cyc': cycles,
      'n': cellCount,
      'cv': cellsMv,
      'bal': balMask,
      'st': staleMask,
      'mn': minMv,
      'mnc': minCell,
      'mx': maxMv,
      'mxc': maxCell,
      'dv': deltaMv,
      't': temps,
      'tmn': tempMin,
      'tmx': tempMax,
      'cmos': chargeMos,
      'dmos': dischargeMos,
      'flt': fault,
      if (rawFaultBytes != null) 'fb': rawFaultBytes,
      if (lastRawFaultBytes != null) 'lfb': lastRawFaultBytes,
      if (lastFaultAgeSec != null) 'lfa': lastFaultAgeSec,
      if (ocSettingsValid) ...{
        'oc': [
          ocWarnA,
          ocProtect1A,
          ocProtect1DelayMs,
          ocProtect2A,
          ocProtect2DelayMs,
        ],
        if (ocAgeSec != null) 'oca': ocAgeSec,
      },
    };
  }

  String toStorageJson() => jsonEncode(toJson());

  static BmsData? tryFromStorageJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? BmsData.fromJson(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  factory BmsData.fromJson(Map<String, dynamic> j) {
    // `oc` is [warnA, p1A, p1ms, p2A, p2ms]; all five entries must be numeric
    // before any of it is trusted, so a malformed array degrades to "not
    // provided" instead of half-validated settings.
    double? ocWarn, ocP1a, ocP2a;
    int? ocP1ms, ocP2ms;
    if (j['oc'] is List) {
      final raw = j['oc'] as List;
      if (raw.length == 5 && raw.every((e) => e is num)) {
        ocWarn = (raw[0] as num).toDouble();
        ocP1a = (raw[1] as num).toDouble();
        ocP1ms = (raw[2] as num).toInt();
        ocP2a = (raw[3] as num).toDouble();
        ocP2ms = (raw[4] as num).toInt();
      }
    }
    return BmsData(
      link: j['link'] == true,
      freshnessMask: j['fv'] is num ? (j['fv'] as num).toInt() : null,
      alarmLevel: j['al'] is num ? (j['al'] as num).toInt() : null,
      rawFaultBytes: j['fb'] is String ? j['fb'] as String : null,
      lastRawFaultBytes: j['lfb'] is String ? j['lfb'] as String : null,
      lastFaultAgeSec: j['lfa'] is num ? (j['lfa'] as num).toInt() : null,
      ocWarnA: ocWarn,
      ocProtect1A: ocP1a,
      ocProtect1DelayMs: ocP1ms,
      ocProtect2A: ocP2a,
      ocProtect2DelayMs: ocP2ms,
      ocAgeSec: j['oca'] is num ? (j['oca'] as num).toInt() : null,
      packVolts: _d(j['pv']),
      current: _d(j['cur']),
      soc: _i(j['soc']),
      remainingAh: _d(j['rah']),
      cycles: _i(j['cyc']),
      cellCount: _i(j['n']),
      cellsMv: (j['cv'] is List)
          ? (j['cv'] as List).map((e) => (e as num).toInt()).toList()
          : const [],
      balMask: _i(j['bal']),
      staleMask: _i(j['st']),
      minMv: _i(j['mn']),
      minCell: _i(j['mnc']),
      maxMv: _i(j['mx']),
      maxCell: _i(j['mxc']),
      deltaMv: _i(j['dv']),
      temps: (j['t'] is List)
          ? (j['t'] as List).map((e) => (e as num).toInt()).toList()
          : const [],
      tempMin: _i(j['tmn']),
      tempMax: _i(j['tmx']),
      chargeMos: j['cmos'] == true,
      dischargeMos: j['dmos'] == true,
      fault: j['flt'] == true,
    );
  }
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

  /// fw 0.9.5+: wipe the board's learned range calibration (pack resistance,
  /// deliverable energy, Wh/mi) so it re-learns from scratch — e.g. after a
  /// battery swap.
  static const String calReset = 'CAL_RESET';

  /// Remove a persisted board-side rider override so the VESC/default tier is
  /// authoritative again (firmware command `UNSET:<key>`).
  static String unset(String key) => 'UNSET:$key';
}

/// The board's WiFi AP for the hybrid log/OTA transfer (spec §6). The board
/// raises this after WIFI_EXPORT_START is confirmed on-board; the user joins it
/// and the app fetches over HTTP. The password is per-device since fw 0.9.4
/// (read it from [BoardSettings.wifiPass]); [legacyPassword] only matches
/// older firmware that still ships the fixed key.
class Esk8WifiExport {
  static const String ssid = 'ESK8-BRIDGE';
  static const String legacyPassword = 'esk8bridge';
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
  static const Set<String> batterySources = {
    'none',
    'vesc',
    'daly',
    'fused',
    'demo',
  };

  final bool live; // live: fresh drivetrain fields are from demo or VESC
  final bool vescConnected; // vesc: recent VESC packet received
  final bool batteryLive; // blive: independent fresh battery presentation
  final String batterySource; // bsrc: none | vesc | daly | fused | demo
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
  final double maxMotorAmps; // mpa (session peak motor pull)
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
    bool? batteryLive,
    String? batterySource,
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
    this.maxMotorAmps = 0.0,
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
  }) : batteryLive = batteryLive ?? live,
       batterySource = batterySource ?? (live ? 'vesc' : 'none');

  String get batterySourceLabel => switch (batterySource) {
    'daly' => 'BMS',
    'fused' => 'VESC + BMS',
    'demo' => 'DEMO',
    'vesc' => 'VESC',
    _ => 'NONE',
  };

  factory Telemetry.fromJson(Map<String, dynamic> j) {
    final live = j.containsKey('live') ? j['live'] == true : true;
    final batteryLive = j.containsKey('blive') ? j['blive'] == true : live;
    final rawSource = j['bsrc']?.toString().toLowerCase();
    final batterySource =
        rawSource != null && batterySources.contains(rawSource)
        ? rawSource
        : (live ? 'vesc' : 'none');
    return Telemetry(
      live: live,
      vescConnected: j.containsKey('vesc') ? j['vesc'] == true : true,
      batteryLive: batteryLive,
      batterySource: batterySource,
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
      maxMotorAmps: _d(j['mpa']),
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
  final bool
  hasColorTheme; // board sends a color theme (TFT only; OLED is mono, headless has none)
  final int poles; // read-only
  final int
  wheelMm; // effective diameter used for speed/distance (preset or override)
  final int
  wheelOverrideMm; // wheelmm: rider calibration, 0 = using the preset's nominal
  final double gear; // read-only
  final int batterySeries; // bat_s
  final int profile;
  // --- fw 0.9.0 ---
  final double packAh; // packAh
  final double homeCellV; // homeCell (resting floor you set)
  final double stopCellV; // stopCell (resting floor you set)
  final double
  homeEffCellV; // homeEff: sag-lifted LOADED floor the estimate actually stops at
  final double stopEffCellV; // stopEff: sag-lifted LOADED limp floor
  final double whPerMile; // whmi
  final int brightness; // bright (%)
  final bool statusRgb; // rgb
  final bool oledInvert; // oled_inv
  final bool demo; // demo
  final String rider; // rider
  final String hudFace; // hud: speed | battery | volts | watts | safety
  final String batteryFocus; // bfocus: pct | volts
  final String
  deviceName; // name: BLE advertised name (settable; distinguishes boards)
  final int
  vehicleType; // vtype: 0=skate 1=ebike 2=scooter 3=moped 4=car 5=custom 6=euc 7=onewheel
  final String vehicleLabel; // vlabel: rider-typed name for a custom vehicle
  final int vehicleCustomIcon; // vicon: icon index for a custom vehicle
  // Read-only AP credentials for the log/OTA transfer. Older firmware doesn't
  // send these; the defaults match its fixed legacy credentials.
  final String wifiSsid; // wifiSsid
  final String wifiPass; // wifiPass (per-device since fw 0.9.4)
  // Read-only on-board adaptive battery calibration (fw 0.9.5+). When
  // [hasBoardCal] the BOARD learns its own range model while riding — the app
  // must not push a learned whmi over it (manual writes stay allowed).
  final bool hasBoardCal; // calR present in the settings JSON
  final int calPackROhm; // calR: learned pack internal resistance, mohm
  final double calTypicalAmps; // calA: typical riding battery draw, A
  final double calWhPerMile; // calWhmi: learned consumption (0 = not yet)
  final int calPackWh; // calWh: measured deliverable pack Wh (0 = not yet)
  // ESK8OS firmware version string, e.g. "v0.9.5 9fc0918" (fw 0.9.5+; empty on
  // older firmware). Shown on the app's About card.
  final String firmwareVersion; // fwv
  // fw 0.9.5+ only reports "rgb" when the build has a controllable status LED
  // (headless/OLED devkits). Absent -> hide the toggle in the app.
  final bool hasStatusRgb;

  const BoardSettings({
    this.hardware = 'tdisplay-s3',
    this.display = 'tft',
    this.ui = 'full',
    this.hasButtons = true,
    required this.mph,
    required this.theme,
    this.hasColorTheme = false,
    required this.poles,
    required this.wheelMm,
    this.wheelOverrideMm = 0,
    required this.gear,
    required this.batterySeries,
    required this.profile,
    this.packAh = 0.0,
    this.homeCellV = 0.0,
    this.stopCellV = 0.0,
    this.homeEffCellV = 0.0,
    this.stopEffCellV = 0.0,
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
    this.vehicleLabel = '',
    this.vehicleCustomIcon = 0,
    this.wifiSsid = Esk8WifiExport.ssid,
    this.wifiPass = Esk8WifiExport.legacyPassword,
    this.hasBoardCal = false,
    this.calPackROhm = 0,
    this.calTypicalAmps = 0.0,
    this.calWhPerMile = 0.0,
    this.calPackWh = 0,
    this.firmwareVersion = '',
    this.hasStatusRgb = true,
  });

  factory BoardSettings.fromJson(Map<String, dynamic> j) => BoardSettings(
    hardware: (j['hw'] ?? 'tdisplay-s3').toString(),
    display: _settingString(j['display'], {'tft', 'oled', 'none'}, 'tft'),
    ui: _settingString(j['ui'], {'full', 'mini', 'headless'}, 'full'),
    hasButtons: j.containsKey('buttons') ? j['buttons'] == true : true,
    mph: j['mph'] == true,
    theme: (j['theme'] ?? '').toString(),
    hasColorTheme: (j['theme'] ?? '').toString().isNotEmpty,
    poles: _i(j['poles']),
    wheelMm: _i(j['wheel']),
    wheelOverrideMm: _i(j['wheelmm']),
    gear: _d(j['gear']),
    batterySeries: _i(j['bat_s']),
    profile: _i(j['profile']),
    packAh: _d(j['packAh']),
    homeCellV: _d(j['homeCell']),
    stopCellV: _d(j['stopCell']),
    homeEffCellV: _d(j['homeEff']),
    stopEffCellV: _d(j['stopEff']),
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
    vehicleLabel: (j['vlabel'] ?? '').toString(),
    vehicleCustomIcon: _i(j['vicon']),
    wifiSsid: (j['wifiSsid'] ?? Esk8WifiExport.ssid).toString(),
    wifiPass: (j['wifiPass'] ?? Esk8WifiExport.legacyPassword).toString(),
    hasBoardCal: j.containsKey('calR'),
    calPackROhm: _i(j['calR']),
    calTypicalAmps: _d(j['calA']),
    calWhPerMile: _d(j['calWhmi']),
    calPackWh: _i(j['calWh']),
    firmwareVersion: (j['fwv'] ?? '').toString(),
    // Pre-0.9.5 firmware always sent rgb; keep the toggle for it. On 0.9.5+
    // the key's absence means "this hardware has no LED".
    hasStatusRgb: j.containsKey('rgb') || !j.containsKey('fwv'),
  );

  /// Build a partial-update map for the writable fields only. Pass just what you
  /// want to change — the firmware applies partial updates.
  static Map<String, dynamic> writeJson({
    bool? mph,
    String? theme,
    int? batterySeries,
    int? profile,
    int? wheelOverrideMm,
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
    String? vehicleLabel,
    int? vehicleCustomIcon,
  }) {
    final m = <String, dynamic>{};
    if (mph != null) m['mph'] = mph;
    if (theme != null) m['theme'] = theme;
    if (batterySeries != null) m['bat_s'] = batterySeries;
    if (profile != null) m['profile'] = profile;
    if (wheelOverrideMm != null) m['wheelmm'] = wheelOverrideMm;
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
    if (vehicleLabel != null) m['vlabel'] = vehicleLabel;
    if (vehicleCustomIcon != null) m['vicon'] = vehicleCustomIcon;
    return m;
  }

  BoardSettings copyWith({bool? mph}) => BoardSettings(
    hardware: hardware,
    display: display,
    ui: ui,
    hasButtons: hasButtons,
    mph: mph ?? this.mph,
    theme: theme,
    hasColorTheme: hasColorTheme,
    poles: poles,
    wheelMm: wheelMm,
    wheelOverrideMm: wheelOverrideMm,
    gear: gear,
    batterySeries: batterySeries,
    profile: profile,
    packAh: packAh,
    homeCellV: homeCellV,
    stopCellV: stopCellV,
    homeEffCellV: homeEffCellV,
    stopEffCellV: stopEffCellV,
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
    vehicleLabel: vehicleLabel,
    vehicleCustomIcon: vehicleCustomIcon,
    wifiSsid: wifiSsid,
    wifiPass: wifiPass,
    hasBoardCal: hasBoardCal,
    calPackROhm: calPackROhm,
    calTypicalAmps: calTypicalAmps,
    calWhPerMile: calWhPerMile,
    calPackWh: calPackWh,
    firmwareVersion: firmwareVersion,
    hasStatusRgb: hasStatusRgb,
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

  /// True when the connected board exposes the BMS characteristic (0006) — i.e.
  /// it's a BMS build. Drives whether the app shows the pack view. Valid after
  /// [connect].
  bool get hasBms;

  /// 1 Hz Daly pack + per-cell stream. Empty (never emits) when [hasBms] is
  /// false, so callers can subscribe unconditionally.
  Stream<BmsData> bms();

  Future<BoardSettings?> readSettings();
  Future<void> writeSettings(Map<String, dynamic> partial);
  Future<void> sendCommand(String command);

  /// VESC base config + provenance (fw 0.10.1+). Null on older firmware.
  Future<BaseConfig?> readBaseConfig();
}
