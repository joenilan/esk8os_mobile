import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:latlong2/latlong.dart';

/// The floating bubble shown over other apps while a trip records in the
/// background. Runs in its own engine (the [overlayMain] entry point), and gets
/// live stats pushed from the app via FlutterOverlayWindow.shareData.
///
/// Google-nav style: a live mini-map fills the bubble, centered on the rider
/// with a heading arrow, and a translucent speed/trip strip is pinned at the
/// bottom. The map is pure-Dart flutter_map + HTTP CartoDB tiles, so it renders
/// in this isolate without plugin registration.
class TripOverlay extends StatefulWidget {
  const TripOverlay({super.key});

  @override
  State<TripOverlay> createState() => _TripOverlayState();
}

class _TripOverlayState extends State<TripOverlay> {
  static const _accent = Color(0xFFB950D7);
  static const _zoom = 16.0;
  // Fallback center until the first GPS fix arrives (San Francisco).
  static const _fallback = LatLng(37.7749, -122.4194);

  final MapController _mapController = MapController();
  bool _mapReady = false;

  String _spd = '0';
  String _unit = 'MPH';
  String _trip = '0.00';
  String _tripUnit = 'mi';
  String _time = '0s';
  bool _paused = false;

  LatLng? _pos; // null until the first fix
  double _hdg = 0; // GPS course, degrees (0 = north, clockwise)

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == null) return;
      try {
        final m = event is String ? jsonDecode(event) : event;
        if (m is! Map) return;
        setState(() {
          _spd = (m['spd'] ?? _spd).toString();
          _unit = (m['unit'] ?? _unit).toString();
          _trip = (m['trip'] ?? _trip).toString();
          _tripUnit = (m['tu'] ?? _tripUnit).toString();
          _time = (m['time'] ?? _time).toString();
          _paused = m['paused'] == true;
          final lat = _toDouble(m['lat']);
          final lng = _toDouble(m['lng']);
          if (lat != null && lng != null) _pos = LatLng(lat, lng);
          final hdg = _toDouble(m['hdg']);
          if (hdg != null) _hdg = hdg;
        });
        _recenter();
      } catch (_) {}
    });
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  void _recenter() {
    final p = _pos;
    if (!_mapReady || p == null) return;
    try {
      _mapController.move(p, _zoom);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _paused ? const Color(0xFFFFCD00) : _accent;
    return Material(
      color: Colors.transparent,
      child: Container(
        // Square corners to match the square overlay window — a rounded border
        // here doesn't line up with the window's right-angle corners.
        decoration: BoxDecoration(
          color: const Color(0xF21A1A1A),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMap(),
            // No-fix hint while we wait for GPS.
            if (_pos == null)
              const Center(
                child: Text('Waiting for GPS…',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            Positioned(left: 0, right: 0, bottom: 0, child: _buildStatsStrip()),
            // Transparent tap-catcher on top: FlutterMap absorbs pointer events,
            // so this restores tap-to-return-to-app over the whole bubble.
            // onTap-only doesn't claim the pointer, so native drag still works.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FlutterOverlayWindow.shareData('open_app'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _pos ?? _fallback,
        initialZoom: _zoom,
        // Gestures off so dragging the bubble moves the window, not the map.
        interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.none),
        onMapReady: () {
          _mapReady = true;
          _recenter();
        },
      ),
      children: [
        // CartoDB dark, brightness-bumped to match the in-app trip map.
        ColorFiltered(
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
            retinaMode: RetinaMode.isHighDensity(context),
          ),
        ),
        if (_pos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _pos!,
                width: 28,
                height: 28,
                child: Transform.rotate(
                  angle: _hdg * math.pi / 180.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.navigation,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatsStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xE6000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          Text(_spd,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1)),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(_paused ? 'PAUSED' : _unit,
                style: TextStyle(
                    color: _paused ? const Color(0xFFFFCD00) : Colors.grey,
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_trip $_tripUnit',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.1)),
              Text(_time,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
