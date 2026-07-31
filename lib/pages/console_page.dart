import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/esk8os_ble.dart';
import '../widgets/esk8_widgets.dart';
import '../wifi/wifi_service.dart';

/// Wireless serial console (fw 0.10.3+). Its own entry point, separate from
/// Export/OTA: the device can't be on USB while the vehicle powers it, so this
/// is the way to reach `stat`, `diag`, `vesc faults`, `set`, `json` etc. with
/// the ESC awake.
///
/// The job here is simply to RAISE the device's WiFi and leave it up, so any
/// device — this phone, a laptop, a PC — can connect and use the console at
/// http://192.168.4.1/console (or /cmd?c=... for scripts). It does NOT tear
/// the network down when you leave; the firmware auto-stops it after 10 min
/// idle. An optional in-app terminal is offered for driving it from the phone.
class ConsolePage extends StatefulWidget {
  final Esk8Device dev;
  const ConsolePage({super.key, required this.dev});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  // 0 = not started, 1 = waiting for the on-board L-press approval, 2 = live
  int _phase = 0;
  bool _timedOut = false;
  String? _error;
  Timer? _poll;
  int _elapsed = 0;
  String _ssid = Esk8WifiExport.ssid;
  String _pass = Esk8WifiExport.legacyPassword;

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _lines = <String>[];
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
    } catch (_) {
      /* keep defaults */
    }
  }

  @override
  void dispose() {
    // Intentionally does NOT stop the AP — the whole point is to raise it and
    // walk to another device. The firmware idle-timeout (10 min) cleans up.
    _poll?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    setState(() {
      _phase = 1; // waiting for approval
      _timedOut = false;
      _error = null;
      _elapsed = 0;
    });
    try {
      await widget.dev.sendCommand(Esk8Commands.wifiExportStart);
    } catch (e) {
      setState(() {
        _phase = 0;
        _error = 'Failed to enable device WiFi: $e';
      });
      return;
    }
    // Advance to the live screen ONLY when the device reports the AP is really
    // up (wifiOn flips true after the on-board L-press). Never advance on the
    // send alone — an unapproved request leaves nothing to connect to.
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      _elapsed += 1500;
      try {
        // wifiOn lives on the base-config characteristic (0005), not settings —
        // the settings JSON has no room and adding it there broke the app.
        final base = await widget.dev.readBaseConfig();
        if (!mounted) return;
        if (base != null && base.wifiOn) {
          t.cancel();
          setState(() => _phase = 2);
          return;
        }
      } catch (_) {
        /* keep polling */
      }
      if (_elapsed >= 33000 && mounted) {
        t.cancel();
        setState(() => _timedOut = true); // show "approve on board / continue"
      }
    });
  }

  Future<void> _turnOff() async {
    try {
      await widget.dev.sendCommand(Esk8Commands.wifiExportStop);
    } catch (_) {
      /* best effort */
    }
    if (mounted) Navigator.of(context).pop();
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
      setState(
        () => _lines.add('(no reply — is THIS phone joined to $_ssid? $e)'),
      );
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
    return SubPageScaffold(
      title: 'Wireless Console',
      children: [Expanded(child: _phase == 2 ? _buildLive() : _buildEnable())],
    );
  }

  Widget _buildEnable() {
    final waiting = _phase == 1 && !_timedOut;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Turns on the device\'s WiFi so any device — your PC, a laptop, or '
            'this phone — can reach the console. Same console as USB serial, '
            'but usable while the vehicle is powered (when USB can\'t be '
            'plugged in).\n\n'
            'The device shows "ALLOW WIFI?" — press its LEFT button within 30 s '
            'to approve. Buttonless devices approve automatically.',
          ),
          const SizedBox(height: 20),
          if (waiting) ...[
            Row(
              children: const [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Press the device\'s LEFT button to approve — waiting for '
                    'the network to come up…',
                  ),
                ),
              ],
            ),
          ] else if (_timedOut) ...[
            const Text(
              'The device never reported its WiFi on. Approve on the device '
              '(LEFT button) and try again — or, on older firmware that can\'t '
              'report status, continue once you\'ve approved it.',
              style: TextStyle(color: Colors.orangeAccent),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _enable,
                    child: const Text('Try Again'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _phase = 2),
                    child: const Text('Continue Anyway'),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            FilledButton.icon(
              onPressed: _enable,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Turn On Console WiFi'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLive() {
    return Column(
      children: [
        // Status + how to connect — the primary content, since the usual
        // client is a separate device, not this phone.
        Container(
          width: double.infinity,
          color: Colors.green.withValues(alpha: 0.10),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.wifi_tethering, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'CONSOLE WiFi ON',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _copyRow('network', _ssid),
              _copyRow('password', _pass),
              _copyRow('browser', 'http://192.168.4.1/console'),
              _copyRow('scripts', 'http://192.168.4.1/cmd?c=<command>'),
              const SizedBox(height: 8),
              const Text(
                'Connect any device to that network, then open the browser URL '
                '(or curl the scripts URL). Stays on for 10 min of no activity.',
                style: TextStyle(color: Colors.grey, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _turnOff,
                icon: const Icon(Icons.wifi_off, size: 18),
                label: const Text('Turn Off'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: const [
              Icon(Icons.smartphone, size: 15, color: Colors.grey),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Or run from this phone (requires THIS phone joined to the '
                  'device WiFi):',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _terminal()),
      ],
    );
  }

  Widget _copyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('copied $label'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy, size: 16, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _terminal() {
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
                _lines.isEmpty
                    ? 'type a command (try: help)'
                    : _lines.join('\n\n'),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.4,
                  color: _lines.isEmpty
                      ? const Color(0xFF666666)
                      : const Color(0xFFE8E8E8),
                ),
              ),
            ),
          ),
        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
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
