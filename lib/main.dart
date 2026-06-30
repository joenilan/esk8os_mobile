import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay/trip_overlay.dart';

import 'ble/companion_device.dart';
import 'ble/esk8os_ble.dart';
import 'ble/mock_device.dart';
import 'database/trip_database.dart';
import 'pages/settings_page.dart';
import 'pages/wifi_export_page.dart';
import 'services/app_prefs.dart';
import 'services/trip_recorder.dart';
import 'views/dash_view.dart';
import 'views/diag_view.dart';
import 'views/graphs_view.dart';
import 'views/hud_view.dart';
import 'views/settings_summary_view.dart';
import 'views/trip_view.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/esk8_theme.dart';
import 'widgets/esk8_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort(); // for notification-button relay
  await AppPrefs.init();
  TripDatabase.instance
      .recoverOrphans(); // finalize any trip left open by a kill
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const Esk8App());
}

/// Entry point for the floating-overlay engine (kept by the tree-shaker).
@pragma('vm:entry-point')
void overlayMain() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: TripOverlay()),
  );
}

Color get _accent => Esk8Theme.accent; // follows the board's selected theme

class Esk8App extends StatelessWidget {
  const Esk8App({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app whenever the board's theme changes so the
    // MaterialApp chrome (scaffold bg, colour scheme, light/dark) re-themes.
    return ValueListenableBuilder<int>(
      valueListenable: Esk8Theme.revision,
      builder: (context, _, child) {
        final brightness =
            Esk8Theme.isLight ? Brightness.light : Brightness.dark;
        return MaterialApp(
          title: 'ESK8OS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: brightness,
            scaffoldBackgroundColor: Esk8Theme.scaffold,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Esk8Theme.accent,
              brightness: brightness,
            ),
          ),
          home: const ScanPage(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan: find boards advertising the companion service, tap to connect.
// ─────────────────────────────────────────────────────────────────────────────
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  String? _error;
  bool _connecting = false;

  Future<void> _scan() async {
    setState(() => _error = null);
    final ok = await CompanionScanner.requestPermissions();
    if (!ok) {
      setState(() => _error = 'Bluetooth permission denied');
      return;
    }
    try {
      await CompanionScanner.start();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    await CompanionScanner.stop();
    setState(() => _connecting = true);
    final dev = CompanionDevice(device);
    try {
      await dev.connect();
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DashboardPage(dev: dev)));
    } catch (e) {
      if (mounted) setState(() => _error = 'Connect failed: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _startMockMode() async {
    await CompanionScanner.stop();
    setState(() => _connecting = true);
    final dev = MockDevice();
    try {
      await dev.connect();
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DashboardPage(dev: dev)));
    } catch (e) {
      if (mounted) setState(() => _error = 'Mock connect failed: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESK8OS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Mock Mode',
            onPressed: _connecting ? null : _startMockMode,
          ),
          StreamBuilder<bool>(
            stream: CompanionScanner.isScanning,
            initialData: false,
            builder: (_, snap) => (snap.data ?? false)
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(icon: const Icon(Icons.search), onPressed: _scan),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          if (_connecting) const LinearProgressIndicator(),
          Expanded(
            child: StreamBuilder<List<ScanResult>>(
              stream: CompanionScanner.results(),
              initialData: const [],
              builder: (_, snap) {
                final results = snap.data ?? const [];
                if (results.isEmpty) {
                  return const Center(
                    child: Text('Tap search to scan for your board'),
                  );
                }
                return ListView(
                  children: [
                    // The board advertises [vtype, macHi, macLo] in manufacturer
                    // data (company 0xFFFF), so we can show the right vehicle icon
                    // and the pair code BEFORE connecting. Fall back to the MAC tail
                    // for the code (Android exposes it) and a skateboard icon.
                    ...results.map((r) {
                      final mfg =
                          r.advertisementData.manufacturerData[0xFFFF];
                      final hasMfg = mfg != null && mfg.length >= 3;
                      final vtype = hasMfg ? mfg[0] : 0;
                      final macHex =
                          r.device.remoteId.str.replaceAll(':', '');
                      final code = hasMfg
                          ? (mfg[1].toRadixString(16).padLeft(2, '0') +
                                    mfg[2].toRadixString(16).padLeft(2, '0'))
                                .toUpperCase()
                          : (macHex.length >= 4
                                ? macHex
                                      .substring(macHex.length - 4)
                                      .toUpperCase()
                                : null);
                      return ListTile(
                        leading: Icon(Vehicle.icon(vtype)),
                        title: Text(
                          r.device.platformName.isNotEmpty
                              ? r.device.platformName
                              : r.device.remoteId.str,
                        ),
                        subtitle: Text(
                          code != null
                              ? 'PAIR #$code   ·   ${r.rssi} dBm'
                              : '${r.rssi} dBm',
                        ),
                        onTap: _connecting ? null : () => _connect(r.device),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard: live telemetry + command buttons for a connected board.
// ─────────────────────────────────────────────────────────────────────────────
class DashboardPage extends StatefulWidget {
  final Esk8Device dev;
  const DashboardPage({super.key, required this.dev});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  // Telemetry is re-piped through a controller we own so the UI's StreamBuilder
  // survives a BLE drop + reconnect (the underlying characteristic stream is
  // replaced on reconnect via _subscribeTelemetry).
  final StreamController<Telemetry> _telCtrl =
      StreamController<Telemetry>.broadcast();
  StreamSubscription<Telemetry>? _telSub;
  StreamSubscription<DeviceConnectionState>? _connSub;
  bool _reconnecting = false;
  BoardSettings? _boardSettings;

  // Start deep in a large virtual range so the deck wraps both ways (last page
  // swipes back to the first, and vice-versa). _kLoopBase is a multiple of the
  // page count so the initial page is HUD (index 0). 6006 % 6 == 0.
  static const int _kLoopBase = 6006;
  final PageController _pageCtrl = PageController(initialPage: _kLoopBase);
  int _currentPage = 0;
  bool _showControls = false;
  bool _bridgeModeRequested = false;
  static const _oledFaces = ['speed', 'battery', 'volts', 'watts', 'safety'];

  // Auto start/stop + over-speed alert run off the latest telemetry frame.
  Telemetry? _latestT;
  final List<Telemetry> _telemetryHistory = <Telemetry>[];
  Timer? _autoTimer;
  DateTime? _stoppedSince;
  bool _seenStopped = false; // gate: auto-start only after a real standstill
  bool _wasOverSpeed = false;
  bool _overlayShown = false;
  static const _appChannel = MethodChannel('esk8os/app');
  // overlayListener is a single-subscription stream — listen ONCE per process,
  // not per DashboardPage (reconnecting would otherwise throw and gray the app).
  static bool _overlayListenerSet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeTelemetry();
    _connSub = widget.dev.connectionState.listen((s) {
      if (s == DeviceConnectionState.disconnected &&
          mounted &&
          !_reconnecting) {
        _handleReconnect();
      }
    });
    // Tapping the floating overlay asks the app to come back to the front.
    // Guarded so we only ever attach one listener for the whole process.
    if (!_overlayListenerSet) {
      _overlayListenerSet = true;
      try {
        FlutterOverlayWindow.overlayListener.listen((event) {
          if (event == 'open_app') _appChannel.invokeMethod('bringToFront');
        });
      } catch (_) {}
    }
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _autoTick());
    _fetchSettings();
  }

  /// Pop the floating window when a recording trip is backgrounded; dismiss it
  /// when the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused &&
        AppPrefs.overlayEnabled &&
        TripRecorder.instance.isRecording &&
        !_overlayShown) {
      if (await FlutterOverlayWindow.isPermissionGranted()) {
        await FlutterOverlayWindow.showOverlay(
          height: 360,
          width: 360,
          alignment: OverlayAlignment.center,
          enableDrag: true,
          positionGravity: PositionGravity.none,
          overlayTitle: 'ESK8OS trip',
          flag: OverlayFlag.defaultFlag,
        );
        _overlayShown = true;
      }
    } else if (state == AppLifecycleState.resumed && _overlayShown) {
      await FlutterOverlayWindow.closeOverlay();
      _overlayShown = false;
    }
  }

  void _pushOverlay() {
    final rec = TripRecorder.instance;
    final mph = _boardSettings?.mph ?? true;
    final spd = mph ? rec.gpsSpeedKmh / 1.60934 : rec.gpsSpeedKmh;
    final trip = mph ? rec.gpsDistanceM / 1609.34 : rec.gpsDistanceM / 1000.0;
    final pos = rec.currentPosition;
    FlutterOverlayWindow.shareData(
      jsonEncode({
        'spd': spd.toStringAsFixed(0),
        'unit': mph ? 'MPH' : 'KM/H',
        'trip': trip.toStringAsFixed(2),
        'tu': mph ? 'mi' : 'km',
        'time': _fmtElapsed(rec.elapsed),
        'paused': rec.isPaused,
        // Map fields — guarded; rider may have no fix yet.
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
        'hdg': rec.heading,
      }),
    );
  }

  String _fmtElapsed(Duration d) {
    final h = d.inHours,
        m = d.inMinutes.remainder(60),
        s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Once a second: auto start/stop a trip from movement, and fire the
  /// over-speed haptic when crossing the alert threshold.
  void _autoTick() {
    if (_overlayShown) _pushOverlay(); // feed the floating window live stats
    final t = _latestT;
    if (t == null) return;
    final rec = TripRecorder.instance;

    if (t.speed < 0.5) _seenStopped = true; // a genuine standstill was observed
    if (AppPrefs.autoTrip) {
      if (!rec.isRecording) {
        // Only auto-start after a real stop since the last trip — so a manual
        // Stop sticks (and the always-moving mock never auto-restarts).
        if (_seenStopped && t.speed > 5) {
          _seenStopped = false;
          rec.start(widget.dev, isMph: _boardSettings?.mph ?? true);
        }
      } else if (!rec.isPaused) {
        if (t.speed < 1) {
          _stoppedSince ??= DateTime.now();
          if (DateTime.now().difference(_stoppedSince!).inMinutes >= 3) {
            rec.stop(); // parked a while -> end the trip
            _stoppedSince = null;
          }
        } else {
          _stoppedSince = null;
        }
      }
    }

    final alert = AppPrefs.speedAlert;
    if (alert > 0) {
      final over = t.speed >= alert;
      if (over && !_wasOverSpeed) HapticFeedback.heavyImpact();
      _wasOverSpeed = over;
    }
  }

  Future<void> _fetchSettings() async {
    try {
      final s = await widget.dev.readSettings();
      if (mounted && s != null) {
        Esk8Theme.applyTheme(s.theme);
        setState(() => _boardSettings = s);
      }
    } catch (_) {}
  }

  /// (Re)subscribe to the device's telemetry stream and forward into _telCtrl.
  /// Called on init and after every successful reconnect (the characteristic
  /// object is replaced on reconnect, so the old subscription is dead).
  void _subscribeTelemetry() {
    _telSub?.cancel();
    _telSub = widget.dev.telemetry().listen((t) {
      _latestT = t;
      final frameMph = t.mph;
      if (frameMph != null && _boardSettings?.mph != frameMph) {
        final current = _boardSettings;
        if (current != null && mounted) {
          setState(() => _boardSettings = current.copyWith(mph: frameMph));
        }
      }
      _telemetryHistory.add(t);
      if (_telemetryHistory.length > 60) _telemetryHistory.removeAt(0);
      if (!_telCtrl.isClosed) _telCtrl.add(t);
    }, onError: (_) {});
  }

  /// On a BLE drop, retry connect() with backoff (the board is usually still
  /// nearby — range blip, or a reboot taking a few seconds) before giving up and
  /// returning to the scan screen. The last telemetry frame stays on screen.
  Future<void> _handleReconnect() async {
    if (_reconnecting || !mounted) return;
    setState(() => _reconnecting = true);
    for (int attempt = 1; attempt <= 6 && mounted; attempt++) {
      await Future.delayed(Duration(seconds: (attempt * 2).clamp(2, 8)));
      if (!mounted) return;
      try {
        await widget.dev.connect();
        _subscribeTelemetry();
        await _fetchSettings();
        if (mounted) setState(() => _reconnecting = false);
        return; // recovered
      } catch (_) {
        /* keep retrying */
      }
    }
    if (mounted) {
      setState(() => _reconnecting = false);
      Navigator.of(context).pop(); // gave up — back to scan
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_overlayShown) FlutterOverlayWindow.closeOverlay();
    _telSub?.cancel();
    _telCtrl.close();
    _connSub?.cancel();
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    widget.dev.disconnect();
    super.dispose();
  }

  Future<void> _cmd(String command, String label) async {
    try {
      await widget.dev.sendCommand(command);
      if (command == Esk8Commands.bridgeMode ||
          command == Esk8Commands.bridgeToggle) {
        setState(() => _bridgeModeRequested = true);
      } else if (command == Esk8Commands.bridgeExit ||
          command == Esk8Commands.reboot) {
        setState(() => _bridgeModeRequested = false);
      }
      _toast('$label sent');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  Future<void> _writeSettings(
    Map<String, dynamic> partial,
    String label,
  ) async {
    try {
      await widget.dev.writeSettings(partial);
      await _fetchSettings();
      _toast('$label updated');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  Future<void> _setOledFace(String face) =>
      _writeSettings(BoardSettings.writeJson(hudFace: face), 'OLED face');

  Future<void> _stepOledFace(int delta) async {
    final current = _boardSettings?.hudFace ?? 'speed';
    final index = _oledFaces.contains(current)
        ? _oledFaces.indexOf(current)
        : 0;
    final next = _oledFaces[(index + delta) % _oledFaces.length];
    await _setOledFace(next);
  }

  static String _faceLabel(String face) => switch (face) {
    'speed' => 'Speed',
    'battery' => 'Battery',
    'volts' => 'Volts',
    'watts' => 'Watts',
    'safety' => 'Safety',
    _ => face,
  };

  /// Confirm before a disruptive board command, then send it.
  Future<void> _cmdConfirm(
    String command,
    String label,
    String message, {
    String? confirmLabel,
  }) async {
    final ok = await confirmAction(
      context,
      title: '$label?',
      message: message,
      confirmLabel: confirmLabel ?? label,
    );
    if (!ok) return;
    await _cmd(command, label);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // App page -> board PageId. Mirrors the board's 8-page deck, plus the GPS MAP
  // which is app-only (-1 = no board sync; it leaves the board where it is).
  // Consolidated phone deck (the board keeps its own 8 pages; the app no longer
  // mirrors them 1:1). DASH absorbed POWER; TRIP is the map + stats + history;
  // DIAG absorbed SYSTEM.
  static const _pageNames = [
    'HUD',
    'DASH',
    'TRIP',
    'GRAPHS',
    'DIAG',
    'SETTINGS',
  ];

  void _onPageChanged(int index) {
    // App pages independently of the board now — the board self-navigates with its
    // LEFT button. (PAGE_SET is still available as a command if we ever want an
    // explicit remote-control toggle; we just don't fire it on every swipe.)
    setState(() => _currentPage = index);
  }

  String _pageName(int i) =>
      (i >= 0 && i < _pageNames.length) ? _pageNames[i] : '';

  static String _clock() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  static String _rangeWarningText(Telemetry t) => switch (t.rangeWarning) {
    3 => 'LIMP HOME · ${t.cellVolts.toStringAsFixed(2)} V/cell',
    2 => 'VOLTAGE SAG · ease throttle',
    1 => 'TURN HOME · ${t.range.toStringAsFixed(1)} range left',
    _ => '',
  };

  static String _telemetryStateText(Telemetry t) {
    if (!t.live && !t.vescConnected) return 'NO VESC DATA · demo off';
    if (!t.live) return 'NO LIVE TELEMETRY';
    if (!t.vescConnected) return 'VESC LINK LOST';
    return '';
  }

  static Color _rangeWarningColor(int code) => switch (code) {
    3 => Esk8Theme.danger,
    2 => Esk8Theme.orange,
    1 => Esk8Theme.yellow,
    _ => Colors.transparent,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<Telemetry>(
        stream: _telCtrl.stream,
        initialData: _latestT,
        builder: (_, snap) {
          final t = snap.data ?? _latestT;
          _latestT = t; // feed the auto-trip / alert tick
          final du = _boardSettings?.mph == true ? 'mi' : 'km';
          final rider = (_boardSettings?.rider ?? '').trim().toUpperCase();
          final isHeadless =
              _boardSettings?.display == 'none' ||
              _boardSettings?.ui == 'headless';
          final hasBoardDisplay = _boardSettings?.display != 'none';
          return SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                // TOP PANEL — rider (left) · time (right). The centre is left
                // empty so the camera punch-hole sits in clear space; the panel
                // rides up at the notch line. Page title moves into the content.
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Esk8Theme.border)),
                  ),
                  child: TopStatusBar(
                    leadingIcon: Vehicle.icon(_boardSettings?.vehicleType ?? 0),
                    left: rider.isNotEmpty ? 'RIDER: $rider' : 'ESK8OS',
                    right: _clock(),
                  ),
                ),

                // Connection-lost banner: shown while we retry in the background.
                // The dashboard keeps the last telemetry frame underneath.
                if (_reconnecting)
                  Container(
                    width: double.infinity,
                    color: const Color(0x26FFCD00), // yellow @ ~15%
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Esk8Theme.yellow,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Reconnecting to board…',
                          style: TextStyle(
                            color: Esk8Theme.yellow,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_reconnecting && t != null && t.rangeWarning != 0)
                  Container(
                    width: double.infinity,
                    color: _rangeWarningColor(
                      t.rangeWarning,
                    ).withValues(alpha: 0.18),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      _rangeWarningText(t),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _rangeWarningColor(t.rangeWarning),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                if (!_reconnecting && t != null && !t.live)
                  Container(
                    width: double.infinity,
                    color: Esk8Theme.orange.withValues(alpha: 0.18),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      _telemetryStateText(t),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Esk8Theme.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),

                // PAGES — double-tap toggles the controls overlay
                Expanded(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onDoubleTap: () =>
                            setState(() => _showControls = !_showControls),
                        child: PageView.builder(
                          controller: _pageCtrl,
                          onPageChanged: (i) =>
                              _onPageChanged(i % _pageNames.length),
                          itemBuilder: (_, i) {
                            switch (i % _pageNames.length) {
                              case 0:
                                return HudView(
                                  telemetry: t,
                                  settings: _boardSettings,
                                );
                              case 1:
                                return DashView(
                                  telemetry: t,
                                  settings: _boardSettings,
                                );
                              case 2:
                                return TripView(
                                  dev: widget.dev,
                                  telemetry: t,
                                  settings: _boardSettings,
                                );
                              case 3:
                                return GraphsView(
                                  telemetry: t,
                                  history: _telemetryHistory,
                                  settings: _boardSettings,
                                );
                              case 4:
                                return DiagView(
                                  telemetry: t,
                                  settings: _boardSettings,
                                );
                              default:
                                return SettingsSummaryView(
                                  dev: widget.dev,
                                  settings: _boardSettings,
                                  telemetry: t,
                                  onEdited: _fetchSettings,
                                );
                            }
                          },
                        ),
                      ),
                      // Page title — moved out of the top panel, centered at the
                      // top of the content (in the open space above the speed).
                      Positioned(
                        top: 6,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Text(
                              _pageName(_currentPage),
                              style: TextStyle(
                                fontSize: 13,
                                color: Esk8Theme.dim,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Headless boards need obvious phone navigation. The TRIP
                      // map also gets arrows because map gestures consume swipes.
                      if (isHeadless || _pageName(_currentPage) == 'TRIP') ...[
                        Positioned(
                          left: 6,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _NavButton(
                              Icons.chevron_left,
                              () => _pageCtrl.previousPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOut,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _NavButton(
                              Icons.chevron_right,
                              () => _pageCtrl.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOut,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!_showControls)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.tune, size: 30),
                            color: Colors.white60,
                            tooltip: 'Controls',
                            onPressed: () => setState(() => _showControls = true),
                          ),
                        ),
                      if (_showControls)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.black87,
                            padding: const EdgeInsets.all(
                              16,
                            ).copyWith(bottom: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'CONTROLS',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.touch_app,
                                      color: Colors.white60,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'PHONE NAVIGATION',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Close controls',
                                      onPressed: () =>
                                          setState(() => _showControls = false),
                                      icon: const Icon(Icons.close),
                                      color: Colors.white60,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _pageCtrl.previousPage(
                                          duration: const Duration(
                                            milliseconds: 280,
                                          ),
                                          curve: Curves.easeOut,
                                        ),
                                        icon: const Icon(Icons.chevron_left),
                                        label: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Prev'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _pageCtrl.nextPage(
                                          duration: const Duration(
                                            milliseconds: 280,
                                          ),
                                          curve: Curves.easeOut,
                                        ),
                                        icon: const Icon(Icons.chevron_right),
                                        label: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Next'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => SettingsPage(
                                                dev: widget.dev,
                                                telemetry: _latestT,
                                              ),
                                            ),
                                          );
                                          _fetchSettings();
                                        },
                                        icon: const Icon(Icons.settings),
                                        label: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Settings'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (hasBoardDisplay) ...[
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.developer_board,
                                        color: Colors.white60,
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          'BOARD DISPLAY',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _cmd(
                                          Esk8Commands.pagePrev,
                                          'Board page previous',
                                        ),
                                        icon: const Icon(Icons.chevron_left),
                                        label: const Text('Prev'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _cmd(
                                          Esk8Commands.pageNext,
                                          'Board page next',
                                        ),
                                        icon: const Icon(Icons.chevron_right),
                                        label: const Text('Next'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (_boardSettings?.display == 'oled') ...[
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.splitscreen,
                                        color: Colors.white60,
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'OLED FACE',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _faceLabel(
                                          _boardSettings?.hudFace ?? 'speed',
                                        ).toUpperCase(),
                                        style: TextStyle(
                                          color: _accent,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _NavButton(
                                        Icons.chevron_left,
                                        () => _stepOledFace(-1),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final face in _oledFaces)
                                              ChoiceChip(
                                                label: Text(_faceLabel(face)),
                                                selected:
                                                    (_boardSettings?.hudFace ??
                                                        'speed') ==
                                                    face,
                                                selectedColor: _accent,
                                                labelStyle: TextStyle(
                                                  color:
                                                      (_boardSettings
                                                                  ?.hudFace ??
                                                              'speed') ==
                                                          face
                                                      ? Colors.black
                                                      : Colors.white70,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                onSelected: (_) =>
                                                    _setOledFace(face),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _NavButton(
                                        Icons.chevron_right,
                                        () => _stepOledFace(1),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _CmdButton(
                                      'Trip Reset',
                                      () => _cmdConfirm(
                                        Esk8Commands.tripReset,
                                        'Trip Reset',
                                        'Zeros the board\'s trip distance and moving-time. The lifetime odometer is unaffected.',
                                      ),
                                    ),
                                    _CmdButton('WiFi Export / OTA', () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              WifiExportPage(dev: widget.dev),
                                        ),
                                      );
                                    }),
                                    _CmdButton(
                                      'Bridge Mode',
                                      () => _cmdConfirm(
                                        _bridgeModeRequested
                                            ? Esk8Commands.bridgeExit
                                            : Esk8Commands.bridgeMode,
                                        _bridgeModeRequested
                                            ? 'Stop Bridge'
                                            : 'Bridge Mode',
                                        _bridgeModeRequested
                                            ? 'Stops VESC passthrough and returns the ESP32 to normal dashboard telemetry.'
                                            : 'Puts the board into VESC passthrough. Use Stop Bridge here when you are done.',
                                        confirmLabel: _bridgeModeRequested
                                            ? 'Stop'
                                            : 'Enter',
                                      ),
                                    ),
                                    _CmdButton(
                                      'Reboot',
                                      () => _cmdConfirm(
                                        Esk8Commands.reboot,
                                        'Reboot',
                                        'Restarts the board now. Telemetry will drop for a few seconds.',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // PAGE DOTS
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pageNames.length,
                      (i) => Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _currentPage
                              ? _accent
                              : Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
                ),

                // BOTTOM PANEL — identifies battery · trip · odometer
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Esk8Theme.border)),
                  ),
                  child: t == null
                      ? const SizedBox(height: 18)
                      : BottomStatus(
                          percent: t.battery,
                          trip: '${t.trip.toStringAsFixed(1)}$du',
                          odo: '${t.odometer.toStringAsFixed(0)}$du',
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CmdButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CmdButton(this.label, this.onTap);

  @override
  Widget build(BuildContext context) =>
      OutlinedButton(onPressed: onTap, child: Text(label));
}

/// Round translucent page-nav button (used on the map page where swipe pans).
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavButton(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xDD1A1A1A),
        shape: BoxShape.circle,
        border: Border.all(color: Esk8Theme.border),
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    ),
  );
}
