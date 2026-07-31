import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_prefs.dart';
import '../views/trip_view.dart';
import '../widgets/esk8_theme.dart';
import '../widgets/esk8_widgets.dart';
import 'trip_history_page.dart';

/// Board-independent ride recorder. GPS is the explicit primary source; board
/// telemetry and BMS values remain unavailable rather than being simulated.
class PhoneRidePage extends StatefulWidget {
  const PhoneRidePage({super.key});

  @override
  State<PhoneRidePage> createState() => _PhoneRidePageState();
}

class _PhoneRidePageState extends State<PhoneRidePage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> _openLibrary() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripHistoryPage(isMph: AppPrefs.preferredMph),
      ),
    );
    if (mounted) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) => SubPageScaffold(
    title: 'Phone Ride · GPS',
    actions: [
      IconButton(
        tooltip: 'Library',
        onPressed: _openLibrary,
        icon: Icon(Icons.route_outlined, color: Esk8Theme.accent),
      ),
    ],
    children: [
      Expanded(
        child: TripView(
          telemetry: null,
          settings: null,
          isMphOverride: AppPrefs.preferredMph,
        ),
      ),
    ],
  );
}
