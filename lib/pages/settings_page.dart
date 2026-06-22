import 'package:flutter/material.dart';

import '../ble/esk8os_ble.dart';

/// Board theme names — the firmware recognises these (case-insensitive).
const _themeNames = [
  'CAM',
  'EMBER',
  'ICE',
  'LIGHT',
  'CYBER',
  'SYNTHWAVE',
  'MONO',
  'FOREST',
];

const _accent = Color(0xFFB950D7);

class SettingsPage extends StatefulWidget {
  final Esk8Device dev;
  const SettingsPage({super.key, required this.dev});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  BoardSettings? _settings;
  bool _loading = true;
  bool _writing = false;
  String? _error;
  final _riderCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _riderCtrl.dispose();
    super.dispose();
  }

  // ── BLE helpers ──────────────────────────────────────────────────────────

  Future<void> _read() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.dev.readSettings();
      if (s == null) throw StateError('Empty response from board');
      if (!mounted) return;
      setState(() {
        _settings = s;
        _riderCtrl.text = s.rider;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Write a partial update, re-read to confirm, and show feedback.
  Future<void> _write(Map<String, dynamic> partial, String label) async {
    if (_writing) return; // prevent double-tap
    setState(() => _writing = true);
    try {
      await widget.dev.writeSettings(partial);
      // Re-read to confirm the board accepted the value.
      final s = await widget.dev.readSettings();
      if (s != null && mounted) setState(() => _settings = s);
      _toast('$label updated');
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          // Manual refresh.
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _read,
            tooltip: 'Re-read settings',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _read,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final s = _settings!;
    return AbsorbPointer(
      absorbing: _writing,
      child: AnimatedOpacity(
        opacity: _writing ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // ── Rider ──────────────────────────────────────────────────
            _SectionHeader('RIDER'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: _accent),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _riderCtrl,
                        maxLength: 15,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Rider name',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        onSubmitted: (v) =>
                            _write(BoardSettings.writeJson(rider: v.trim()), 'Rider'),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.check, color: _accent),
                      tooltip: 'Save rider',
                      onPressed: () => _write(
                          BoardSettings.writeJson(rider: _riderCtrl.text.trim()), 'Rider'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Units ──────────────────────────────────────────────────
            _SectionHeader('UNITS'),
            Card(
              child: SwitchListTile(
                title: Text(s.mph ? 'MPH' : 'KM/H',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                subtitle: const Text('Speed & range display unit'),
                secondary: Icon(Icons.speed, color: _accent),
                value: s.mph,
                activeThumbColor: _accent,
                onChanged: (v) =>
                    _write(BoardSettings.writeJson(mph: v), 'Units'),
              ),
            ),

            const SizedBox(height: 16),

            // ── Theme ──────────────────────────────────────────────────
            _SectionHeader('THEME'),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  initialValue: _themeNames.contains(s.theme.toUpperCase())
                      ? s.theme.toUpperCase()
                      : _themeNames.first,
                  decoration: const InputDecoration(
                    icon: Icon(Icons.palette, color: _accent),
                    labelText: 'Board Theme',
                    border: InputBorder.none,
                  ),
                  dropdownColor: const Color(0xFF1E1E1E),
                  items: [
                    for (final t in _themeNames)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _write(BoardSettings.writeJson(theme: v), 'Theme');
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Battery Cells ──────────────────────────────────────────
            _SectionHeader('BATTERY'),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.battery_full, color: _accent),
                        const SizedBox(width: 16),
                        Text('${s.batterySeries}S',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('${(s.batterySeries * 4.2).toStringAsFixed(1)}V max',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 13)),
                      ],
                    ),
                    Slider(
                      value: s.batterySeries.toDouble(),
                      min: 6,
                      max: 14,
                      divisions: 8,
                      label: '${s.batterySeries}S',
                      activeColor: _accent,
                      onChanged: (v) {}, // preview only; write on change end
                      onChangeEnd: (v) => _write(
                        BoardSettings.writeJson(batterySeries: v.round()),
                        'Battery cells',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Battery / Range tuning ─────────────────────────────────
            _SectionHeader('BATTERY / RANGE'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    _SliderRow(
                      icon: Icons.battery_charging_full,
                      label: 'Pack capacity',
                      value: s.packAh.clamp(4.0, 40.0),
                      min: 4, max: 40, divisions: 72,
                      display: '${s.packAh.toStringAsFixed(1)} Ah',
                      onEnd: (v) => _write(BoardSettings.writeJson(packAh: double.parse(v.toStringAsFixed(1))), 'Pack capacity'),
                    ),
                    _SliderRow(
                      icon: Icons.power_settings_new,
                      label: 'Stop-cell voltage',
                      value: s.stopCellV.clamp(3.0, 3.6),
                      min: 3.0, max: 3.6, divisions: 12,
                      display: '${s.stopCellV.toStringAsFixed(2)} V',
                      onEnd: (v) => _write(BoardSettings.writeJson(stopCellV: double.parse(v.toStringAsFixed(2))), 'Stop-cell'),
                    ),
                    _SliderRow(
                      icon: Icons.route,
                      label: 'Range model',
                      value: s.whPerMile.toDouble().clamp(14, 40),
                      min: 14, max: 40, divisions: 26,
                      display: '${s.whPerMile} Wh/mi',
                      onEnd: (v) => _write(BoardSettings.writeJson(whPerMile: v.round()), 'Wh/mi'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Display ────────────────────────────────────────────────
            _SectionHeader('DISPLAY'),
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _SliderRow(
                      icon: Icons.brightness_6,
                      label: 'Brightness',
                      value: s.brightness.toDouble().clamp(10, 100),
                      min: 10, max: 100, divisions: 18,
                      display: '${s.brightness}%',
                      onEnd: (v) => _write(BoardSettings.writeJson(brightness: v.round()), 'Brightness'),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Demo mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Synthetic telemetry (no VESC needed)'),
                    secondary: Icon(Icons.science, color: _accent),
                    value: s.demo,
                    activeThumbColor: _accent,
                    onChanged: (v) => _write(BoardSettings.writeJson(demo: v), 'Demo mode'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Wheel Profile ──────────────────────────────────────────
            _SectionHeader('WHEEL PROFILE'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Profile 0')),
                        ButtonSegment(value: 1, label: Text('Profile 1')),
                      ],
                      selected: {s.profile},
                      onSelectionChanged: (sel) => _write(
                        BoardSettings.writeJson(profile: sel.first),
                        'Profile',
                      ),
                      style: ButtonStyle(
                        foregroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return Colors.grey[400];
                        }),
                        backgroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return _accent.withValues(alpha: 0.25);
                          }
                          return null;
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Read-only derived fields
                    _ReadOnlyField(
                        icon: Icons.settings,
                        label: 'Motor Poles',
                        value: '${s.poles}'),
                    _ReadOnlyField(
                        icon: Icons.trip_origin,
                        label: 'Wheel Diameter',
                        value: '${s.wheelMm} mm'),
                    _ReadOnlyField(
                        icon: Icons.sync,
                        label: 'Gear Ratio',
                        value: s.gear.toStringAsFixed(2)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600)),
      );
}

class _SliderRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String display;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onEnd;
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onEnd,
  });

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late double _v = widget.value;

  @override
  void didUpdateWidget(_SliderRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value; // re-sync after a confirmed write
  }

  @override
  Widget build(BuildContext context) {
    final v = _v.clamp(widget.min, widget.max);
    return Column(
      children: [
        Row(
          children: [
            Icon(widget.icon, color: _accent),
            const SizedBox(width: 16),
            Text(widget.label, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            Text(widget.display, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
        Slider(
          value: v,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          activeColor: _accent,
          label: v.toStringAsFixed(2),
          onChanged: (x) => setState(() => _v = x),
          onChangeEnd: widget.onEnd,
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ReadOnlyField(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: Colors.grey[400])),
            const Spacer(),
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
