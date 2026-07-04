import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/esk8os_ble.dart';
import '../wifi/wifi_service.dart';

/// Wireless serial console (fw 0.10.3+). Its own entry point, separate from
/// Export/OTA: the board can't be on USB while the vehicle powers it, so this
/// is the way to reach `stat`, `diag`, `vesc faults`, `set`, `json` etc. with
/// the ESC awake. It rides the board's export AP (same per-device password),
/// but is presented as a distinct action so Export/OTA stays about files.
class ConsolePage extends StatefulWidget {
  final Esk8Device dev;
  const ConsolePage({super.key, required this.dev});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  int _step = 0; // 0 enable, 1 connect, 2 terminal
  bool _loading = false;
  String? _error;
  String _ssid = Esk8WifiExport.ssid;
  String _pass = Esk8WifiExport.legacyPassword;

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _lines = <String>['EVEE wireless console — type a command (try: help)'];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _fetchCredentials();
  }

  Future<void> _fetchCredentials() async {
    try {
      final s = await widget.dev.readSettings();
      if (s != null && mounted) {
        setState(() {
          _ssid = s.wifiSsid;
          _pass = s.wifiPass;
        });
      }
    } catch (_) {/* keep defaults */}
  }

  @override
  void dispose() {
    widget.dev.sendCommand(Esk8Commands.wifiExportStop).catchError((_) {});
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
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
        _error = 'Failed to enable board WiFi: $e';
        _loading = false;
      });
    }
  }

  Future<void> _run() async {
    final cmd = _inputCtrl.text.trim();
    if (cmd.isEmpty || _running) return;
    _inputCtrl.clear();
    setState(() {
      _lines.add('> $cmd');
      _running = true;
    });
    _scrollToEnd();
    try {
      final out = await WifiService.runCommand(cmd);
      setState(() => _lines.add(out.trimRight()));
    } catch (e) {
      setState(() => _lines.add('(request failed — connected to $_ssid? $e)'));
    } finally {
      if (mounted) setState(() => _running = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wireless Console')),
      body: _step < 2 ? _buildSetup() : _buildTerminal(),
    );
  }

  Widget _buildSetup() {
    return Stepper(
      currentStep: _step,
      controlsBuilder: (context, details) => const SizedBox.shrink(),
      steps: [
        Step(
          title: const Text('Enable Board WiFi'),
          isActive: _step >= 0,
          state: _step > 0 ? StepState.complete : StepState.indexed,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Raises the board\'s WiFi so your phone can reach the console — '
                'the same console as USB serial, but usable while the vehicle '
                'is powered (when USB can\'t be plugged in).\n\n'
                'The board shows "ALLOW WIFI?" — press its LEFT button within '
                '30 s to approve. Buttonless boards approve automatically.',
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              FilledButton(
                onPressed: _loading ? null : _enable,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enable Console WiFi'),
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
              Text(
                '1. Approve on the board if you haven\'t (LEFT button).\n'
                '2. Open your phone\'s WiFi settings.\n'
                '3. Connect to: $_ssid\n'
                '4. Password: $_pass\n\n'
                'If Android warns about no internet, tap YES to stay connected.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _step = 2),
                child: const Text('I\'m Connected — Open Console'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminal() {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: SelectableText(
                _lines.join('\n\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFFE8E8E8),
                ),
              ),
            ),
          ),
        ),
        // Quick chips for the commands you actually want on the bench.
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final c in const [
                'stat',
                'diag',
                'json',
                'vesc faults',
                'cfg',
                'vstat',
                'help',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ActionChip(
                    label: Text(c),
                    onPressed: _running
                        ? null
                        : () {
                            _inputCtrl.text = c;
                            _run();
                          },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            8,
            4,
            8,
            8 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _run(),
                  inputFormatters: [LengthLimitingTextInputFormatter(90)],
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'command',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _running ? null : _run,
                child: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Run'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
