import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/trip_database.dart';

/// Trip backup / restore. Lets you pull all recorded rides out to a JSON file
/// (shared off the phone, so it survives an uninstall) and read them back in —
/// the safety net so an app update / re-signing can't lose your history.
class TripBackup {
  static const int _formatVersion = 1;

  /// Export every trip + its telemetry to a JSON file and open the share sheet
  /// (save to Drive/Files/etc). Returns the number of trips exported.
  static Future<int> export() async {
    final db = TripDatabase.instance;
    final trips = await db.getAllTrips();
    final out = <String, dynamic>{
      'format': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'trips': [
        for (final t in trips)
          {
            'trip': t,
            'telemetry': await db.getTripTelemetry(t['id'] as int),
          },
      ],
    };

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file = File('${dir.path}/esk8_trips_$stamp.json');
    await file.writeAsString(jsonEncode(out));

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'ESK8OS trip backup'),
    );
    return trips.length;
  }

  /// Pick a previously-exported JSON file and import the trips into the DB.
  /// Returns the number of trips imported.
  static Future<int> import() async {
    const typeGroup = XTypeGroup(label: 'backup', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return 0;

    final data = jsonDecode(await picked.readAsString());
    if (data is! Map || data['trips'] is! List) {
      throw const FormatException('Not a valid ESK8OS trip backup');
    }
    final db = TripDatabase.instance;
    var count = 0;
    for (final entry in (data['trips'] as List)) {
      if (entry is Map &&
          entry['trip'] is Map &&
          entry['telemetry'] is List) {
        await db.importTrip(
          Map<String, dynamic>.from(entry['trip'] as Map),
          [for (final s in (entry['telemetry'] as List)) Map<String, dynamic>.from(s as Map)],
        );
        count++;
      }
    }
    return count;
  }
}
