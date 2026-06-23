import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';

class TripDatabase {
  static final TripDatabase instance = TripDatabase._init();
  static Database? _database;

  TripDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('trips.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  /// Schema migrations — additive ALTERs so existing trips are preserved.
  Future<void> _upgradeDB(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      // v2: elevation. Climb on the trip, per-point altitude for GPX export.
      await db.execute('ALTER TABLE trips ADD COLUMN elevGainM REAL DEFAULT 0');
      await db.execute('ALTER TABLE telemetry ADD COLUMN altitude REAL DEFAULT 0');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startTime INTEGER NOT NULL,
        endTime INTEGER,
        distance REAL NOT NULL,
        maxSpeed REAL NOT NULL,
        boardMaxSpeed REAL NOT NULL,
        elevGainM REAL DEFAULT 0
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
        FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- Trips ---

  Future<int> createTrip(int startTime) async {
    final db = await instance.database;
    return await db.insert('trips', {
      'startTime': startTime,
      'distance': 0.0,
      'maxSpeed': 0.0,
      'boardMaxSpeed': 0.0,
    });
  }

  Future<void> updateTrip(int id, int endTime, double distance, double maxSpeed, double boardMaxSpeed,
      {double elevGainM = 0}) async {
    final db = await instance.database;
    await db.update(
      'trips',
      {
        'endTime': endTime,
        'distance': distance,
        'maxSpeed': maxSpeed,
        'boardMaxSpeed': boardMaxSpeed,
        'elevGainM': elevGainM,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllTrips() async {
    final db = await instance.database;
    return await db.query('trips', orderBy: 'startTime DESC');
  }

  /// Finalize any trip left un-ended by a crash/kill (before its first 10 s
  /// checkpoint): derive end-time/distance/max from its telemetry, or drop it if
  /// it has no points. Run once on app start.
  Future<void> recoverOrphans() async {
    final db = await instance.database;
    final orphans = await db.query('trips', where: 'endTime IS NULL');
    for (final o in orphans) {
      final id = o['id'] as int;
      final tel = await db.query('telemetry', where: 'tripId = ?', whereArgs: [id], orderBy: 'timestamp ASC');
      if (tel.isEmpty) {
        await deleteTrip(id);
        continue;
      }
      double dist = 0, maxSpd = 0;
      LatLng? prev;
      for (final r in tel) {
        final pt = LatLng(r['lat'] as double, r['lng'] as double);
        if (prev != null) dist += const Distance().as(LengthUnit.Meter, prev, pt);
        prev = pt;
        final s = (r['gpsSpeed'] as num).toDouble();
        if (s > maxSpd) maxSpd = s;
      }
      await updateTrip(id, tel.last['timestamp'] as int, dist, maxSpd, maxSpd);
    }
  }

  Future<void> deleteTrip(int id) async {
    final db = await instance.database;
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
    // Cascade delete on telemetry
    await db.delete('telemetry', where: 'tripId = ?', whereArgs: [id]);
  }

  /// Import a trip + its telemetry under a fresh id (re-links the rows). Used by
  /// the backup/restore so trips survive a reinstall. Returns the new trip id.
  Future<int> importTrip(Map<String, dynamic> trip, List<Map<String, dynamic>> telemetry) async {
    final db = await instance.database;
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
    final db = await instance.database;
    await db.insert('telemetry', data);
  }

  Future<List<Map<String, dynamic>>> getTripTelemetry(int tripId) async {
    final db = await instance.database;
    return await db.query('telemetry', where: 'tripId = ?', whereArgs: [tripId], orderBy: 'timestamp ASC');
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
