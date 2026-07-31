import 'package:esk8os_mobile/ble/esk8os_ble.dart';
import 'package:esk8os_mobile/views/dash_view.dart';
import 'package:esk8os_mobile/views/hud_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parked = Telemetry(
    live: false,
    vescConnected: false,
    batteryLive: true,
    batterySource: 'daly',
    speed: 0,
    battery: 100,
    volts: 41.8,
    watts: 0,
    motorTempC: 0,
    escTempC: 0,
    range: 21.4,
    maxSpeed: 0,
    wattHours: 0,
    batteryTempC: 21,
    cellVolts: 4.18,
    limpRange: 24.6,
    estRange: 21.4,
    limpEstRange: 24.6,
  );

  testWidgets('HUD retains Daly battery fields and masks drivetrain zeroes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HudView(telemetry: parked, settings: null)),
      ),
    );

    expect(find.text('100'), findsOneWidget);
    expect(find.text('41.8'), findsOneWidget);
    expect(find.text('21.4'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(2)); // speed and watts
  });

  testWidgets('dashboard masks drive-only rows but retains battery/range', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DashView(telemetry: parked, settings: null)),
      ),
    );

    expect(find.text('41.8'), findsOneWidget);
    expect(find.text('21.4'), findsNWidgets(2));
    expect(find.text('4.18'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
  });
}
