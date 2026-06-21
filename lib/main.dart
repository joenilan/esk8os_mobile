import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/companion_device.dart';
import 'ble/esk8os_ble.dart';

void main() => runApp(const Esk8App());

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESK8OS'),
        actions: [
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
  final CompanionDevice dev;
  const DashboardPage({super.key, required this.dev});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final Stream<Telemetry> _telemetry = widget.dev.telemetry();
  StreamSubscription<BluetoothConnectionState>? _connSub;

  @override
  void initState() {
    super.initState();
    _connSub = widget.dev.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dev.name)),
      body: StreamBuilder<Telemetry>(
        stream: _telemetry,
        builder: (_, snap) {
          final t = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (t == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Waiting for telemetry…')),
                )
              else ...[
                _Hero(value: t.speed.toStringAsFixed(1)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.2,
                  children: [
                    _Tile(label: 'BATTERY', value: '${t.battery}%'),
                    _Tile(label: 'VOLTS', value: t.volts.toStringAsFixed(1)),
                    _Tile(label: 'WATTS', value: '${t.watts}'),
                    _Tile(label: 'RANGE', value: t.range.toStringAsFixed(1)),
                    _Tile(label: 'MOTOR °C', value: '${t.motorTempC}'),
                    _Tile(label: 'ESC °C', value: '${t.escTempC}'),
                    _Tile(label: 'MAX SPD', value: t.maxSpeed.toStringAsFixed(1)),
                    _Tile(label: 'SESSION WH', value: '${t.wattHours}'),
                  ],
                ),
              ],
              const Divider(height: 32),
              Text('COMMANDS', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CmdButton('Trip Reset', () => _cmd(Esk8Commands.tripReset, 'Trip reset')),
                  _CmdButton('Page ◀', () => _cmd(Esk8Commands.pagePrev, 'Prev page')),
                  _CmdButton('Page ▶', () => _cmd(Esk8Commands.pageNext, 'Next page')),
                  _CmdButton('WiFi Export', () => _cmd(Esk8Commands.wifiExportStart, 'WiFi export start')),
                  _CmdButton('WiFi Off', () => _cmd(Esk8Commands.wifiExportStop, 'WiFi export stop')),
                  _CmdButton('Bridge Mode', () => _cmd(Esk8Commands.bridgeMode, 'Bridge mode')),
                  _CmdButton('Reboot', () => _cmd(Esk8Commands.reboot, 'Reboot')),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final String value;
  const _Hero({required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 84, fontWeight: FontWeight.bold, height: 1)),
        Text('SPEED', style: TextStyle(color: Colors.grey[500], letterSpacing: 2)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  const _Tile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
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
