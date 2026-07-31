import 'package:esk8os_mobile/ble/esk8os_ble.dart';
import 'package:esk8os_mobile/ble/mock_device.dart';
import 'package:esk8os_mobile/views/bms_view.dart';
import 'package:esk8os_mobile/widgets/esk8_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page(BmsData data) => MaterialApp(
    home: Scaffold(
      body: BmsView(
        key: UniqueKey(),
        dev: MockDevice(),
        settings: null,
        bmsStream: Stream.value(data),
      ),
    ),
  );

  testWidgets(
    'Level-1 alarm is a warning and an idle pack is not discharging',
    (tester) async {
      const data = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask,
        alarmLevel: 1,
        rawFaultBytes: '11000000000000',
        packVolts: 41.8,
        current: 0.1,
        soc: 100,
        remainingAh: 32,
        cellCount: 2,
        cellsMv: [4177, 4187],
        minMv: 4177,
        minCell: 1,
        maxMv: 4187,
        maxCell: 2,
        deltaMv: 10,
        temps: [21],
        tempMin: 21,
        tempMax: 21,
        chargeMos: true,
        dischargeMos: true,
        fault: true,
      );

      await tester.pumpWidget(page(data));
      await tester.pump();

      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('FAULT'), findsNothing);
      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('11000000000000'), findsOneWidget);
      final healthyMin = tester.widget<Text>(find.text('4177'));
      expect(healthyMin.style?.color, Esk8Theme.textPrimary);
    },
  );

  testWidgets('a genuinely lagging minimum cell receives weak-cell treatment', (
    tester,
  ) async {
    const data = BmsData(
      link: true,
      freshnessMask: BmsData.allFreshMask,
      alarmLevel: 0,
      packVolts: 41,
      soc: 80,
      cellCount: 2,
      cellsMv: [4070, 4180],
      minMv: 4070,
      minCell: 1,
      maxMv: 4180,
      maxCell: 2,
      deltaMv: 110,
    );

    await tester.pumpWidget(page(data));
    await tester.pump();

    final weakMin = tester.widget<Text>(find.text('4070'));
    expect(weakMin.style?.color, Esk8Theme.danger);
  });

  testWidgets('link-down help reflects the wireless UART-K ownership rules', (
    tester,
  ) async {
    await tester.pumpWidget(page(const BmsData(link: false)));
    await tester.pump();

    expect(find.textContaining('close the Daly app'), findsOneWidget);
    expect(find.textContaining('UART wiring'), findsNothing);
  });

  testWidgets('alert and stale fault evidence are not downplayed', (
    tester,
  ) async {
    const alert = BmsData(
      link: true,
      freshnessMask: BmsData.allFreshMask,
      alarmLevel: 2,
      rawFaultBytes: '01000000000000',
    );
    await tester.pumpWidget(page(alert));
    await tester.pump();
    expect(find.text('ALERT'), findsOneWidget);

    const stale = BmsData(
      link: true,
      freshnessMask: BmsData.allFreshMask & ~(1 << BmsData.freshnessFaults),
      alarmLevel: 3,
      rawFaultBytes: '00000000000000',
    );
    await tester.pumpWidget(page(stale));
    await tester.pump();
    expect(find.text('FAULT DATA STALE'), findsOneWidget);
    expect(find.textContaining('FAULTS'), findsOneWidget);
  });
}
