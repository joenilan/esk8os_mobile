import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/trip_database.dart';
import '../models/trail.dart';

class LibraryBackupResult {
  final int rides;
  final int trails;
  final int waypoints;

  const LibraryBackupResult({
    required this.rides,
    required this.trails,
    required this.waypoints,
  });

  bool get isEmpty => rides == 0 && trails == 0 && waypoints == 0;

  String get label =>
      '$rides ride${rides == 1 ? '' : 's'}, '
      '$trails trail${trails == 1 ? '' : 's'}, '
      '$waypoints waypoint${waypoints == 1 ? '' : 's'}';
}

/// Trip backup / restore. Lets you pull all recorded rides out to a JSON file
/// (shared off the phone, so it survives an uninstall) and read them back in —
/// the safety net so an app update / re-signing can't lose your history.
class TripBackup {
  static const int _formatVersion = 2;

  /// Export the complete rider-owned library. Trails contain copied geometry;
  /// source ride IDs remain optional provenance and are remapped on restore.
  static Future<LibraryBackupResult> export() async {
    final db = TripDatabase.instance;
    final out = await buildPayload(db);
    final trips = out['trips'] as List;
    final trails = out['trails'] as List;
    final waypoints = out['waypoints'] as List;

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File('${dir.path}/evee_library_$stamp.json');
    await file.writeAsString(jsonEncode(out));

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'EVEE library backup'),
    );
    return LibraryBackupResult(
      rides: trips.length,
      trails: trails.length,
      waypoints: waypoints.length,
    );
  }

  /// Builds a serializable backup without invoking a file picker or share
  /// sheet. Kept public so the format can be round-trip tested with an isolated
  /// database.
  static Future<Map<String, dynamic>> buildPayload(TripDatabase db) async {
    final trips = await db.getAllTrips();
    final trails = await db.getAllTrails();
    final waypoints = await db.getAllWaypoints();
    return <String, dynamic>{
      'format': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'trips': [
        for (final t in trips)
          {'trip': t, 'telemetry': await db.getTripTelemetry(t['id'] as int)},
      ],
      'trails': [
        for (final trail in trails)
          {
            'trail': trail.toMap(),
            'points': [
              for (final point in await db.getTrailPoints(trail.id!))
                point.toMap(),
            ],
          },
      ],
      'waypoints': [for (final waypoint in waypoints) waypoint.toMap()],
    };
  }

  /// Export one trip as a GPX track (lat/lon/ele/time) and share it — drops
  /// straight into Strava, Google Earth, etc.
  static Future<void> exportGpx(int tripId, DateTime start) async {
    final pts = await TripDatabase.instance.getTripTelemetry(tripId);
    final sb = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="EVEE" xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln(
        '<trk><name>EVEE ride ${start.toIso8601String()}</name><trkseg>',
      );
    for (final p in pts) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        p['timestamp'] as int,
      ).toUtc().toIso8601String();
      sb
        ..writeln('<trkpt lat="${p['lat']}" lon="${p['lng']}">')
        ..writeln(
          '<ele>${(p['altitude'] as num?)?.toStringAsFixed(1) ?? '0'}</ele>',
        )
        ..writeln('<time>$t</time></trkpt>');
    }
    sb.writeln('</trkseg></trk></gpx>');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/esk8_ride_$tripId.gpx');
    await file.writeAsString(sb.toString());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'EVEE ride (GPX)'),
    );
  }

  /// Restore format-1 ride-only backups or the complete format-2 library.
  static Future<LibraryBackupResult> import() async {
    const typeGroup = XTypeGroup(label: 'backup', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) {
      return const LibraryBackupResult(rides: 0, trails: 0, waypoints: 0);
    }

    final data = jsonDecode(await picked.readAsString());
    return restorePayload(data, TripDatabase.instance);
  }

  /// Restores decoded backup data into [db], remapping every ride/trail
  /// relationship to the new local IDs.
  static Future<LibraryBackupResult> restorePayload(
    Object? data,
    TripDatabase db,
  ) async {
    if (data is! Map || data['trips'] is! List) {
      throw const FormatException('Not a valid EVEE trip backup');
    }
    final format = data['format'];
    if (format is! int || format < 1 || format > _formatVersion) {
      throw const FormatException('Unsupported EVEE backup version');
    }
    final tripIdMap = <int, int>{};
    var rideCount = 0;
    for (final entry in (data['trips'] as List)) {
      if (entry is Map && entry['trip'] is Map && entry['telemetry'] is List) {
        final trip = Map<String, dynamic>.from(entry['trip'] as Map);
        final oldId = trip['id'];
        final newId = await db.importTrip(trip, [
          for (final s in (entry['telemetry'] as List))
            Map<String, dynamic>.from(s as Map),
        ]);
        if (oldId is int) tripIdMap[oldId] = newId;
        rideCount++;
      }
    }

    final trailIdMap = <int, int>{};
    var trailCount = 0;
    final trailEntries = data['trails'];
    if (trailEntries is List) {
      for (final entry in trailEntries) {
        if (entry is! Map ||
            entry['trail'] is! Map ||
            entry['points'] is! List) {
          continue;
        }
        final trailMap = Map<String, Object?>.from(entry['trail'] as Map);
        final oldTrailId = trailMap['id'];
        final oldSourceTripId = trailMap['sourceTripId'];
        final trail = Trail.fromMap(trailMap);
        final points = [
          for (final point in entry['points'] as List)
            if (point is Map)
              TrailPoint.fromMap(Map<String, Object?>.from(point)),
        ];
        if (points.length < 2) continue;
        final newTrailId = await db.importTrail(
          trail,
          points,
          sourceTripId: oldSourceTripId is int
              ? tripIdMap[oldSourceTripId]
              : null,
        );
        if (oldTrailId is int) trailIdMap[oldTrailId] = newTrailId;
        trailCount++;
      }
    }

    var waypointCount = 0;
    final waypointEntries = data['waypoints'];
    if (waypointEntries is List) {
      for (final entry in waypointEntries) {
        if (entry is! Map) continue;
        final old = Waypoint.fromMap(Map<String, Object?>.from(entry));
        await db.createWaypoint(
          Waypoint(
            trailId: old.trailId == null ? null : trailIdMap[old.trailId],
            sourceTripId: old.sourceTripId == null
                ? null
                : tripIdMap[old.sourceTripId],
            name: old.name,
            type: old.type,
            notes: old.notes,
            latitude: old.latitude,
            longitude: old.longitude,
            createdAt: old.createdAt,
            updatedAt: old.updatedAt,
          ),
        );
        waypointCount++;
      }
    }

    return LibraryBackupResult(
      rides: rideCount,
      trails: trailCount,
      waypoints: waypointCount,
    );
  }
}
