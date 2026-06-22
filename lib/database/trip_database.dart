import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startTime INTEGER NOT NULL,
        endTime INTEGER,
        distance REAL NOT NULL,
        maxSpeed REAL NOT NULL,
        boardMaxSpeed REAL NOT NULL
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

  Future<void> updateTrip(int id, int endTime, double distance, double maxSpeed, double boardMaxSpeed) async {
    final db = await instance.database;
    await db.update(
      'trips',
      {
        'endTime': endTime,
        'distance': distance,
        'maxSpeed': maxSpeed,
        'boardMaxSpeed': boardMaxSpeed,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllTrips() async {
    final db = await instance.database;
    return await db.query('trips', orderBy: 'startTime DESC');
  }

  Future<void> deleteTrip(int id) async {
    final db = await instance.database;
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
    // Cascade delete on telemetry
    await db.delete('telemetry', where: 'tripId = ?', whereArgs: [id]);
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
