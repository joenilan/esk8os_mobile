import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../ble/esk8os_ble.dart';
import '../database/trip_database.dart';
import '../services/app_prefs.dart';
import 'wifi_export_page.dart';
import '../widgets/esk8_widgets.dart';
import '../widgets/esk8_theme.dart';

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

Color get _accent => Esk8Theme.accent; // follows the board's selected theme
const _hudFaces = ['speed', 'battery', 'volts', 'watts', 'safety'];
const _batteryFocuses = ['pct', 'volts'];

class SettingsPage extends StatefulWidget {
  final Esk8Device dev;
  final Telemetry? telemetry;
  const SettingsPage({super.key, required this.dev, this.telemetry});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  BoardSettings? _settings;
  _RangeCalibration? _lastTripCalibration;
  _RangeCalibration? _learnedCalibration;
  bool _loading = true;
  bool _loadingLastTrip = true;
  bool _writing = false;
  String? _error;
  double? _pendingWhPerMile;
  Timer? _whPerMileSaveTimer;
  final _riderCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _read();
    _readLastTripCalibration();
  }

  @override
  void dispose() {
    _whPerMileSaveTimer?.cancel();
    _riderCtrl.dispose();
    _nameCtrl.dispose();
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
      Esk8Theme.applyTheme(s.theme);
      setState(() {
        _settings = s;
        _riderCtrl.text = s.rider;
        _nameCtrl.text = s.deviceName;
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

  Future<void> _readLastTripCalibration() async {
    try {
      final trip = await TripDatabase.instance.getLatestRangeCalibrationTrip();
      final trips = await TripDatabase.instance
          .getRecentRangeCalibrationTrips();
      if (!mounted) return;
      setState(() {
        _lastTripCalibration = _RangeCalibration.fromTrip(trip);
        _learnedCalibration = _RangeCalibration.fromTrips(trips);
        _loadingLastTrip = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastTripCalibration = null;
        _loadingLastTrip = false;
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
      if (s != null && mounted) {
        Esk8Theme.applyTheme(s.theme);
        setState(() => _settings = s);
      }
      _toast('$label updated');
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _command(String command, String label) async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      await widget.dev.sendCommand(command);
      _toast('$label sent');
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _confirmCommand({
    required String command,
    required String label,
    required String message,
    String confirmText = 'Send',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    if (ok == true) await _command(command, label);
  }

  double _cleanWhPerMile(double value) =>
      double.parse(value.clamp(14.0, 40.0).toStringAsFixed(1));

  Future<void> _writeWhPerMileNow(double value) async {
    _whPerMileSaveTimer?.cancel();
    final cleaned = _cleanWhPerMile(value);
    if (mounted) setState(() => _pendingWhPerMile = cleaned);
    await _write(BoardSettings.writeJson(whPerMile: cleaned), 'Wh/mi');
    if (mounted) setState(() => _pendingWhPerMile = null);
  }

  void _queueWhPerMile(double value) {
    final cleaned = _cleanWhPerMile(value);
    setState(() => _pendingWhPerMile = cleaned);
    _whPerMileSaveTimer?.cancel();
    _whPerMileSaveTimer = Timer(const Duration(milliseconds: 900), () async {
      await _write(BoardSettings.writeJson(whPerMile: cleaned), 'Wh/mi');
      if (mounted) setState(() => _pendingWhPerMile = null);
    });
  }

  Future<void> _editWhPerMile(double currentValue) async {
    final ctrl = TextEditingController(text: currentValue.toStringAsFixed(1));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Range model'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Wh/mi',
            helperText: '14.0 to 40.0',
          ),
          onSubmitted: (_) {
            Navigator.of(context).pop(double.tryParse(ctrl.text.trim()));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(double.tryParse(ctrl.text.trim()));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    if (!result.isFinite) {
      _toast('Enter a valid Wh/mi');
      return;
    }
    await _writeWhPerMileNow(result);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _hardwareLabel(BoardSettings s) {
    if (s.hardware == 'tdisplay-s3') return 'LILYGO T-Display S3';
    if (s.hardware == 'esp32s3-oled') return 'ESP32-S3 OLED';
    if (s.hardware == 'esp32s3-headless') return 'ESP32-S3 Headless';
    return s.hardware.isNotEmpty ? s.hardware : 'Unknown hardware';
  }

  String _uiLabel(BoardSettings s) {
    final display = switch (s.display) {
      'tft' => 'full TFT display',
      'oled' => 'small OLED display',
      'none' => 'no onboard display',
      _ => '${s.display} display',
    };
    final input = s.hasButtons ? 'local buttons' : 'phone controlled';
    return '$display · ${s.ui} UI · $input';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Esk8Theme.scaffold,
      body: Column(
        children: [
          SubPageHeader(
            title: 'Settings',
            actions: [
              IconButton(
                icon: Icon(Icons.refresh, color: Esk8Theme.accent),
                onPressed: _loading ? null : _read,
                tooltip: 'Re-read settings',
              ),
            ],
          ),
          Expanded(child: _buildBody()),
        ],
      ),
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
    final rangeWhPerMile = _pendingWhPerMile ?? s.whPerMile;
    final rangeCalibration = _RangeCalibration.from(s, widget.telemetry);
    final lastTripCalibration = _lastTripCalibration;
    final hasOnboardDisplay = s.display != 'none';
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, color: _accent),
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
                        onSubmitted: (v) => _write(
                          BoardSettings.writeJson(rider: v.trim()),
                          'Rider',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.check, color: _accent),
                      tooltip: 'Save rider',
                      onPressed: () => _write(
                        BoardSettings.writeJson(rider: _riderCtrl.text.trim()),
                        'Rider',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Board identity (name + vehicle type) ───────────────────
            _SectionHeader('BOARD'),
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(Vehicle.icon(s.vehicleType), color: _accent),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _nameCtrl,
                            maxLength: 18,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Board name',
                              helperText:
                                  'Shown in the scan list · reboot to re-advertise',
                              border: InputBorder.none,
                              counterText: '',
                            ),
                            onSubmitted: (v) => _write(
                              BoardSettings.writeJson(deviceName: v.trim()),
                              'Board name',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.check, color: _accent),
                          tooltip: 'Save name',
                          onPressed: () => _write(
                            BoardSettings.writeJson(
                              deviceName: _nameCtrl.text.trim(),
                            ),
                            'Board name',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.category, color: _accent),
                            SizedBox(width: 16),
                            Text(
                              'Vehicle type',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: [
                              for (var i = 0; i < Vehicle.count; i++)
                                ButtonSegment(
                                  value: i,
                                  icon: Icon(Vehicle.icon(i)),
                                  tooltip: Vehicle.label(i),
                                ),
                            ],
                            selected: {
                              s.vehicleType.clamp(0, Vehicle.count - 1),
                            },
                            onSelectionChanged: (sel) => _write(
                              BoardSettings.writeJson(vehicleType: sel.first),
                              'Vehicle type',
                            ),
                            style: ButtonStyle(
                              foregroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : Colors.grey[400],
                              ),
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? _accent.withValues(alpha: 0.25)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Vehicle.label(s.vehicleType),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Units ──────────────────────────────────────────────────
            _SectionHeader('UNITS'),
            Card(
              child: SwitchListTile(
                title: Text(
                  s.mph ? 'MPH' : 'KM/H',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: DropdownButtonFormField<String>(
                  initialValue: _themeNames.contains(s.theme.toUpperCase())
                      ? s.theme.toUpperCase()
                      : _themeNames.first,
                  decoration: InputDecoration(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.battery_full, color: _accent),
                        const SizedBox(width: 16),
                        Text(
                          '${s.batterySeries}S',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(s.batterySeries * 4.2).toStringAsFixed(1)}V max',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                        ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    _SliderRow(
                      icon: Icons.battery_charging_full,
                      label: 'Pack capacity',
                      value: s.packAh.clamp(4.0, 40.0),
                      min: 4,
                      max: 40,
                      divisions: 72,
                      display: '${s.packAh.toStringAsFixed(1)} Ah',
                      onEnd: (v) => _write(
                        BoardSettings.writeJson(
                          packAh: double.parse(v.toStringAsFixed(1)),
                        ),
                        'Pack capacity',
                      ),
                    ),
                    _SliderRow(
                      icon: Icons.home,
                      label: 'Ride-home voltage',
                      value: s.homeCellV.clamp(s.stopCellV, 4.2),
                      min: s.stopCellV,
                      max: 4.2,
                      divisions: ((4.2 - s.stopCellV) / 0.05).round(),
                      display:
                          '${s.homeCellV.toStringAsFixed(2)} V/cell  ${(s.homeCellV * s.batterySeries).toStringAsFixed(1)} V pack',
                      onEnd: (v) => _write(
                        BoardSettings.writeJson(
                          homeCellV: double.parse(v.toStringAsFixed(2)),
                        ),
                        'Ride-home voltage',
                      ),
                    ),
                    _SliderRow(
                      icon: Icons.power_settings_new,
                      label: 'Limp floor voltage',
                      value: s.stopCellV.clamp(3.0, 3.6),
                      min: 3.0,
                      max: 3.6,
                      divisions: 12,
                      display:
                          '${s.stopCellV.toStringAsFixed(2)} V/cell  ${(s.stopCellV * s.batterySeries).toStringAsFixed(1)} V pack',
                      onEnd: (v) => _write(
                        BoardSettings.writeJson(
                          stopCellV: double.parse(v.toStringAsFixed(2)),
                        ),
                        'Limp floor',
                      ),
                    ),
                    _RangeModelControl(
                      value: rangeWhPerMile,
                      pending: _pendingWhPerMile != null,
                      onStep: (delta) =>
                          _queueWhPerMile(rangeWhPerMile + delta),
                      onExact: () => _editWhPerMile(rangeWhPerMile),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.auto_mode, color: _accent),
                      title: const Text(
                        'Auto-learn range',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Starts at 22.0 Wh/mi, then learns from 2+ mi / 20+ Wh trips',
                      ),
                      value: AppPrefs.autoLearnRange,
                      onChanged: (v) =>
                          setState(() => AppPrefs.autoLearnRange = v),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.auto_graph, color: _accent),
                      title: const Text(
                        'Calibrate range from ride',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(rangeCalibration.subtitle),
                      trailing: FilledButton(
                        onPressed: rangeCalibration.canUse
                            ? () => _write(
                                BoardSettings.writeJson(
                                  whPerMile: rangeCalibration.whPerMile,
                                ),
                                'Range model',
                              )
                            : null,
                        child: const Text('Use'),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.insights, color: _accent),
                      title: const Text(
                        'Use learned model',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _loadingLastTrip
                            ? 'Checking trip history'
                            : _learnedCalibration?.subtitle ??
                                  'Need longer recorded trips first',
                      ),
                      trailing: FilledButton(
                        onPressed:
                            _learnedCalibration != null &&
                                _learnedCalibration!.canUse
                            ? () => _write(
                                BoardSettings.writeJson(
                                  whPerMile: _learnedCalibration!.whPerMile,
                                ),
                                'Range model',
                              )
                            : null,
                        child: const Text('Use'),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.history, color: _accent),
                      title: const Text(
                        'Use last recorded trip',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _loadingLastTrip
                            ? 'Checking trip history'
                            : lastTripCalibration?.subtitle ??
                                  'No recorded trip with board energy yet',
                      ),
                      trailing: FilledButton(
                        onPressed:
                            lastTripCalibration != null &&
                                lastTripCalibration.canUse
                            ? () => _write(
                                BoardSettings.writeJson(
                                  whPerMile: lastTripCalibration.whPerMile,
                                ),
                                'Range model',
                              )
                            : null,
                        child: const Text('Use'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Display ────────────────────────────────────────────────
            _SectionHeader('BOARD UI'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.developer_board, color: _accent),
                    title: Text(
                      _hardwareLabel(s),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(_uiLabel(s)),
                    trailing: s.hasButtons
                        ? const Icon(Icons.keyboard_alt_outlined)
                        : const Icon(Icons.smartphone),
                  ),
                  if (!hasOnboardDisplay)
                    const ListTile(
                      leading: Icon(Icons.visibility_off),
                      title: Text(
                        'Phone-only dashboard',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'This firmware has no local display, so ride controls live in the app',
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: _SliderRow(
                        icon: Icons.brightness_6,
                        label: 'Brightness',
                        value: s.brightness.toDouble().clamp(10, 100),
                        min: 10,
                        max: 100,
                        divisions: 18,
                        display: '${s.brightness}%',
                        onEnd: (v) => _write(
                          BoardSettings.writeJson(brightness: v.round()),
                          'Brightness',
                        ),
                      ),
                    ),
                    _SegmentedStringRow(
                      icon: Icons.dashboard_customize,
                      label: s.display == 'oled' ? 'OLED face' : 'Board HUD',
                      values: _hudFaces,
                      selected: _hudFaces.contains(s.hudFace)
                          ? s.hudFace
                          : 'speed',
                      labels: const {
                        'speed': 'Speed',
                        'battery': 'Battery',
                        'volts': 'Volts',
                        'watts': 'Watts',
                        'safety': 'Safety',
                      },
                      onChanged: (v) => _write(
                        BoardSettings.writeJson(hudFace: v),
                        s.display == 'oled' ? 'OLED face' : 'Board HUD',
                      ),
                    ),
                    if (s.display != 'oled')
                      _SegmentedStringRow(
                        icon: Icons.battery_unknown,
                        label: 'Battery focus',
                        values: _batteryFocuses,
                        selected: _batteryFocuses.contains(s.batteryFocus)
                            ? s.batteryFocus
                            : 'pct',
                        labels: const {'pct': 'Percent', 'volts': 'Volts'},
                        onChanged: (v) => _write(
                          BoardSettings.writeJson(batteryFocus: v),
                          'Battery focus',
                        ),
                      ),
                    if (s.display == 'oled')
                      SwitchListTile(
                        title: Text(
                          s.oledInvert ? 'OLED light mode' : 'OLED dark mode',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text('Invert black and white pixels'),
                        secondary: Icon(Icons.invert_colors, color: _accent),
                        value: s.oledInvert,
                        activeThumbColor: _accent,
                        onChanged: (v) => _write(
                          BoardSettings.writeJson(oledInvert: v),
                          'OLED mode',
                        ),
                      ),
                  ],
                  SwitchListTile(
                    title: const Text(
                      'Status RGB LED',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      hasOnboardDisplay
                          ? 'On-board status indicator light'
                          : 'Headless status indicator light',
                    ),
                    secondary: Icon(Icons.lightbulb_outline, color: _accent),
                    value: s.statusRgb,
                    activeThumbColor: _accent,
                    onChanged: (v) => _write(
                      BoardSettings.writeJson(statusRgb: v),
                      'Status RGB',
                    ),
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Demo mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Synthetic telemetry (no VESC needed)',
                    ),
                    secondary: Icon(Icons.science, color: _accent),
                    value: s.demo,
                    activeThumbColor: _accent,
                    onChanged: (v) =>
                        _write(BoardSettings.writeJson(demo: v), 'Demo mode'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Board controls ────────────────────────────────────────
            _SectionHeader('BOARD CONTROLS'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.restart_alt, color: _accent),
                    title: const Text(
                      'Reset board trip',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Clears the board trip distance, moving time, and session stats',
                    ),
                    onTap: () => _confirmCommand(
                      command: Esk8Commands.tripReset,
                      label: 'Reset board trip',
                      message:
                          'This clears the trip counters stored on the ESP32. Recorded phone trips are not deleted.',
                      confirmText: 'Reset',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.wifi_tethering, color: _accent),
                    title: const Text(
                      'Logs / OTA WiFi',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Start the board WiFi AP for session files and firmware updates',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WifiExportPage(dev: widget.dev),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.cable, color: _accent),
                    title: const Text(
                      'VESC Tool bridge',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Starts the board TCP bridge; stop the board before using it',
                    ),
                    onTap: () => _confirmCommand(
                      command: Esk8Commands.bridgeMode,
                      label: 'Start VESC bridge',
                      message:
                          'Only use bridge mode while stopped. The board will expose ESK8-BRIDGE for desktop VESC Tool at 192.168.4.1:65102.',
                      confirmText: 'Start',
                    ),
                  ),
                  if (hasOnboardDisplay)
                    OverflowBar(
                      alignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _command(
                            Esk8Commands.pagePrev,
                            'Board page previous',
                          ),
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Prev page'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _command(
                            Esk8Commands.pageNext,
                            'Board page next',
                          ),
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Next page'),
                        ),
                      ],
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.power_settings_new, color: _accent),
                    title: const Text(
                      'Reboot board',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Restarts the ESP32 controller only'),
                    onTap: () => _confirmCommand(
                      command: Esk8Commands.reboot,
                      label: 'Reboot board',
                      message:
                          'The phone will disconnect briefly while the ESP32 restarts.',
                      confirmText: 'Reboot',
                    ),
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
                        foregroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return Colors.grey[400];
                        }),
                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
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
                      value: '${s.poles}',
                    ),
                    _ReadOnlyField(
                      icon: Icons.trip_origin,
                      label: 'Wheel Diameter',
                      value: '${s.wheelMm} mm',
                    ),
                    _ReadOnlyField(
                      icon: Icons.sync,
                      label: 'Gear Ratio',
                      value: s.gear.toStringAsFixed(2),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Ride tracking (app-local prefs) ────────────────────────
            _SectionHeader('RIDE TRACKING'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      'Auto record',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Start/stop a trip automatically from movement',
                    ),
                    secondary: Icon(Icons.fiber_manual_record, color: _accent),
                    value: AppPrefs.autoTrip,
                    activeThumbColor: _accent,
                    onChanged: (v) => setState(() => AppPrefs.autoTrip = v),
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Floating window',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Stats bubble over other apps when a recording trip is backgrounded',
                    ),
                    secondary: Icon(
                      Icons.picture_in_picture_alt,
                      color: _accent,
                    ),
                    value: AppPrefs.overlayEnabled,
                    activeThumbColor: _accent,
                    onChanged: (v) async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (v &&
                          !await FlutterOverlayWindow.isPermissionGranted()) {
                        await FlutterOverlayWindow.requestPermission();
                        if (!await FlutterOverlayWindow.isPermissionGranted()) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Grant "Display over other apps" to use the floating window',
                              ),
                            ),
                          );
                          return;
                        }
                      }
                      setState(() => AppPrefs.overlayEnabled = v);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.open_in_new, color: _accent),
                    title: const Text(
                      'Test floating window',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Show it now to check it appears / drags / taps — no trip needed',
                    ),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (!await FlutterOverlayWindow.isPermissionGranted()) {
                        await FlutterOverlayWindow.requestPermission();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Grant the permission, then tap Test again',
                            ),
                          ),
                        );
                        return;
                      }
                      if (await FlutterOverlayWindow.isActive()) {
                        await FlutterOverlayWindow.closeOverlay();
                        return;
                      }
                      await FlutterOverlayWindow.showOverlay(
                        height: 360,
                        width: 360,
                        alignment: OverlayAlignment.center,
                        enableDrag: true,
                        positionGravity: PositionGravity.none,
                        overlayTitle: 'ESK8OS trip',
                        flag: OverlayFlag.defaultFlag,
                      );
                      await Future.delayed(const Duration(milliseconds: 300));
                      await FlutterOverlayWindow.shareData(
                        jsonEncode({
                          'spd': '12',
                          'unit': s.mph ? 'MPH' : 'KM/H',
                          'trip': '0.42',
                          'tu': s.mph ? 'mi' : 'km',
                          'time': '2m 5s',
                          'paused': false,
                          // Sample fix so the map renders during a no-trip test.
                          'lat': 37.7749,
                          'lng': -122.4194,
                          'hdg': 45.0,
                        }),
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bubble shown — drag it, tap it to return, or tap Test again to close',
                          ),
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: _SliderRow(
                      icon: Icons.notifications_active,
                      label: 'Over-speed alert',
                      value: AppPrefs.speedAlert.clamp(0, 50),
                      min: 0,
                      max: 50,
                      divisions: 50,
                      display: AppPrefs.speedAlert <= 0
                          ? 'Off'
                          : '${AppPrefs.speedAlert.toStringAsFixed(0)} ${s.mph ? 'mph' : 'km/h'}',
                      onEnd: (v) => setState(
                        () => AppPrefs.speedAlert = v.roundToDouble(),
                      ),
                    ),
                  ),
                ],
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

class _RangeCalibration {
  static const double _kmPerMile = 1.609344;
  final double whPerMile;
  final String subtitle;
  final bool canUse;
  final int sampleCount;

  const _RangeCalibration._({
    required this.whPerMile,
    required this.subtitle,
    required this.canUse,
    this.sampleCount = 0,
  });

  factory _RangeCalibration.from(BoardSettings settings, Telemetry? telemetry) {
    if (telemetry == null) {
      return const _RangeCalibration._(
        whPerMile: 0,
        subtitle: 'Waiting for live board telemetry',
        canUse: false,
      );
    }

    final tripMiles = settings.mph
        ? telemetry.trip
        : telemetry.trip / _kmPerMile;
    final netWh = telemetry.wattHours - telemetry.regenWh;
    final usedWh = netWh > 0 ? netWh : 0.0;

    if (tripMiles < 2.0) {
      return const _RangeCalibration._(
        whPerMile: 0,
        subtitle: 'Ride at least 2.0 mi before calibrating',
        canUse: false,
      );
    }
    if (usedWh < 20.0) {
      return const _RangeCalibration._(
        whPerMile: 0,
        subtitle: 'Use at least 20 Wh before calibrating',
        canUse: false,
      );
    }

    final rawWhPerMile = usedWh / tripMiles;
    if (!rawWhPerMile.isFinite) {
      return const _RangeCalibration._(
        whPerMile: 0,
        subtitle: 'Need valid energy and distance data',
        canUse: false,
      );
    }

    final clampedWhPerMile = rawWhPerMile.clamp(14.0, 40.0);
    final roundedWhPerMile = double.parse(clampedWhPerMile.toStringAsFixed(1));
    return _RangeCalibration._(
      whPerMile: roundedWhPerMile,
      subtitle:
          '${usedWh.toStringAsFixed(1)} Wh / ${tripMiles.toStringAsFixed(2)} mi = ${roundedWhPerMile.toStringAsFixed(1)} Wh/mi',
      canUse: true,
      sampleCount: 1,
    );
  }

  factory _RangeCalibration.fromTrip(Map<String, dynamic>? trip) {
    if (trip == null) {
      return const _RangeCalibration._(
        whPerMile: 0,
        subtitle: 'No recorded trip with board energy yet',
        canUse: false,
      );
    }

    final tripMiles = _num(trip['boardDistanceMi']);
    final wattHours = _num(trip['wattHours']);
    final regenWh = _num(trip['regenWh']);
    final storedEff = _num(trip['effWhMi']);
    final usedWh = wattHours - regenWh;
    final rawWhPerMile = storedEff > 0
        ? storedEff
        : (tripMiles > 0 ? usedWh / tripMiles : 0.0);

    if (tripMiles < 2.0 || usedWh < 20.0 || !rawWhPerMile.isFinite) {
      return const _RangeCalibration._(
        whPerMile: 0,
        subtitle: 'No 2+ mi / 20+ Wh recorded trip yet',
        canUse: false,
      );
    }

    final roundedWhPerMile = double.parse(
      rawWhPerMile.clamp(14.0, 40.0).toStringAsFixed(1),
    );
    return _RangeCalibration._(
      whPerMile: roundedWhPerMile,
      subtitle:
          '${usedWh.toStringAsFixed(1)} Wh / ${tripMiles.toStringAsFixed(2)} mi = ${roundedWhPerMile.toStringAsFixed(1)} Wh/mi',
      canUse: true,
      sampleCount: 1,
    );
  }

  factory _RangeCalibration.fromTrips(List<Map<String, dynamic>> trips) {
    double totalMiles = 0;
    double totalWh = 0;
    var count = 0;

    for (final trip in trips) {
      final tripMiles = _num(trip['boardDistanceMi']);
      final usedWh = _num(trip['wattHours']) - _num(trip['regenWh']);
      final eff = _num(trip['effWhMi']);
      if (tripMiles < 2.0 || usedWh < 20.0 || eff < 14.0 || eff > 40.0) {
        continue;
      }
      totalMiles += tripMiles;
      totalWh += usedWh;
      count++;
    }

    if (count == 0 || totalMiles <= 0 || totalWh <= 0) {
      return const _RangeCalibration._(
        whPerMile: 0,
        subtitle: 'Need a 2+ mi / 20+ Wh recorded trip first',
        canUse: false,
      );
    }

    final whPerMile = double.parse(
      (totalWh / totalMiles).clamp(14.0, 40.0).toStringAsFixed(1),
    );
    return _RangeCalibration._(
      whPerMile: whPerMile,
      subtitle:
          '$count trip${count == 1 ? '' : 's'} · ${totalWh.toStringAsFixed(1)} Wh / ${totalMiles.toStringAsFixed(2)} mi = ${whPerMile.toStringAsFixed(1)} Wh/mi',
      canUse: true,
      sampleCount: count,
    );
  }

  static double _num(dynamic value) => value is num ? value.toDouble() : 0.0;
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey[500],
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    ),
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
    if (old.value != widget.value) {
      _v = widget.value; // re-sync after a confirmed write
    }
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
            Text(
              widget.display,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
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

class _RangeModelControl extends StatelessWidget {
  final double value;
  final bool pending;
  final ValueChanged<double> onStep;
  final VoidCallback onExact;

  const _RangeModelControl({
    required this.value,
    required this.pending,
    required this.onStep,
    required this.onExact,
  });

  @override
  Widget build(BuildContext context) {
    final display = value.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.route, color: _accent),
              const SizedBox(width: 16),
              const Text('Range model', style: TextStyle(fontSize: 16)),
              const Spacer(),
              Text(
                pending ? 'saving...' : '14.0-40.0 Wh/mi',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 36),
              IconButton.filledTonal(
                tooltip: '-0.1 Wh/mi',
                onPressed: value <= 14.0 ? null : () => onStep(-0.1),
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onExact,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: _accent.withValues(alpha: 0.8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    '$display Wh/mi',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: '+0.1 Wh/mi',
                onPressed: value >= 40.0 ? null : () => onStep(0.1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ReadOnlyField({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: Colors.grey[400])),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}

class _SegmentedStringRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> values;
  final String selected;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  const _SegmentedStringRow({
    required this.icon,
    required this.label,
    required this.values,
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _accent),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [
              for (final v in values)
                ButtonSegment(value: v, label: Text(labels[v] ?? v)),
            ],
            selected: {selected},
            onSelectionChanged: (sel) => onChanged(sel.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return Colors.grey[400];
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _accent.withValues(alpha: 0.25);
                }
                return null;
              }),
            ),
          ),
        ),
      ],
    ),
  );
}
