import 'package:flutter_test/flutter_test.dart';
import 'package:esk8os_mobile/ble/esk8os_ble.dart';

/// Tests for the BLE telemetry contract (spec §3). The board sends display-ready
/// JSON numbers; these lock in the field mapping, defaults, and type coercion so
/// a renamed/missing field (like the recently-added `tmov`) can't regress silently.
void main() {
  group('Telemetry.fromJson', () {
    test('maps a full payload to the right fields', () {
      final t = Telemetry.fromJson({
        'live': true,
        'vesc': true,
        'spd': 24.5,
        'bat': 73,
        'v': 41.2,
        'w': 850,
        'mtr_t': 48,
        'esc_t': 39,
        'btemp': 31,
        'rng': 18.4,
        'max_s': 31.2,
        'wh': 120.4,
        'bata': 22.8,
        'mota': 30.1,
        'duty': 35,
        'pkw': 1850,
        'mpw': 2100,
        'whr': 6.2,
        'minv': 40.1,
        'avs': 18.3,
        'trip': 6.2,
        'odo': 412.5,
        'est': 21.7,
        'lrng': 3.1,
        'lest': 24.4,
        'eff': 25.9,
        'minvl': 36.5,
        'mba': 37.9,
        'cellv': 3.65,
        'rwarn': 2,
        'sagc': 3,
        'thome': 18,
        'tlimp': 0,
        'fault': 0,
        'rtime': 1843,
        'tmov': 1290,
        'ppm': 0.42,
        'ppmok': true,
        'lfault': 5,
        'slave': true,
        'm1a': 18.3,
        'm2a': 17.9,
        'fw': '6.2',
      });

      expect(t.live, true);
      expect(t.vescConnected, true);
      expect(t.speed, 24.5);
      expect(t.battery, 73);
      expect(t.volts, 41.2);
      expect(t.watts, 850);
      expect(t.peakWatts, 1850);
      expect(t.maxWattsSession, 2100);
      expect(t.wattHours, 120.4);
      expect(t.regenWh, 6.2);
      expect(t.trip, 6.2);
      expect(t.odometer, 412.5);
      expect(t.avgSpeed, 18.3);
      expect(t.limpRange, 3.1);
      expect(t.limpEstRange, 24.4);
      expect(t.efficiency, 25.9);
      expect(t.minLoadedVolts, 36.5);
      expect(t.maxBatteryAmps, 37.9);
      expect(t.cellVolts, 3.65);
      expect(t.rangeWarning, 2);
      expect(t.sagEvents, 3);
      expect(t.homeVoltageSeconds, 18);
      expect(t.limpVoltageSeconds, 0);
      expect(t.rideSeconds, 1843);
      // The field this whole task hinged on:
      expect(t.tripMovingSeconds, 1290);
      // Remote + diagnostics fields:
      expect(t.throttle, 0.42);
      expect(t.remoteConnected, true);
      expect(t.lastFault, 5);
      expect(t.slaveOnline, true);
      expect(t.masterMotorAmps, 18.3);
      expect(t.slaveMotorAmps, 17.9);
      expect(t.vescFw, '6.2');
    });

    test('remote/diagnostics fields default safely when absent', () {
      final t = Telemetry.fromJson({'spd': 10});
      expect(t.live, true);
      expect(t.vescConnected, true);
      expect(t.throttle, 0.0);
      expect(t.remoteConnected, false);
      expect(t.slaveOnline, false);
      expect(t.vescFw, '');
      expect(t.rangeWarning, 0);
      expect(t.sagEvents, 0);
    });

    test('live/link flags parse false for no-VESC state', () {
      final t = Telemetry.fromJson({'live': false, 'vesc': false});
      expect(t.live, false);
      expect(t.vescConnected, false);
    });

    test('tmov defaults to 0 when absent (older firmware)', () {
      final t = Telemetry.fromJson({'spd': 10});
      expect(t.tripMovingSeconds, 0);
      expect(t.rideSeconds, 0);
    });

    test('missing numeric fields default to 0', () {
      final t = Telemetry.fromJson({});
      expect(t.speed, 0.0);
      expect(t.battery, 0);
      expect(t.trip, 0.0);
      expect(t.fault, 0);
    });

    test('coerces int->double and double->int across the num/int split', () {
      // spd/eff are double fields, w is an int field. JSON may carry either.
      final t = Telemetry.fromJson({'spd': 24, 'eff': 26, 'w': 850.0});
      expect(t.speed, 24.0);
      expect(t.speed, isA<double>());
      expect(t.efficiency, 26.0);
      expect(t.efficiency, isA<double>());
      expect(t.watts, 850);
      expect(t.watts, isA<int>());
    });

    test('non-numeric values fall back to 0 rather than throwing', () {
      final t = Telemetry.fromJson({'spd': 'fast', 'bat': null});
      expect(t.speed, 0.0);
      expect(t.battery, 0);
    });
  });
}
