import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/companion_device.dart';
import 'ble/esk8os_ble.dart';
import 'ble/mock_device.dart';
import 'pages/settings_page.dart';
import 'pages/wifi_export_page.dart';
import 'views/dash_view.dart';
import 'views/graphs_view.dart';
import 'views/hud_view.dart';
import 'views/power_view.dart';
import 'views/trip_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFF141414),
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

  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _connSub = widget.dev.connectionState.listen((s) {
      if (s == DeviceConnectionState.disconnected && mounted) {
        Navigator.of(context).pop();
      }
    });
    _fetchSettings();
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

  void _onPageChanged(int index) {
    if (index > _currentPage) {
      widget.dev.sendCommand(Esk8Commands.pageNext).catchError((_) {});
    } else if (index < _currentPage) {
      widget.dev.sendCommand(Esk8Commands.pagePrev).catchError((_) {});
    }
    _currentPage = index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<Telemetry>(
        stream: _telemetry,
        builder: (_, snap) {
          final t = snap.data;
          return Stack(
            children: [
              // 1. The main swipeable views — double-tap toggles controls
              GestureDetector(
                onDoubleTap: () => setState(() => _showControls = !_showControls),
                child: PageView(
                  controller: _pageCtrl,
                  onPageChanged: _onPageChanged,
                  children: [
                    HudView(telemetry: t, settings: _boardSettings),
                    DashView(telemetry: t, settings: _boardSettings),
                    PowerView(telemetry: t),
                    TripView(dev: widget.dev, telemetry: t, settings: _boardSettings),
                    GraphsView(telemetry: t),
                  ],
                ),
              ),

              // 2. Page indicator dots (bottom center)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _currentPage
                          ? const Color(0xFF8B5CF6)
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  )),
                ),
              ),

              // 3. Settings Gear (Top Right)
              if (_showControls)
                Positioned(
                  top: 32,
                  right: 16,
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

              // 4. Command Controls (Bottom Overlay)
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
