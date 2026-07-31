import 'dart:convert';
import 'dart:io';

import 'package:esk8os_mobile/database/trip_database.dart';
import 'package:esk8os_mobile/models/trail.dart';
import 'package:esk8os_mobile/services/trip_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late Database db;
  late TripDatabase repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('evee_trail_test_');
    final path = '${tempDir.path}${Platform.pathSeparator}trips.db';
    await _createLegacyV5(path);
    db = await TripDatabase.openForTesting(databaseFactoryFfi, path);
    repository = TripDatabase.forTesting(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('v5 migration preserves rides and adds trail/waypoint schema', () async {
    expect(await db.getVersion(), TripDatabase.schemaVersion);
    final rides = await repository.getAllTrips();
    expect(rides, hasLength(1));
    expect(rides.single['source'], 'board-assisted');

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(names, containsAll(['trails', 'trail_points', 'waypoints']));
  });

  test('new rides persist an explicit recording source', () async {
    final id = await repository.createTrip(30000, source: 'phone-gps');
    final rides = await repository.getAllTrips();
    final phoneRide = rides.singleWhere((ride) => ride['id'] == id);

    expect(phoneRide['source'], 'phone-gps');
    await expectLater(
      repository.createTrip(40000, source: 'mystery-source'),
      throwsArgumentError,
    );
  });

  test('derived trail copies points and preserves GPS gap segments', () async {
    final trail = await repository.createTrailFromTrip(
      tripId: 1,
      name: '  Creek   Loop  ',
    );
    final points = await repository.getTrailPoints(trail.id!);

    expect(trail.name, 'Creek Loop');
    expect(trail.sourceTripId, 1);
    expect(trail.pointCount, 4);
    expect(trail.segmentCount, 2);
    expect(trail.distanceM, closeTo(22.2, 2));
    expect(points.map((point) => point.segment), [0, 0, 1, 1]);
  });

  test('orphan recovery does not bridge a long GPS gap', () async {
    await db.update(
      'trips',
      {'endTime': null, 'distance': 0.0},
      where: 'id = ?',
      whereArgs: [1],
    );

    await repository.recoverOrphans();

    final recovered = (await repository.getAllTrips()).single;
    expect(recovered['endTime'], 22000);
    expect((recovered['distance'] as num).toDouble(), closeTo(22.2, 2));
  });

  test('deleting a source ride keeps the independent trail copy', () async {
    final trail = await repository.createTrailFromTrip(
      tripId: 1,
      name: 'Independent Trail',
    );

    await repository.deleteTrip(1);

    final retained = await repository.getTrail(trail.id!);
    expect(retained, isNotNull);
    expect(retained!.sourceTripId, isNull);
    expect(await repository.getTrailPoints(trail.id!), hasLength(4));
    expect(await repository.getTripTelemetry(1), isEmpty);
  });

  test(
    'waypoints validate names and survive trail deletion unlinked',
    () async {
      final trail = await repository.createTrailFromTrip(
        tripId: 1,
        name: 'Waypoint Trail',
      );
      final now = DateTime.utc(2026, 7, 29).millisecondsSinceEpoch;
      final waypointId = await repository.createWaypoint(
        Waypoint(
          trailId: trail.id,
          sourceTripId: 1,
          name: ' Trailhead ',
          type: 'trailhead',
          latitude: 40,
          longitude: -75,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await repository.deleteTrail(trail.id!);

      final waypoint = (await repository.getAllWaypoints()).single;
      expect(waypoint.id, waypointId);
      expect(waypoint.name, 'Trailhead');
      expect(waypoint.trailId, isNull);
    },
  );

  test('library backup round-trips trails and remaps provenance IDs', () async {
    final trail = await repository.createTrailFromTrip(
      tripId: 1,
      name: 'Backup Trail',
    );
    final now = DateTime.utc(2026, 7, 29).millisecondsSinceEpoch;
    await repository.createWaypoint(
      Waypoint(
        trailId: trail.id,
        sourceTripId: 1,
        name: 'Water',
        type: 'water',
        latitude: 40.0001,
        longitude: -75,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final encoded = jsonEncode(await TripBackup.buildPayload(repository));

    final restorePath = '${tempDir.path}${Platform.pathSeparator}restored.db';
    final restoreDb = await TripDatabase.openForTesting(
      databaseFactoryFfi,
      restorePath,
    );
    final restored = TripDatabase.forTesting(restoreDb);
    await restored.createTrip(999); // force restored ride IDs to be remapped

    final result = await TripBackup.restorePayload(
      jsonDecode(encoded),
      restored,
    );
    final restoredTrail = (await restored.getAllTrails()).single;
    final restoredWaypoint = (await restored.getAllWaypoints()).single;

    expect(result.label, '1 ride, 1 trail, 1 waypoint');
    expect(restoredTrail.sourceTripId, 2);
    expect(restoredWaypoint.sourceTripId, 2);
    expect(restoredWaypoint.trailId, restoredTrail.id);
    expect(await restored.getTrailPoints(restoredTrail.id!), hasLength(4));
    await restoreDb.close();
  });

  test('format-1 ride-only backups remain importable', () async {
    final payload = await TripBackup.buildPayload(repository);
    payload['format'] = 1;
    payload.remove('trails');
    payload.remove('waypoints');

    final restorePath =
        '${tempDir.path}${Platform.pathSeparator}legacy_restore.db';
    final restoreDb = await TripDatabase.openForTesting(
      databaseFactoryFfi,
      restorePath,
    );
    final restored = TripDatabase.forTesting(restoreDb);

    final result = await TripBackup.restorePayload(
      jsonDecode(jsonEncode(payload)),
      restored,
    );

    expect(result.rides, 1);
    expect(result.trails, 0);
    expect(result.waypoints, 0);
    expect(await restored.getAllTrips(), hasLength(1));
    await restoreDb.close();
  });
}

Future<void> _createLegacyV5(String path) async {
  final legacy = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 5,
      singleInstance: false,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE trips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startTime INTEGER NOT NULL,
            endTime INTEGER,
            distance REAL NOT NULL,
            maxSpeed REAL NOT NULL,
            boardMaxSpeed REAL NOT NULL,
            elevGainM REAL DEFAULT 0,
            boardDistanceMi REAL DEFAULT 0,
            wattHours REAL DEFAULT 0,
            regenWh REAL DEFAULT 0,
            effWhMi REAL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE telemetry (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tripId INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            gpsSpeed REAL NOT NULL,
            boardSpeed REAL NOT NULL,
            battery INTEGER NOT NULL,
            voltage REAL NOT NULL,
            watts INTEGER NOT NULL,
            altitude REAL DEFAULT 0,
            bmsJson TEXT,
            FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
          )
        ''');
        await db.insert('trips', {
          'id': 1,
          'startTime': 1000,
          'endTime': 22000,
          'distance': 22.2,
          'maxSpeed': 10.0,
          'boardMaxSpeed': 10.0,
        });
        final samples = [
          (timestamp: 1000, lat: 40.0000),
          (timestamp: 2000, lat: 40.0001),
          (timestamp: 21000, lat: 40.0100),
          (timestamp: 22000, lat: 40.0101),
        ];
        for (final sample in samples) {
          await db.insert('telemetry', {
            'tripId': 1,
            'timestamp': sample.timestamp,
            'lat': sample.lat,
            'lng': -75.0,
            'gpsSpeed': 5.0,
            'boardSpeed': 5.0,
            'battery': 90,
            'voltage': 40.0,
            'watts': 500,
            'altitude': 100.0,
          });
        }
      },
    ),
  );
  await legacy.close();
}
