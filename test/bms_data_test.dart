import 'package:esk8os_mobile/ble/esk8os_ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BmsData trip serialization', () {
    test('round-trips the complete 0006 snapshot', () {
      const original = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask,
        alarmLevel: 1,
        rawFaultBytes: '11000000000000',
        lastRawFaultBytes: '00000800000000',
        lastFaultAgeSec: 42,
        packVolts: 39.62,
        current: -12.4,
        soc: 78,
        remainingAh: 24.96,
        cycles: 42,
        cellCount: 10,
        cellsMv: [3962, 3968, 3961, 3970, 3966, 3959, 3892, 3964, 3967, 3960],
        balMask: 4,
        staleMask: 32,
        minMv: 3892,
        minCell: 7,
        maxMv: 3970,
        maxCell: 4,
        deltaMv: 78,
        temps: [26, 28],
        tempMin: 26,
        tempMax: 28,
        chargeMos: true,
        dischargeMos: true,
        fault: false,
      );

      final stored = original.toStorageJson();
      final restored = BmsData.tryFromStorageJson(stored)!;

      expect(restored.link, true);
      expect(restored.freshnessMask, BmsData.allFreshMask);
      expect(restored.alarmLevel, 1);
      expect(restored.effectiveAlarmLevel, 1);
      expect(restored.alarmLabel, 'WARNING');
      expect(restored.rawFaultBytes, '11000000000000');
      expect(restored.lastRawFaultBytes, '00000800000000');
      expect(restored.lastFaultAgeSec, 42);
      expect(restored.lastFaultLabel, 'DISCHARGE OVERCURRENT PROTECTION');
      expect(restored.packVolts, 39.62);
      expect(restored.current, -12.4);
      expect(restored.soc, 78);
      expect(restored.remainingAh, 24.96);
      expect(restored.cycles, 42);
      expect(restored.cellCount, 10);
      expect(restored.cellsMv, original.cellsMv);
      expect(restored.balMask, 4);
      expect(restored.staleMask, 32);
      expect(restored.minMv, 3892);
      expect(restored.minCell, 7);
      expect(restored.maxMv, 3970);
      expect(restored.maxCell, 4);
      expect(restored.deltaMv, 78);
      expect(restored.temps, [26, 28]);
      expect(restored.tempMin, 26);
      expect(restored.tempMax, 28);
      expect(restored.chargeMos, true);
      expect(restored.dischargeMos, true);
      expect(restored.fault, false);
    });

    test(
      'legacy payload keeps link freshness and classifies flt conservatively',
      () {
        final legacyOk = BmsData.fromJson({
          'link': true,
          'pv': 40,
          'flt': false,
        });
        expect(legacyOk.freshnessMask, isNull);
        expect(legacyOk.alarmLevel, isNull);
        expect(legacyOk.packFresh, true);
        expect(legacyOk.cellsFresh, true);
        expect(legacyOk.effectiveAlarmLevel, 0);

        final legacyFault = BmsData.fromJson({'link': true, 'flt': true});
        expect(legacyFault.effectiveAlarmLevel, 2);
        expect(legacyFault.alarmLabel, 'UNCLASSIFIED ALERT');
      },
    );

    test('freshness mask invalidates only the missing response groups', () {
      final b = BmsData.fromJson({
        'link': true,
        'fv': BmsData.allFreshMask & ~(1 << BmsData.freshnessCells),
        'al': 0,
        'cv': [4000, 3990],
      });

      expect(b.packFresh, true);
      expect(b.cellsFresh, false);
      expect(b.cellStale(0), true);
      expect(b.effectiveAlarmLevel, 0);
    });

    test('explicit alert and stale alarm levels remain distinct', () {
      const alert = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask,
        alarmLevel: 2,
      );
      const stale = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask & ~(1 << BmsData.freshnessFaults),
        alarmLevel: 3,
      );

      expect(alert.effectiveAlarmLevel, 2);
      expect(alert.alarmLabel, 'ALERT');
      expect(stale.effectiveAlarmLevel, 3);
      expect(stale.alarmLabel, 'FAULT DATA STALE');
    });

    test('verified overcurrent bytes receive exact rider-facing labels', () {
      const warning = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask,
        alarmLevel: 2,
        rawFaultBytes: '00000400000000',
      );
      const protection = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask,
        alarmLevel: 2,
        rawFaultBytes: '00000800000000',
      );

      expect(warning.alarmLabel, 'DISCHARGE OVERCURRENT WARNING');
      expect(protection.alarmLabel, 'DISCHARGE OVERCURRENT PROTECTION');
    });

    test('weak-cell threshold ignores a normal minimum', () {
      const healthy = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask,
        cellsMv: [4177, 4187],
        minCell: 1,
        deltaMv: 10,
      );
      const weak = BmsData(
        link: true,
        freshnessMask: BmsData.allFreshMask,
        cellsMv: [4100, 4180],
        minCell: 1,
        deltaMv: 80,
      );

      expect(healthy.cellWeak(0), false);
      expect(weak.cellWeak(0), true);
    });

    test('link-down samples do not retain stale measurements', () {
      const down = BmsData(link: false, packVolts: 40, cellsMv: [4000]);

      expect(down.toJson(), const {'link': false});
      final restored = BmsData.fromJson(down.toJson());
      expect(restored.link, false);
      expect(restored.packVolts, 0);
      expect(restored.cellsMv, isEmpty);
    });
  });
}
