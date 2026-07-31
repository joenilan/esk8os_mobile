import 'package:esk8os_mobile/services/ride_distance_fusion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RideDistanceFusion', () {
    test('uses GPS when a live board trip remains stuck at zero', () {
      final fusion = RideDistanceFusion();

      fusion.update(
        gpsKm: 0,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 0,
      );
      final distance = fusion.update(
        gpsKm: 2.4,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 120000,
      );

      expect(fusion.source, RideDistanceSource.gps);
      expect(distance, closeTo(2.4, 0.001));
    });

    test('promotes advancing board odometry without a visible jump', () {
      final fusion = RideDistanceFusion();
      fusion.update(
        gpsKm: 0.20,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 1000,
      );
      final before = fusion.distanceKm;
      final after = fusion.update(
        gpsKm: 0.21,
        gpsLive: true,
        boardKm: 0.01,
        boardLive: true,
        nowMs: 2000,
      );

      expect(fusion.source, RideDistanceSource.board);
      expect(after, closeTo(before, 0.001));
      expect(
        fusion.update(
          gpsKm: 0.30,
          gpsLive: true,
          boardKm: 0.11,
          boardLive: true,
          nowMs: 3000,
        ),
        closeTo(before + 0.10, 0.001),
      );
    });

    test('a board reset falls back to GPS and never reduces the trip', () {
      final fusion = RideDistanceFusion();
      fusion.update(
        gpsKm: 1.0,
        gpsLive: true,
        boardKm: 1.0,
        boardLive: true,
        nowMs: 1000,
      );
      fusion.update(
        gpsKm: 1.1,
        gpsLive: true,
        boardKm: 1.1,
        boardLive: true,
        nowMs: 2000,
      );
      final beforeReset = fusion.distanceKm;
      final afterReset = fusion.update(
        gpsKm: 1.2,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 3000,
      );

      expect(fusion.source, RideDistanceSource.gps);
      expect(afterReset, greaterThanOrEqualTo(beforeReset));
      expect(
        fusion.update(
          gpsKm: 1.5,
          gpsLive: true,
          boardKm: 0,
          boardLive: true,
          nowMs: 4000,
        ),
        closeTo(afterReset + 0.3, 0.001),
      );
    });

    test('falls back when board stalls after previously advancing', () {
      final fusion = RideDistanceFusion();
      fusion.update(
        gpsKm: 0,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 0,
      );
      fusion.update(
        gpsKm: 0.01,
        gpsLive: true,
        boardKm: 0.01,
        boardLive: true,
        nowMs: 1000,
      );
      final atStall = fusion.distanceKm;
      fusion.update(
        gpsKm: 0.20,
        gpsLive: true,
        boardKm: 0.01,
        boardLive: true,
        nowMs: 32000,
      );

      expect(fusion.source, RideDistanceSource.gps);
      expect(fusion.distanceKm, closeTo(atStall, 0.001));
      expect(
        fusion.update(
          gpsKm: 0.40,
          gpsLive: true,
          boardKm: 0.01,
          boardLive: true,
          nowMs: 33000,
        ),
        closeTo(atStall + 0.20, 0.001),
      );
    });
  });
}
