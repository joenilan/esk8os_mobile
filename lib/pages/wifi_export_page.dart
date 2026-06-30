import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../ble/esk8os_ble.dart';
import '../wifi/wifi_service.dart';
import '../widgets/esk8_theme.dart';

Color get _accent => Esk8Theme.accent; // follows the board's selected theme

class WifiExportPage extends StatefulWidget {
  final Esk8Device dev;
  const WifiExportPage({super.key, required this.dev});

  @override
  State<WifiExportPage> createState() => _WifiExportPageState();
}

class _WifiExportPageState extends State<WifiExportPage> {
  int _step = 0; // 0: Start, 1: Connect, 2: Action
  bool _loading = false;
  String? _error;

  List<String>? _logs;
  bool _uploading = false;

  @override
  void dispose() {
    // Ensure we stop export mode on the board when exiting.
    widget.dev.sendCommand(Esk8Commands.wifiExportStop).catchError((_) {});
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // --- Step 1: Send Start Command ---
  Future<void> _startExport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.dev.sendCommand(Esk8Commands.wifiExportStart);
      setState(() {
        _step = 1;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to start WiFi mode: $e';
        _loading = false;
      });
    }
  }

  // --- Step 2: Confirm Connected ---
  void _confirmConnected() {
    setState(() {
      _step = 2;
    });
    _fetchLogs();
  }

  // --- Step 3: Logs & OTA ---
  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await WifiService.fetchLogIndex();
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error =
            'Failed to connect to board WiFi. Are you connected to ESK8-BRIDGE?';
        _loading = false;
      });
    }
  }

  Future<void> _downloadLog(String filename) async {
    setState(() => _loading = true);
    try {
      final file = await WifiService.downloadLog(filename);
      _toast('Downloaded to ${file.path}');
    } catch (e) {
      _toast('Download failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadOta() async {
    try {
      const XTypeGroup typeGroup = XTypeGroup(extensions: <String>['bin']);
      final XFile? result = await openFile(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );

      if (result != null) {
        final file = File(result.path);
        setState(() => _uploading = true);

        await WifiService.uploadOta(file);

        _toast('OTA Success! Board will restart.');
        // After OTA, board restarts, so we drop out.
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      _toast('OTA failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi Export & OTA')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_uploading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _accent),
            SizedBox(height: 16),
            Text('Uploading Firmware...', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text(
              'Do not close the app or turn off the board.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Stepper(
      currentStep: _step,
      controlsBuilder: (context, details) =>
          const SizedBox.shrink(), // Custom controls inside steps
      steps: [
        Step(
          title: const Text('Enable Board WiFi'),
          isActive: _step >= 0,
          state: _step > 0 ? StepState.complete : StepState.indexed,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will command the board to raise its high-speed WiFi network for file transfers.',
              ),
              const SizedBox(height: 16),
              if (_error != null && _step == 0)
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              FilledButton(
                onPressed: _loading ? null : _startExport,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start WiFi Export'),
              ),
            ],
          ),
        ),
        Step(
          title: const Text('Connect Phone to Board'),
          isActive: _step >= 1,
          state: _step > 1 ? StepState.complete : StepState.indexed,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Open your phone\'s WiFi settings.\n'
                '2. Connect to the network: ESK8-BRIDGE\n'
                '3. Password: esk8bridge\n\n'
                'IMPORTANT: If Android asks if you want to stay connected to a network with no internet, tap YES.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _confirmConnected,
                child: const Text('I\'m Connected'),
              ),
            ],
          ),
        ),
        Step(
          title: const Text('Transfer Files'),
          isActive: _step >= 2,
          state: StepState.indexed,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null && _step == 2) ...[
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _fetchLogs,
                  child: const Text('Retry Connection'),
                ),
                const Divider(height: 32),
              ],

              const Text(
                'Board Session Logs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_loading && _logs == null)
                const Center(child: CircularProgressIndicator())
              else if (_logs == null || _logs!.isEmpty)
                const Text(
                  'No logs found.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ..._logs!.map(
                  (log) => ListTile(
                    title: Text(log),
                    trailing: IconButton(
                      icon: Icon(Icons.download, color: _accent),
                      onPressed: _loading ? null : () => _downloadLog(log),
                    ),
                  ),
                ),

              const Divider(height: 32),

              const Text(
                'Firmware Update (OTA)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a .bin file to update the board firmware.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickAndUploadOta,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Select Firmware & Update'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
