import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';
import '../database/trip_database.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';

/// LOGS — mirrors the board's Logs page: a list of recent ride summaries. Uses
/// the app's own recorded trips (SQLite); the board's on-flash CSV logs come
/// over the WiFi export instead.
class LogsView extends StatefulWidget {
  final BoardSettings? settings;
  const LogsView({super.key, required this.settings});

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  late Future<List<Map<String, dynamic>>> _trips;

  @override
  void initState() {
    super.initState();
    _trips = TripDatabase.instance.getAllTrips();
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${mon[d.month - 1]} ${d.day}  $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isMph = widget.settings?.mph == true;
    final distUnit = isMph ? 'mi' : 'km';
    final spdUnit = isMph ? 'mph' : 'km/h';

    return PageChrome(
      sections: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _trips,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const FieldSection(title: 'Recent Rides', rows: [
                Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()))
              ]);
            }
            final trips = (snap.data ?? const []).take(10).toList();
            if (trips.isEmpty) {
              return const FieldSection(title: 'Recent Rides', rows: [
                Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('No recorded rides yet', style: TextStyle(color: Esk8Theme.dim))))
              ]);
            }
            return FieldSection(
              title: 'Recent Rides',
              rows: [
                for (final t in trips)
                  _LogRow(
                    date: _date(t['startTime'] as int),
                    dist: ((t['distance'] as num) / (isMph ? 1609.34 : 1000)).toStringAsFixed(2),
                    distUnit: distUnit,
                    maxSpeed: ((t['maxSpeed'] as num) / (isMph ? 1.60934 : 1)).toStringAsFixed(0),
                    spdUnit: spdUnit,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  final String date, dist, distUnit, maxSpeed, spdUnit;
  const _LogRow({required this.date, required this.dist, required this.distUnit, required this.maxSpeed, required this.spdUnit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(date, style: const TextStyle(fontSize: 13, color: Esk8Theme.label))),
          Text(dist, style: Esk8Theme.number(24)),
          Text(' $distUnit  ', style: const TextStyle(fontSize: 12, color: Esk8Theme.dim)),
          Text(maxSpeed, style: Esk8Theme.number(24, color: Esk8Theme.accent)),
          Text(' $spdUnit', style: const TextStyle(fontSize: 12, color: Esk8Theme.dim)),
        ],
      ),
    );
  }
}
