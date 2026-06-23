import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// The floating bubble shown over other apps while a trip records in the
/// background. Runs in its own engine (the [overlayMain] entry point), and gets
/// live stats pushed from the app via FlutterOverlayWindow.shareData.
class TripOverlay extends StatefulWidget {
  const TripOverlay({super.key});

  @override
  State<TripOverlay> createState() => _TripOverlayState();
}

class _TripOverlayState extends State<TripOverlay> {
  String _spd = '0';
  String _unit = 'MPH';
  String _trip = '0.00';
  String _tripUnit = 'mi';
  String _time = '0s';
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == null) return;
      try {
        final m = event is String ? jsonDecode(event) : event;
        if (m is Map) {
          setState(() {
            _spd = (m['spd'] ?? _spd).toString();
            _unit = (m['unit'] ?? _unit).toString();
            _trip = (m['trip'] ?? _trip).toString();
            _tripUnit = (m['tu'] ?? _tripUnit).toString();
            _time = (m['time'] ?? _time).toString();
            _paused = m['paused'] == true;
          });
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFB950D7);
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF21A1A1A),
          border: Border.all(color: _paused ? const Color(0xFFFFCD00) : accent, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(_spd,
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, height: 1)),
                Text(_paused ? 'PAUSED' : _unit,
                    style: TextStyle(color: _paused ? const Color(0xFFFFCD00) : Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 34, color: const Color(0xFF333333)),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_trip $_tripUnit', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                Text(_time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
