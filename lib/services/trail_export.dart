import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trail.dart';

class TrailExport {
  static String buildGpx(
    Trail trail,
    List<TrailPoint> points,
    List<Waypoint> waypoints,
  ) {
    final segments = _segments(points);
    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="EVEE" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('<metadata><name>${_xml(trail.name)}</name></metadata>');
    for (final waypoint in waypoints) {
      out
        ..writeln(
          '<wpt lat="${waypoint.latitude}" lon="${waypoint.longitude}">',
        )
        ..writeln('<name>${_xml(waypoint.name)}</name>')
        ..writeln('<type>${_xml(waypoint.type)}</type>');
      if (waypoint.notes.isNotEmpty) {
        out.writeln('<desc>${_xml(waypoint.notes)}</desc>');
      }
      out.writeln('</wpt>');
    }
    out
      ..writeln('<trk>')
      ..writeln('<name>${_xml(trail.name)}</name>');
    if (trail.description.isNotEmpty) {
      out.writeln('<desc>${_xml(trail.description)}</desc>');
    }
    for (final segment in segments) {
      out.writeln('<trkseg>');
      for (final point in segment) {
        out
          ..writeln('<trkpt lat="${point.latitude}" lon="${point.longitude}">')
          ..writeln('<ele>${point.altitudeM.toStringAsFixed(1)}</ele>')
          ..writeln('</trkpt>');
      }
      out.writeln('</trkseg>');
    }
    out.writeln('</trk></gpx>');
    return out.toString();
  }

  static String buildGeoJson(
    Trail trail,
    List<TrailPoint> points,
    List<Waypoint> waypoints,
  ) {
    final coordinates = [
      for (final segment in _segments(points))
        [
          for (final point in segment)
            [point.longitude, point.latitude, point.altitudeM],
        ],
    ];
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {'type': 'MultiLineString', 'coordinates': coordinates},
          'properties': {
            'name': trail.name,
            'description': trail.description,
            'surface': trail.surface,
            'difficulty': trail.difficulty,
            'direction': trail.direction,
            'visibility': trail.visibility,
            'distanceM': trail.distanceM,
            'sourceTripId': trail.sourceTripId,
            'producer': 'EVEE',
          },
        },
        for (final waypoint in waypoints)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [waypoint.longitude, waypoint.latitude],
            },
            'properties': {
              'name': waypoint.name,
              'type': waypoint.type,
              'notes': waypoint.notes,
            },
          },
      ],
    });
  }

  static Future<void> shareGpx(
    Trail trail,
    List<TrailPoint> points,
    List<Waypoint> waypoints,
  ) async {
    final file = await _writeTemporary(
      trail,
      'gpx',
      buildGpx(trail, points, waypoints),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/gpx+xml')],
        subject: '${trail.name} · EVEE Trail',
      ),
    );
  }

  static Future<void> shareGeoJson(
    Trail trail,
    List<TrailPoint> points,
    List<Waypoint> waypoints,
  ) async {
    final file = await _writeTemporary(
      trail,
      'geojson',
      buildGeoJson(trail, points, waypoints),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/geo+json')],
        subject: '${trail.name} · EVEE Trail',
      ),
    );
  }

  static Future<File> _writeTemporary(
    Trail trail,
    String extension,
    String contents,
  ) async {
    final directory = await getTemporaryDirectory();
    final stableId = trail.id?.toString() ?? 'draft';
    final file = File('${directory.path}/evee_trail_$stableId.$extension');
    await file.writeAsString(contents, flush: true);
    return file;
  }

  static List<List<TrailPoint>> _segments(List<TrailPoint> points) {
    final grouped = <int, List<TrailPoint>>{};
    final ordered = [...points]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final point in ordered) {
      grouped.putIfAbsent(point.segment, () => []).add(point);
    }
    return grouped.values.where((segment) => segment.isNotEmpty).toList();
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
