import 'dart:io';

import 'package:esk8os_mobile/database/trip_database.dart';
import 'package:esk8os_mobile/services/trip_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late Database db;
  late TripDatabase repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('evee_fusion_test_');
    final path = '${tempDir.path}${Platform.pathSeparator}trips.db';
    await _createLegacyV7(path);
    db = await TripDatabase.openForTesting(databaseFactoryFfi, path);
    repository = TripDatabase.forTesting(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'v8 migration preserves rides and adds nullable fusion evidence',
    () async {
      expect(await db.getVersion(), TripDatabase.schemaVersion);
      final rides = await repository.getAllTrips();
      expect(rides, hasLength(1));
      // Pre-policy rides carry NULL fusion fields so the UI falls back to the
      // legacy raw-GPS distance instead of inventing a number.
      expect(rides.single['fusedDistanceM'], isNull);
      expect(rides.single['fusedSource'], isNull);
      expect(rides.single['fusionSwitches'], 0);
    },
  );

  test(
    'updateTrip persists fusion evidence without clobbering from legacy callers',
    () async {
      final id = await repository.createTrip(50000, source: 'board-assisted');
      await repository.updateTrip(
        id,
        320000,
        5200.0,
        12.0,
        11.0,
        fusedDistanceM: 5230.0,
        fusedSource: 'board',
        fusionSwitches: 2,
      );
      final ride = await repository.getAllTrips().then(
        (rows) => rows.singleWhere((r) => r['id'] == id),
      );
      expect(ride['fusedDistanceM'], 5230.0);
      expect(ride['fusedSource'], 'board');
      expect(ride['fusionSwitches'], 2);

      // A legacy-shaped update (no fusion args) must not null out evidence.
      await repository.updateTrip(id, 330000, 5200.0, 12.0, 11.0);
      final after = await repository.getAllTrips().then(
        (rows) => rows.singleWhere((r) => r['id'] == id),
      );
      expect(after['fusedDistanceM'], 5230.0);
      expect(after['fusionSwitches'], 2);
    },
  );

  test('backup round-trips the fusion evidence (format v3)', () async {
    final id = await repository.createTrip(50000, source: 'board-assisted');
    await repository.updateTrip(
      id,
      320000,
      5200.0,
      12.0,
      11.0,
      fusedDistanceM: 5230.0,
      fusedSource: 'gps',
      fusionSwitches: 4,
    );
    final payload = await TripBackup.buildPayload(repository);
    expect(payload['format'], TripBackup.formatVersion);

    final restorePath = '${tempDir.path}${Platform.pathSeparator}restored.db';
    final restoreDb = await TripDatabase.openForTesting(
      databaseFactoryFfi,
      restorePath,
    );
    final restored = TripDatabase.forTesting(restoreDb);
    addTearDown(restoreDb.close);
    await TripBackup.restorePayload(payload, restored);

    final rides = await restored.getAllTrips();
    final restoredRide = rides.singleWhere((r) => r['fusedSource'] == 'gps');
    expect(restoredRide['fusedDistanceM'], 5230.0);
    expect(restoredRide['fusionSwitches'], 4);
  });
}

Future<void> _createLegacyV7(String path) async {
  final legacy = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 7,
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
            effWhMi REAL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'board-assisted'
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
          'source': 'board-assisted',
        });
        // v6+ carries the trail/waypoint tables; a v7 database has them.
        await db.execute('''
          CREATE TABLE trails (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sourceTripId INTEGER,
            name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 80),
            description TEXT NOT NULL DEFAULT ''
              CHECK(length(description) <= 1000),
            surface TEXT NOT NULL DEFAULT 'unknown',
            difficulty TEXT NOT NULL DEFAULT 'unknown',
            direction TEXT NOT NULL DEFAULT 'both',
            visibility TEXT NOT NULL DEFAULT 'private',
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            distanceM REAL NOT NULL DEFAULT 0 CHECK(distanceM >= 0),
            pointCount INTEGER NOT NULL DEFAULT 0 CHECK(pointCount >= 0),
            segmentCount INTEGER NOT NULL DEFAULT 0 CHECK(segmentCount >= 0)
          )
        ''');
        await db.execute('''
          CREATE TABLE trail_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trailId INTEGER NOT NULL,
            sequence INTEGER NOT NULL CHECK(sequence >= 0),
            segment INTEGER NOT NULL DEFAULT 0 CHECK(segment >= 0),
            lat REAL NOT NULL CHECK(lat BETWEEN -90 AND 90),
            lng REAL NOT NULL CHECK(lng BETWEEN -180 AND 180),
            altitudeM REAL NOT NULL DEFAULT 0,
            FOREIGN KEY (trailId) REFERENCES trails (id) ON DELETE CASCADE,
            UNIQUE(trailId, sequence)
          )
        ''');
        await db.execute('''
          CREATE TABLE waypoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trailId INTEGER,
            sourceTripId INTEGER,
            name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 80),
            type TEXT NOT NULL DEFAULT 'note',
            notes TEXT NOT NULL DEFAULT '' CHECK(length(notes) <= 1000),
            lat REAL NOT NULL CHECK(lat BETWEEN -90 AND 90),
            lng REAL NOT NULL CHECK(lng BETWEEN -180 AND 180),
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            FOREIGN KEY (trailId) REFERENCES trails (id) ON DELETE SET NULL
          )
        ''');
      },
    ),
  );
  await legacy.close();
}
