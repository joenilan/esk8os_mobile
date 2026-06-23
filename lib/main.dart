import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'ble/companion_device.dart';
import 'ble/esk8os_ble.dart';
import 'ble/mock_device.dart';
import 'database/trip_database.dart';
import 'pages/settings_page.dart';
import 'pages/wifi_export_page.dart';
import 'services/app_prefs.dart';
import 'services/trip_recorder.dart';
import 'views/dash_view.dart';
import 'views/graphs_view.dart';
import 'views/hud_view.dart';
import 'views/logs_view.dart';
import 'views/power_view.dart';
import 'views/settings_summary_view.dart';
import 'views/system_view.dart';
import 'views/trip_stats_view.dart';
import 'views/trip_view.dart';
import 'widgets/esk8_theme.dart';
import 'widgets/esk8_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort(); // for notification-button relay
  await AppPrefs.init();
  TripDatabase.instance.recoverOrphans(); // finalize any trip left open by a kill
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const Esk8App());
}

const _accent = Color(0xFFB950D7); // matches the board's CAM accent

class Esk8App extends StatelessWidget {
  const Esk8App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESK8OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const ScanPage(),
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
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DashboardPage(dev: dev)),
      );
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
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DashboardPage(dev: dev)),
      );
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
                        child: CircularProgressIndicator(strokeWidth: 2)),
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
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
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
                    for (final r in results)
                      ListTile(
                        leading: const Icon(Icons.electric_scooter),
                        title: Text(r.device.platformName.isNotEmpty
                            ? r.device.platformName
                            : r.device.remoteId.str),
                        subtitle: Text('${r.rssi} dBm'),
                        onTap: _connecting ? null : () => _connect(r.device),
                      ),
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

class _DashboardPageState extends State<DashboardPage> {
  late final Stream<Telemetry> _telemetry = widget.dev.telemetry();
  StreamSubscription<DeviceConnectionState>? _connSub;
  BoardSettings? _boardSettings;

  // Start deep in a large virtual range so the deck wraps both ways (last page
  // swipes back to the first, and vice-versa). _kLoopBase is a multiple of the
  // page count so the initial page is HUD (index 0).
  static const int _kLoopBase = 10000;
  final PageController _pageCtrl = PageController(initialPage: _kLoopBase);
  int _currentPage = 0;
  bool _showControls = false;

  // Auto start/stop + over-speed alert run off the latest telemetry frame.
  Telemetry? _latestT;
  Timer? _autoTimer;
  DateTime? _stoppedSince;
  bool _wasOverSpeed = false;

  @override
  void initState() {
    super.initState();
    _connSub = widget.dev.connectionState.listen((s) {
      if (s == DeviceConnectionState.disconnected && mounted) {
        Navigator.of(context).pop();
      }
    });
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _autoTick());
    _fetchSettings();
  }

  /// Once a second: auto start/stop a trip from movement, and fire the
  /// over-speed haptic when crossing the alert threshold.
  void _autoTick() {
    final t = _latestT;
    if (t == null) return;
    final rec = TripRecorder.instance;

    if (AppPrefs.autoTrip) {
      if (!rec.isRecording) {
        if (t.speed > 5) rec.start(widget.dev); // moving -> begin a trip
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
      if (mounted && s != null) setState(() => _boardSettings = s);
    } catch (_) {}
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    widget.dev.disconnect();
    super.dispose();
  }

  Future<void> _cmd(String command, String label) async {
    try {
      await widget.dev.sendCommand(command);
      _toast('$label sent');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // App page -> board PageId. Mirrors the board's 8-page deck, plus the GPS MAP
  // which is app-only (-1 = no board sync; it leaves the board where it is).
  static const _pageNames = ['HUD', 'DASH', 'POWER', 'TRIP', 'MAP', 'SETTINGS', 'SYSTEM', 'GRAPHS', 'LOGS'];
  static const _boardPage = [0, 1, 2, 3, -1, 4, 5, 6, 7];

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    final bp = (index >= 0 && index < _boardPage.length) ? _boardPage[index] : -1;
    if (bp >= 0) {
      widget.dev.sendCommand(Esk8Commands.pageSet(bp)).catchError((_) {});
    }
  }

  String _pageName(int i) => (i >= 0 && i < _pageNames.length) ? _pageNames[i] : '';

  static String _clock() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<Telemetry>(
        stream: _telemetry,
        builder: (_, snap) {
          final t = snap.data;
          _latestT = t; // feed the auto-trip / alert tick
          final du = _boardSettings?.mph == true ? 'mi' : 'km';
          final rider = (_boardSettings?.rider ?? '').trim().toUpperCase();
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
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Esk8Theme.border)),
                  ),
                  child: TopStatusBar(
                    left: rider.isNotEmpty ? 'RIDER: $rider' : 'ESK8OS',
                    right: _clock(),
                  ),
                ),

                // PAGES — double-tap toggles the controls overlay
                Expanded(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onDoubleTap: () => setState(() => _showControls = !_showControls),
                        child: PageView.builder(
                          controller: _pageCtrl,
                          onPageChanged: (i) => _onPageChanged(i % _pageNames.length),
                          itemBuilder: (_, i) {
                            switch (i % _pageNames.length) {
                              case 0:
                                return HudView(telemetry: t, settings: _boardSettings);
                              case 1:
                                return DashView(telemetry: t, settings: _boardSettings);
                              case 2:
                                return PowerView(telemetry: t, settings: _boardSettings);
                              case 3:
                                return TripStatsView(telemetry: t, settings: _boardSettings);
                              case 4:
                                return TripView(dev: widget.dev, telemetry: t, settings: _boardSettings);
                              case 5:
                                return SettingsSummaryView(dev: widget.dev, settings: _boardSettings, onEdited: _fetchSettings);
                              case 6:
                                return SystemView(telemetry: t, settings: _boardSettings);
                              case 7:
                                return GraphsView(telemetry: t, settings: _boardSettings);
                              default:
                                return LogsView(settings: _boardSettings);
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
                            child: Text(_pageName(_currentPage),
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Esk8Theme.dim,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),

                      // On the MAP page swipes are consumed by the map (so you
                      // can pan/rotate), so give explicit prev/next page buttons.
                      if (_pageName(_currentPage) == 'MAP') ...[
                        Positioned(
                          left: 6,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _NavButton(Icons.chevron_left, () => _pageCtrl.previousPage(
                                duration: const Duration(milliseconds: 280), curve: Curves.easeOut)),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _NavButton(Icons.chevron_right, () => _pageCtrl.nextPage(
                                duration: const Duration(milliseconds: 280), curve: Curves.easeOut)),
                          ),
                        ),
                      ],
                      if (_showControls)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.settings, size: 32),
                            color: Colors.white54,
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => SettingsPage(dev: widget.dev)),
                              );
                              _fetchSettings();
                            },
                          ),
                        ),
                      if (_showControls)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.black87,
                            padding: const EdgeInsets.all(16).copyWith(bottom: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('CONTROLS', style: TextStyle(color: Colors.grey, letterSpacing: 2)),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _CmdButton('Trip Reset', () => _cmd(Esk8Commands.tripReset, 'Trip reset')),
                                    _CmdButton('WiFi Export / OTA', () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => WifiExportPage(dev: widget.dev)),
                                      );
                                    }),
                                    _CmdButton('Bridge Mode', () => _cmd(Esk8Commands.bridgeMode, 'Bridge mode')),
                                    _CmdButton('Reboot', () => _cmd(Esk8Commands.reboot, 'Reboot')),
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
                    children: List.generate(_pageNames.length, (i) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _currentPage ? _accent : Colors.white.withValues(alpha: 0.25),
                      ),
                    )),
                  ),
                ),

                // BOTTOM PANEL — identifies battery · trip · odometer
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  decoration: const BoxDecoration(
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
