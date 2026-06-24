import 'package:flutter_test/flutter_test.dart';
import 'package:esk8os_mobile/ble/esk8os_ble.dart';

/// Tests for the BLE settings contract (spec §4): parsing the board's config and
/// building partial write maps for the writable fields.
void main() {
  group('BoardSettings.fromJson', () {
    test('parses a full settings payload', () {
      final s = BoardSettings.fromJson({
        'mph': true,
        'theme': 'CAM',
        'poles': 7,
        'wheel': 203,
        'gear': 2.5,
        'bat_s': 10,
        'profile': 0,
        'packAh': 16.5,
        'stopCell': 3.3,
        'whmi': 25,
        'bright': 80,
        'demo': false,
        'rider': 'ZOMBIE',
      });

      expect(s.mph, true);
      expect(s.theme, 'CAM');
      expect(s.poles, 7);
      expect(s.wheelMm, 203);
      expect(s.gear, 2.5);
      expect(s.batterySeries, 10);
      expect(s.packAh, 16.5);
      expect(s.stopCellV, 3.3);
      expect(s.whPerMile, 25);
      expect(s.brightness, 80);
      expect(s.demo, false);
      expect(s.rider, 'ZOMBIE');
    });

    test('brightness defaults to 100 when absent (pre-0.9.0 board)', () {
      final s = BoardSettings.fromJson({'mph': false});
      expect(s.brightness, 100);
    });

    test('mph/demo are strict booleans (only true is true)', () {
      final s = BoardSettings.fromJson({'mph': 1, 'demo': 'yes'});
      expect(s.mph, false);
      expect(s.demo, false);
    });

    test('rider defaults to empty string when absent', () {
      final s = BoardSettings.fromJson({});
      expect(s.rider, '');
    });
  });

  group('BoardSettings.writeJson', () {
    test('includes only the fields that were passed', () {
      final m = BoardSettings.writeJson(mph: true, brightness: 60);
      expect(m, {'mph': true, 'bright': 60});
    });

    test('maps dart field names to the wire keys', () {
      final m = BoardSettings.writeJson(
        batterySeries: 12,
        stopCellV: 3.4,
        whPerMile: 28,
        rider: 'JOE',
      );
      expect(m, {'bat_s': 12, 'stopCell': 3.4, 'whmi': 28, 'rider': 'JOE'});
    });

    test('is empty when nothing is passed', () {
      expect(BoardSettings.writeJson(), isEmpty);
    });
  });
}
