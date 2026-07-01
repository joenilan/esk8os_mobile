import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../database/trip_database.dart';
import '../services/app_prefs.dart';
import '../services/trip_share.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

class TripPlaybackPage extends StatefulWidget {
  final int tripId;
  final bool isMph;
  final Map<String, dynamic> tripData;

  const TripPlaybackPage({
    super.key,
    required this.tripId,
    required this.isMph,
    required this.tripData,
  });

  @override
  State<TripPlaybackPage> createState() => _TripPlaybackPageState();
}

class _TripPlaybackPageState extends State<TripPlaybackPage>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  // Drives playback at vsync (60 fps) so the marker glides continuously instead
  // of stepping; value 0..1 maps to the fractional scrub position _pos.
  late final AnimationController _playCtrl;
  // Cached map layers so the heavy 1578-pt route line isn't rebuilt/re-simplified
  // every animation frame (that was dropping frames -> the marker "pulsed"). The
  // full route is fully static; the trail only changes when _idx crosses a point.
  Widget? _routeLayer;
  Widget? _trailLayer;
  int _trailForIdx = -1;

  static const _routeColor = Color(0xFFB950D7);
  // Static marker dot (const) — only its position changes, so it never rebuilds.
  static const Widget _markerDot = DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.fromBorderSide(BorderSide(color: _routeColor, width: 3)),
      boxShadow: [
        BoxShadow(color: Color(0xCCB950D7), blurRadius: 10, spreadRadius: 2),
      ],
    ),
  );
  List<Map<String, dynamic>> _telemetry = [];
  List<LatLng> _route = [];
  // Keyframes = (pointIndex, position) only where the position actually CHANGED.
  // The GPS updates ~every 5s but we log 1 Hz, so ~80% of points are duplicates;
  // the marker must glide between distinct fixes (spread over the duplicate span),
  // not interpolate between identical points (which looks like stop-go-stop-go).
  final List<(double, LatLng)> _keyframes =
      []; // (cumulativeDistance, position)
  // Speed-integrated distance per point: lets the marker hold still at real stops
  // (speed ~0) and glide while moving, instead of drifting across stopped time.
  List<double> _cumDist = [];
  bool _isLoading = true;
  bool _mapReady = false;

  // Fractional scrub position (0..len-1), DERIVED from the controller so the
  // marker can sit between points and glide. Reading it from the controller (not
  // a setState-updated field) lets us animate the marker via AnimatedBuilder
  // WITHOUT rebuilding the whole map every frame (that was the real stutter).
  double get _pos => _telemetry.length < 2 ? 0.0 : _playCtrl.value * _maxPos;
  bool _isPlaying = false;
  bool _showGraphs = false;
  bool _gpsCompare = true;
  // Map style is shared with the live trip map (AppPrefs.mapLight) so playback
  // matches what you ride with; the toggle here flips that same pref.
  bool _mapLight = AppPrefs.mapLight;
  bool _follow = false; // recenter the camera on the marker as it moves

  int get _idx =>
      _pos.round().clamp(0, _telemetry.isEmpty ? 0 : _telemetry.length - 1);

  @override
  void initState() {
    super.initState();
    _playCtrl = AnimationController(vsync: this)
      ..addListener(() {
        // No setState here — the marker/trail/stats/slider are AnimatedBuilders on
        // this controller, so they repaint WITHOUT rebuilding the map (the cause of
        // the pulsing). Only follow-mode needs to move the camera per frame.
        if (mounted && _follow) {
          _recenterIfFollow();
        }
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _isPlaying = false);
        }
      });
    _loadTelemetry();
  }

  double get _maxPos => (_telemetry.length - 1).clamp(1, 1 << 30).toDouble();

  Future<void> _loadTelemetry() async {
    final data = await TripDatabase.instance.getTripTelemetry(widget.tripId);
    if (mounted) {
      setState(() {
        _telemetry = data;
        _route = data
            .map((t) => LatLng(t['lat'] as double, t['lng'] as double))
            .toList();
        _isLoading = false;
      });
      // ~80 ms per recorded point; scrubbable either way.
      if (_telemetry.length > 1) {
        _playCtrl.duration = Duration(milliseconds: (_maxPos * 80).round());
      }
      // Cumulative distance from speed (1 Hz log => +speed m each point). Deadband
      // tiny speeds to 0 so stops are crisp (no drift). If there's no usable speed
      // data, fall back to index so it still plays (just without true stops).
      _cumDist = List<double>.filled(_telemetry.length, 0);
      for (var i = 1; i < _telemetry.length; i++) {
        final v = (_telemetry[i]['gpsSpeed'] as num?)?.toDouble() ?? 0.0; // m/s
        _cumDist[i] = _cumDist[i - 1] + (v < 0.4 ? 0.0 : v);
      }
      if (_cumDist.isEmpty || _cumDist.last < 1.0) {
        for (var i = 0; i < _cumDist.length; i++) {
          _cumDist[i] = i.toDouble();
        }
      }
      // Keyframes at distinct GPS positions, keyed by cumulative distance (must
      // strictly increase — ignores GPS jitter while stopped).
      _keyframes.clear();
      if (_route.isNotEmpty) {
        _keyframes.add((0, _route.first));
        for (var i = 1; i < _route.length; i++) {
          if (_dist(_route[i], _keyframes.last.$2) > 0.5 &&
              _cumDist[i] > _keyframes.last.$1) {
            _keyframes.add((_cumDist[i], _route[i]));
          }
        }
        final lastD = _cumDist[_route.length - 1];
        if (_keyframes.last.$2 != _route.last && lastD > _keyframes.last.$1) {
          _keyframes.add((lastD, _route.last));
        }
      }
      // Cache the static full-route line once (identical instance => Flutter skips
      // rebuilding it each frame).
      if (_route.length >= 2) {
        _routeLayer = PolylineLayer(
          polylines: [
            Polyline(
              points: _route,
              strokeWidth: 4.0,
              color: _routeColor.withValues(alpha: 0.5),
            ),
          ],
        );
      }

      if (_route.isNotEmpty) {
        // Delay map fit bounds slightly so map is ready
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            final bounds = LatLngBounds.fromPoints(_route);
            if (bounds.southWest.latitude == bounds.northEast.latitude &&
                bounds.southWest.longitude == bounds.northEast.longitude) {
              _mapController.move(_route.first, 16.0);
            } else {
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(50),
                ),
              );
            }
          }
        });
      }
    }
  }

  static double _dist(LatLng a, LatLng b) {
    final dLat = (a.latitude - b.latitude) * 111320;
    final dLng =
        (a.longitude - b.longitude) * 111320 * cos(a.latitude * pi / 180);
    return sqrt(dLat * dLat + dLng * dLng);
  }

  /// Marker position at the current scrub time. Advances by speed-integrated
  /// distance (so it HOLDS at real stops and glides while moving), mapped onto the
  /// distinct-GPS-fix keyframes (so it glides across duplicate logged points).
  LatLng _markerPos() {
    if (_keyframes.isEmpty) {
      return _route.isEmpty ? const LatLng(0, 0) : _route.first;
    }
    // Traveled distance at the current playback time (interpolate cumDist by _pos).
    final lo0 = _pos.floor().clamp(0, _cumDist.length - 1);
    final hi0 = (lo0 + 1).clamp(0, _cumDist.length - 1);
    final d = _cumDist[lo0] + (_cumDist[hi0] - _cumDist[lo0]) * (_pos - lo0);
    // Keyframe segment containing distance d (binary search).
    int lo = 0, hi = _keyframes.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_keyframes[mid].$1 <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final a = _keyframes[lo];
    if (lo >= _keyframes.length - 1) return a.$2;
    final b = _keyframes[lo + 1];
    final span = b.$1 - a.$1;
    final frac = span <= 0 ? 0.0 : ((d - a.$1) / span).clamp(0.0, 1.0);
    return LatLng(
      a.$2.latitude + (b.$2.latitude - a.$2.latitude) * frac,
      a.$2.longitude + (b.$2.longitude - a.$2.longitude) * frac,
    );
  }

  /// Traveled-trail line — rebuilt only when the integer point index changes
  /// (not every frame), so it doesn't re-simplify the growing path 60x/sec.
  Widget _buildTrailLayer() {
    if (_trailLayer == null || _trailForIdx != _idx) {
      _trailForIdx = _idx;
      _trailLayer = PolylineLayer(
        polylines: [
          Polyline(
            points: _route.sublist(0, _idx + 1),
            strokeWidth: 4.0,
            color: _routeColor,
          ),
        ],
      );
    }
    return _trailLayer!;
  }

  void _recenterIfFollow() {
    if (!_follow || !_mapReady || _route.isEmpty) return;
    try {
      _mapController.move(_markerPos(), _mapController.camera.zoom);
    } catch (_) {}
  }

  void _togglePlayback() {
    if (_telemetry.length < 2) return;
    if (_isPlaying) {
      _playCtrl.stop();
      setState(() => _isPlaying = false);
    } else {
      // Resume from the current scrub spot (or restart if at the end).
      final from = (_pos >= _maxPos) ? 0.0 : _pos / _maxPos;
      _playCtrl.forward(from: from);
      setState(() => _isPlaying = true);
    }
  }

  static double _num(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _fmt(double value, {int digits = 1}) => value.toStringAsFixed(digits);

  Widget _compareStat(String label, String value, {String? gps}) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: Esk8Theme.number(18, color: Colors.white)),
            if (gps != null) ...[
              const SizedBox(width: 4),
              const Text(
                '|',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(width: 4),
              Text(gps, style: Esk8Theme.number(18, color: Esk8Theme.accent)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _playCtrl.dispose();
    super.dispose();
  }

  /// Per-metric charts across the whole trip, with a marker at the scrubber.
  Widget _buildGraphs() {
    final isMph = widget.isMph;
    final spdUnit = isMph ? 'mph' : 'km/h';
    final climbUnit = isMph ? 'ft' : 'm';
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 190), // room for scrubber
      children: [
        _metricChart(
          'Speed',
          spdUnit,
          Esk8Theme.accent,
          (r) => (r['boardSpeed'] as num).toDouble(),
          compareValueOf: _gpsCompare
              ? (r) {
                  final gps = (r['gpsSpeed'] as num).toDouble();
                  return isMph ? gps / 1.60934 : gps;
                }
              : null,
        ),
        _metricChart(
          'Elevation',
          climbUnit,
          const Color(0xFF4FC3F7),
          (r) =>
              ((r['altitude'] as num?)?.toDouble() ?? 0) *
              (isMph ? 3.28084 : 1),
        ),
        _metricChart(
          'Power',
          'W',
          const Color(0xFF66BB6A),
          (r) => (r['watts'] as num).toDouble(),
        ),
        _metricChart(
          'Voltage',
          'V',
          Esk8Theme.yellow,
          (r) => (r['voltage'] as num).toDouble(),
        ),
        _metricChart(
          'Battery',
          '%',
          const Color(0xFFEF5350),
          (r) => (r['battery'] as num).toDouble(),
        ),
      ],
    );
  }

  Widget _metricChart(
    String label,
    String unit,
    Color color,
    double Function(Map<String, dynamic>) valueOf, {
    double Function(Map<String, dynamic>)? compareValueOf,
  }) {
    final vals = [for (final r in _telemetry) valueOf(r)];
    final compareVals = compareValueOf == null
        ? null
        : [for (final r in _telemetry) compareValueOf(r)];
    final spots = [
      for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i]),
    ];
    final compareSpots = compareVals == null
        ? null
        : [
            for (var i = 0; i < compareVals.length; i++)
              FlSpot(i.toDouble(), compareVals[i]),
          ];
    final allVals = compareVals == null ? vals : [...vals, ...compareVals];
    double minY = allVals.reduce(min), maxY = allVals.reduce(max);
    if (maxY - minY < 1) maxY = minY + 1;
    final pad = (maxY - minY) * 0.1;
    final cur = vals[_idx.clamp(0, vals.length - 1)];
    final compareCur = compareVals == null
        ? null
        : compareVals[_idx.clamp(0, compareVals.length - 1)];
    return Container(
      height: 170,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: Esk8Theme.panelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label.toUpperCase(), style: Esk8Theme.labelStyle),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      cur.toStringAsFixed(1),
                      style: Esk8Theme.number(20, color: color),
                    ),
                    if (compareCur != null) ...[
                      const SizedBox(width: 5),
                      Text('|', style: TextStyle(color: Esk8Theme.dim)),
                      const SizedBox(width: 5),
                      Text(
                        compareCur.toStringAsFixed(1),
                        style: Esk8Theme.number(20, color: Esk8Theme.accent),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Text(unit, style: TextStyle(color: Esk8Theme.dim)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (vals.length - 1).toDouble().clamp(1, double.infinity),
                minY: minY - pad,
                maxY: maxY + pad,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.15),
                    ),
                  ),
                  if (compareSpots != null)
                    LineChartBarData(
                      spots: compareSpots,
                      isCurved: false,
                      color: Esk8Theme.accent,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: _idx.toDouble(),
                      color: Colors.white54,
                      strokeWidth: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The base tile layer — matches the live map's light/dark preference. Dark
  /// tiles get the same brightness bump used on the trip view.
  Widget _tileLayer() {
    if (_mapLight) {
      return TileLayer(
        urlTemplate:
            'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
        subdomains: const ['a', 'b', 'c', 'd'],
      );
    }
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        1.5, 0, 0, 0, 15, //
        0, 1.5, 0, 0, 15, //
        0, 0, 1.5, 0, 15, //
        0, 0, 0, 1, 0, //
      ]),
      child: TileLayer(
        urlTemplate:
            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
        subdomains: const ['a', 'b', 'c', 'd'],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Esk8Theme.scaffold,
        body: Column(
          children: [
            const SubPageHeader(title: 'Trip Playback'),
            Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Esk8Theme.accent),
              ),
            ),
          ],
        ),
      );
    }

    if (_telemetry.isEmpty) {
      return Scaffold(
        backgroundColor: Esk8Theme.scaffold,
        body: Column(
          children: [
            const SubPageHeader(title: 'Trip Playback'),
            Expanded(
              child: Center(
                child: Text(
                  'No telemetry data for this trip.',
                  style: TextStyle(color: Esk8Theme.dim),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final speedUnitStr = widget.isMph ? 'mph' : 'km/h';
    final distUnitStr = widget.isMph ? 'mi' : 'km';
    final startMs = widget.tripData['startTime'] as int?;
    final endMs = widget.tripData['endTime'] as int?;
    final elapsed = startMs != null && endMs != null
        ? Duration(milliseconds: endMs - startMs)
        : Duration.zero;
    final elapsedHours = elapsed.inMilliseconds / 3600000.0;
    final gpsDistance =
        _num(widget.tripData['distance']) / (widget.isMph ? 1609.34 : 1000.0);
    final boardDistance =
        _num(widget.tripData['boardDistanceMi']) *
        (widget.isMph ? 1.0 : 1.60934);
    final gpsMax =
        _num(widget.tripData['maxSpeed']) / (widget.isMph ? 1.60934 : 1.0);
    final boardMax = _num(widget.tripData['boardMaxSpeed']);
    final gpsAvg = elapsedHours > 0 ? gpsDistance / elapsedHours : 0.0;
    final boardAvg = elapsedHours > 0 ? boardDistance / elapsedHours : 0.0;
    final accent = Esk8Theme.accent;
    return Scaffold(
      backgroundColor: Esk8Theme.scaffold,
      body: Column(
        children: [
          SubPageHeader(
            title: 'Trip Playback',
            actions: [
              IconButton(
                icon: Icon(Icons.compare_arrows, color: accent),
                tooltip: _gpsCompare ? 'Hide GPS compare' : 'GPS compare',
                onPressed: () => setState(() => _gpsCompare = !_gpsCompare),
              ),
              if (!_showGraphs) ...[
                IconButton(
                  icon: Icon(
                    _mapLight ? Icons.light_mode : Icons.dark_mode,
                    color: accent,
                  ),
                  tooltip: _mapLight ? 'Light map' : 'Dark map',
                  onPressed: () => setState(() {
                    _mapLight = !_mapLight;
                    AppPrefs.mapLight = _mapLight; // share with the live map
                  }),
                ),
                IconButton(
                  icon: Icon(
                    _follow ? Icons.my_location : Icons.location_searching,
                    color: accent,
                  ),
                  tooltip: _follow ? 'Following marker' : 'Free look',
                  onPressed: () => setState(() {
                    _follow = !_follow;
                    if (_follow) _recenterIfFollow();
                  }),
                ),
              ],
              IconButton(
                icon: Icon(
                  _showGraphs ? Icons.map : Icons.show_chart,
                  color: accent,
                ),
                tooltip: _showGraphs ? 'Map' : 'Graphs',
                onPressed: () => setState(() => _showGraphs = !_showGraphs),
              ),
              IconButton(
                icon: Icon(Icons.ios_share, color: accent),
                tooltip: 'Share trip card',
                onPressed: () => TripShare.shareSummary(
                  context,
                  widget.tripData,
                  widget.isMph,
                ),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                if (_showGraphs)
                  _buildGraphs()
                else
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _route.isNotEmpty
                          ? _route.first
                          : const LatLng(0, 0),
                      initialZoom: 16,
                      onMapReady: () => _mapReady = true,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture && _follow) {
                          setState(
                            () => _follow = false,
                          ); // a manual pan drops follow
                        }
                      },
                    ),
                    children: [
                      _tileLayer(),
                      ?_routeLayer, // cached static full route (skipped while still loading)
                      // The trail + marker animate on the controller WITHOUT rebuilding the
                      // map (tiles/route stay put), so the marker glides at vsync. No page
                      // setState happens during playback.
                      AnimatedBuilder(
                        animation: _playCtrl,
                        builder: (_, _) => _buildTrailLayer(),
                      ),
                      AnimatedBuilder(
                        animation: _playCtrl,
                        builder: (_, _) => MarkerLayer(
                          markers: [
                            Marker(
                              point: _markerPos(),
                              width: 20,
                              height: 20,
                              child: _markerDot,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                // Playback controls (Bottom)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    decoration: const BoxDecoration(
                      color: Color(0xDD1E1E1E),
                      border: Border(top: BorderSide(color: Color(0xFF333333))),
                    ),
                    // Stats + slider update on the controller (no page rebuild), so they
                    // track playback in sync with the gliding marker.
                    child: AnimatedBuilder(
                      animation: _playCtrl,
                      builder: (context, _) {
                        final data = _telemetry[_idx];
                        final ts = DateTime.fromMillisecondsSinceEpoch(
                          data['timestamp'] as int,
                        );
                        final gps = widget.isMph
                            ? (data['gpsSpeed'] as double) / 1.60934
                            : data['gpsSpeed'] as double;
                        final board = data['boardSpeed'] as double;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _compareStat(
                                  'Speed $speedUnitStr',
                                  _fmt(board),
                                  gps: _gpsCompare ? _fmt(gps) : null,
                                ),
                                _compareStat(
                                  'Trip $distUnitStr',
                                  _fmt(boardDistance, digits: 2),
                                  gps: _gpsCompare
                                      ? _fmt(gpsDistance, digits: 2)
                                      : null,
                                ),
                                _compareStat(
                                  'Max $speedUnitStr',
                                  _fmt(boardMax),
                                  gps: _gpsCompare ? _fmt(gpsMax) : null,
                                ),
                                _compareStat(
                                  'Avg $speedUnitStr',
                                  _fmt(boardAvg),
                                  gps: _gpsCompare ? _fmt(gpsAvg) : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _compareStat(
                                  'Time',
                                  DateFormat('h:mm:ss a').format(ts),
                                ),
                                _compareStat('Battery', '${data['battery']}%'),
                                _compareStat(
                                  'Duration',
                                  _formatDuration(elapsed),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: accent,
                                    size: 32,
                                  ),
                                  onPressed: _togglePlayback,
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      activeTrackColor: accent,
                                      inactiveTrackColor: const Color(
                                        0xFF333333,
                                      ),
                                      thumbColor: Colors.white,
                                      overlayColor: accent.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    child: Slider(
                                      value: _pos.clamp(
                                        0,
                                        (_telemetry.length - 1).toDouble(),
                                      ),
                                      min: 0,
                                      max: (_telemetry.length - 1).toDouble(),
                                      onChanged: (val) {
                                        _playCtrl.stop();
                                        _playCtrl.value = (val / _maxPos).clamp(
                                          0.0,
                                          1.0,
                                        );
                                        if (_isPlaying) {
                                          setState(() => _isPlaying = false);
                                        }
                                        _recenterIfFollow();
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
