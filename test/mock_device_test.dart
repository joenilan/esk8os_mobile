import 'package:esk8os_mobile/ble/esk8os_ble.dart';
import 'package:esk8os_mobile/ble/mock_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UNSET returns a mock rider override to the VESC tier', () async {
    SharedPreferences.setMockInitialValues({});
    final device = MockDevice();

    await device.writeSettings({'packAh': 20.0});
    expect((await device.readBaseConfig())!.src['ah'], 'r');

    await device.sendCommand(Esk8Commands.unset('packAh'));

    expect((await device.readSettings())!.packAh, 32.0);
    expect((await device.readBaseConfig())!.src['ah'], 'v');
  });

  test(
    'mock exposes explicit demo battery source and expanded BMS evidence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final device = MockDevice();
      final telemetry = device.telemetry().first;
      final bms = device.bms().first;

      await device.connect();
      final t = await telemetry;
      final b = await bms;
      await device.disconnect();

      expect(t.live, true);
      expect(t.vescConnected, false);
      expect(t.batteryLive, true);
      expect(t.batterySource, 'demo');
      expect(b.freshnessMask, BmsData.allFreshMask);
      expect(b.alarmLevel, 1);
      expect(b.rawFaultBytes, '11000000000000');
      expect(b.deltaMv, lessThan(50));
    },
  );
}
