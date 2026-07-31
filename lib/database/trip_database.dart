import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';

import '../models/trail.dart';

class TripDatabase {
  static final TripDatabase instance = TripDatabase._init();
  static Database? _database;
  static const int schemaVersion = 7;
  final Database? _databaseOverride;

  TripDatabase._init() : _databaseOverride = null;

  /// Test-only instance backed by an isolated SQLite database.
  TripDatabase.forTesting(Database database) : _databaseOverride = database;

  Future<Database> get database async {
    if (_databaseOverride != null) return _databaseOverride;
    if (_database != null) return _database!;
    _database = await _initDB('trips.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _configureDB,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  /// Opens the production schema through an injected factory. This keeps real
  /// migration tests off the phone and out of the app documents directory.
  static Future<Database> openForTesting(
    DatabaseFactory factory,
    String path,
  ) => factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: _configureDB,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      singleInstance: false,
    ),
  );

  static Future<void> _configureDB(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Schema migrations — additive ALTERs so existing trips are preserved.
  static Future<void> _upgradeDB(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      // v2: elevation. Climb on the trip, per-point altitude for GPX export.
      await db.execute('ALTER TABLE trips ADD COLUMN elevGainM REAL DEFAULT 0');
      await db.execute(
        'ALTER TABLE telemetry ADD COLUMN altitude REAL DEFAULT 0',
      );
    }
    if (oldV < 3) {
      // v3: board energy/range calibration summary. Existing trips keep zeros.
      await db.execute(
        'ALTER TABLE trips ADD COLUMN boardDistanceMi REAL DEFAULT 0',
      );
      await db.execute('ALTER TABLE trips ADD COLUMN wattHours REAL DEFAULT 0');
      await db.execute('ALTER TABLE trips ADD COLUMN regenWh REAL DEFAULT 0');
      await db.execute('ALTER TABLE trips ADD COLUMN effWhMi REAL DEFAULT 0');
    }
    if (oldV < 4) {
      // v4: telemetry rows are looked up by trip on every playback/delete —
      // without this index that's a full scan of a table that grows 1 row/s.
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_telemetry_trip ON telemetry(tripId)',
      );
    }
    if (oldV < 5) {
      // v5: optional raw Daly snapshot aligned with each 1 Hz trip point.
      // NULL means no fresh 0006 notification was available for that point.
      await db.execute('ALTER TABLE telemetry ADD COLUMN bmsJson TEXT');
    }
    if (oldV < 6) {
      await _createTrailTables(db);
    }
    if (oldV < 7) {
      await db.execute(
        "ALTER TABLE trips ADD COLUMN source TEXT NOT NULL "
        "DEFAULT 'board-assisted'",
      );
    }
  }

  static Future<void> _createDB(Database db, int version) async {
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

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_telemetry_trip ON telemetry(tripId)',
    );
    await _createTrailTables(db);
  }

  static Future<void> _createTrailTables(Database db) async {
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
    await db.execute(
      'CREATE INDEX idx_trail_points_trail '
      'ON trail_points(trailId, segment, sequence)',
    );
    await db.execute(
      'CREATE INDEX idx_trails_updated ON trails(updatedAt DESC)',
    );
    await db.execute('CREATE INDEX idx_waypoints_trail ON waypoints(trailId)');
  }

  // --- Trips ---

  Future<int> createTrip(
    int startTime, {
    String source = 'board-assisted',
  }) async {
    if (source != 'board-assisted' && source != 'phone-gps') {
      throw ArgumentError.value(source, 'source', 'Unsupported ride source');
    }
    final db = await database;
    return await db.insert('trips', {
      'startTime': startTime,
      'distance': 0.0,
      'maxSpeed': 0.0,
      'boardMaxSpeed': 0.0,
      'source': source,
    });
  }

  Future<void> updateTrip(
    int id,
    int endTime,
    double distance,
    double maxSpeed,
    double boardMaxSpeed, {
    double elevGainM = 0,
    double boardDistanceMi = 0,
    double wattHours = 0,
    double regenWh = 0,
    double effWhMi = 0,
  }) async {
    final db = await database;
    await db.update(
      'trips',
      {
        'endTime': endTime,
        'distance': distance,
        'maxSpeed': maxSpeed,
        'boardMaxSpeed': boardMaxSpeed,
        'elevGainM': elevGainM,
        'boardDistanceMi': boardDistanceMi,
        'wattHours': wattHours,
        'regenWh': regenWh,
        'effWhMi': effWhMi,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllTrips() async {
    final db = await database;
    return await db.query('trips', orderBy: 'startTime DESC');
  }

  Future<Map<String, dynamic>?> getLatestRangeCalibrationTrip() async {
    final db = await database;
    final rows = await db.query(
      'trips',
      where:
          'endTime IS NOT NULL AND boardDistanceMi >= ? AND (wattHours - regenWh) >= ? AND effWhMi > 0',
      whereArgs: [1.0, 5.0],
      orderBy: 'endTime DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getRecentRangeCalibrationTrips({
    int limit = 5,
  }) async {
    final db = await database;
    return await db.query(
      'trips',
      where:
          'endTime IS NOT NULL AND boardDistanceMi >= ? AND (wattHours - regenWh) >= ? AND effWhMi > 0',
      whereArgs: [1.0, 5.0],
      orderBy: 'endTime DESC',
      limit: limit,
    );
  }

  /// Finalize any trip left un-ended by a crash/kill (before its first 10 s
  /// checkpoint): derive end-time/distance/max from its telemetry, or drop it if
  /// it has no points. Run once on app start.
  Future<void> recoverOrphans() async {
    final db = await database;
    final orphans = await db.query('trips', where: 'endTime IS NULL');
    for (final o in orphans) {
      final id = o['id'] as int;
      final tel = await db.query(
        'telemetry',
        where: 'tripId = ?',
        whereArgs: [id],
        orderBy: 'timestamp ASC',
      );
      if (tel.isEmpty) {
        await deleteTrip(id);
        continue;
      }
      double dist = 0, maxSpd = 0;
      LatLng? prev;
      int? previousTimestamp;
      for (final r in tel) {
        final pt = LatLng(r['lat'] as double, r['lng'] as double);
        final timestamp = r['timestamp'] as int;
        if (prev != null && previousTimestamp != null) {
          final elapsedMs = timestamp - previousTimestamp;
          final gapDistanceM = const Distance().as(LengthUnit.Meter, prev, pt);
          final elapsedSeconds = elapsedMs / 1000.0;
          final plausible =
              elapsedMs > 0 &&
              elapsedMs <= 10000 &&
              gapDistanceM <= (elapsedSeconds * 35.0).clamp(75.0, 10000.0);
          if (plausible) dist += gapDistanceM;
        }
        prev = pt;
        previousTimestamp = timestamp;
        final s = (r['gpsSpeed'] as num).toDouble();
        if (s > maxSpd) maxSpd = s;
      }
      await updateTrip(id, tel.last['timestamp'] as int, dist, maxSpd, maxSpd);
    }
  }

  Future<void> deleteTrip(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      // Derived trails/waypoints own copied geometry. Keep them, but remove a
      // provenance pointer that would otherwise reference a deleted ride.
      await txn.update(
        'trails',
        {'sourceTripId': null},
        where: 'sourceTripId = ?',
        whereArgs: [id],
      );
      await txn.update(
        'waypoints',
        {'sourceTripId': null},
        where: 'sourceTripId = ?',
        whereArgs: [id],
      );
      await txn.delete('trips', where: 'id = ?', whereArgs: [id]);
      await txn.delete('telemetry', where: 'tripId = ?', whereArgs: [id]);
    });
  }

  /// Import a trip + its telemetry under a fresh id (re-links the rows). Used by
  /// the backup/restore so trips survive a reinstall. Returns the new trip id.
  Future<int> importTrip(
    Map<String, dynamic> trip,
    List<Map<String, dynamic>> telemetry,
  ) async {
    final db = await database;
    return await db.transaction((txn) async {
      final t = Map<String, dynamic>.from(trip)..remove('id');
      final newId = await txn.insert('trips', t);
      for (final s in telemetry) {
        final row = Map<String, dynamic>.from(s)
          ..remove('id')
          ..['tripId'] = newId;
        await txn.insert('telemetry', row);
      }
      return newId;
    });
  }

  // --- Telemetry ---

  Future<void> insertTelemetry(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('telemetry', data);
  }

  Future<List<Map<String, dynamic>>> getTripTelemetry(int tripId) async {
    final db = await database;
    return await db.query(
      'telemetry',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp ASC',
    );
  }

  // --- Curated trails ---

  Future<Trail> createTrailFromTrip({
    required int tripId,
    required String name,
    String description = '',
  }) async {
    final cleanName = _cleanName(name);
    final cleanDescription = description.trim();
    if (cleanDescription.length > 1000) {
      throw ArgumentError.value(description, 'description', 'Too long');
    }

    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'telemetry',
        columns: ['timestamp', 'lat', 'lng', 'altitude'],
        where: 'tripId = ?',
        whereArgs: [tripId],
        orderBy: 'timestamp ASC',
      );
      if (rows.length < 2) {
        throw StateError('This ride does not contain enough route points.');
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final pending = <({int segment, double lat, double lng, double alt})>[];
      var segment = 0;
      var distanceM = 0.0;
      int? previousTimestamp;
      LatLng? previousPoint;

      for (final row in rows) {
        final timestamp = row['timestamp'] as int;
        final point = LatLng(
          (row['lat'] as num).toDouble(),
          (row['lng'] as num).toDouble(),
        );
        final altitude = (row['altitude'] as num?)?.toDouble() ?? 0;

        if (previousPoint != null && previousTimestamp != null) {
          final elapsedMs = timestamp - previousTimestamp;
          final gapDistanceM = const Distance().as(
            LengthUnit.Meter,
            previousPoint,
            point,
          );
          final elapsedSeconds = elapsedMs / 1000.0;
          final implausibleJump =
              elapsedMs <= 0 ||
              gapDistanceM > (elapsedSeconds * 35.0).clamp(75.0, 10000.0);
          if (elapsedMs > 10000 || implausibleJump) {
            segment++;
          } else {
            distanceM += gapDistanceM;
          }
        }

        pending.add((
          segment: segment,
          lat: point.latitude,
          lng: point.longitude,
          alt: altitude,
        ));
        previousTimestamp = timestamp;
        previousPoint = point;
      }

      final trailId = await txn.insert('trails', {
        'sourceTripId': tripId,
        'name': cleanName,
        'description': cleanDescription,
        'surface': 'unknown',
        'difficulty': 'unknown',
        'direction': 'both',
        'visibility': 'private',
        'createdAt': now,
        'updatedAt': now,
        'distanceM': distanceM,
        'pointCount': pending.length,
        'segmentCount': segment + 1,
      });
      final batch = txn.batch();
      for (var sequence = 0; sequence < pending.length; sequence++) {
        final point = pending[sequence];
        batch.insert('trail_points', {
          'trailId': trailId,
          'sequence': sequence,
          'segment': point.segment,
          'lat': point.lat,
          'lng': point.lng,
          'altitudeM': point.alt,
        });
      }
      await batch.commit(noResult: true);
      return (await _getTrail(txn, trailId))!;
    });
  }

  Future<List<Trail>> getAllTrails() async {
    final db = await database;
    final rows = await db.query('trails', orderBy: 'updatedAt DESC');
    return rows.map(Trail.fromMap).toList(growable: false);
  }

  Future<Trail?> getTrail(int id) async {
    final db = await database;
    return _getTrail(db, id);
  }

  static Future<Trail?> _getTrail(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      'trails',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Trail.fromMap(rows.first);
  }

  Future<List<TrailPoint>> getTrailPoints(int trailId) async {
    final db = await database;
    final rows = await db.query(
      'trail_points',
      where: 'trailId = ?',
      whereArgs: [trailId],
      orderBy: 'sequence ASC',
    );
    return rows.map(TrailPoint.fromMap).toList(growable: false);
  }

  Future<void> updateTrailMetadata(Trail trail) async {
    final id = trail.id;
    if (id == null) throw ArgumentError('A persisted trail ID is required.');
    final cleanName = _cleanName(trail.name);
    final cleanDescription = trail.description.trim();
    if (cleanDescription.length > 1000) {
      throw ArgumentError.value(trail.description, 'description', 'Too long');
    }
    final db = await database;
    await db.update(
      'trails',
      {
        'name': cleanName,
        'description': cleanDescription,
        'surface': trail.surface,
        'difficulty': trail.difficulty,
        'direction': trail.direction,
        'visibility': trail.visibility,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTrail(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'waypoints',
        {'trailId': null},
        where: 'trailId = ?',
        whereArgs: [id],
      );
      await txn.delete('trail_points', where: 'trailId = ?', whereArgs: [id]);
      await txn.delete('trails', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> getTrailCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS count FROM trails');
    return (result.first['count'] as num).toInt();
  }

  /// Imports an already-curated trail and point copy. IDs are always rewritten
  /// and optional source IDs must already be remapped by the backup importer.
  Future<int> importTrail(
    Trail trail,
    List<TrailPoint> points, {
    int? sourceTripId,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final map = trail.toMap(includeId: false)
        ..['sourceTripId'] = sourceTripId;
      final trailId = await txn.insert('trails', map);
      final batch = txn.batch();
      for (final point in points) {
        final pointMap = point.toMap(includeId: false)..['trailId'] = trailId;
        batch.insert('trail_points', pointMap);
      }
      await batch.commit(noResult: true);
      return trailId;
    });
  }

  // --- Waypoints ---

  Future<int> createWaypoint(Waypoint waypoint) async {
    final db = await database;
    final map = waypoint.toMap(includeId: false)
      ..['name'] = _cleanName(waypoint.name);
    return db.insert('waypoints', map);
  }

  Future<List<Waypoint>> getAllWaypoints() async {
    final db = await database;
    final rows = await db.query('waypoints', orderBy: 'updatedAt DESC');
    return rows.map(Waypoint.fromMap).toList(growable: false);
  }

  Future<List<Waypoint>> getWaypointsForTrail(int trailId) async {
    final db = await database;
    final rows = await db.query(
      'waypoints',
      where: 'trailId = ?',
      whereArgs: [trailId],
      orderBy: 'updatedAt DESC',
    );
    return rows.map(Waypoint.fromMap).toList(growable: false);
  }

  Future<void> updateWaypoint(Waypoint waypoint) async {
    final id = waypoint.id;
    if (id == null) throw ArgumentError('A persisted waypoint ID is required.');
    final db = await database;
    final map = waypoint.toMap(includeId: false)
      ..['name'] = _cleanName(waypoint.name)
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await db.update('waypoints', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteWaypoint(int id) async {
    final db = await database;
    await db.delete('waypoints', where: 'id = ?', whereArgs: [id]);
  }

  static String _cleanName(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty || clean.length > 80) {
      throw ArgumentError.value(value, 'name', 'Must be 1–80 characters.');
    }
    return clean;
  }

  // --- DB Stats ---

  Future<int> getDatabaseSize() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'trips.db');
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }
}
