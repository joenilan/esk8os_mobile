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

    test('switch count stays zero for a pure board ride', () {
      final fusion = RideDistanceFusion();
      fusion.update(
        gpsKm: 0,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 0,
      );
      fusion.update(
        gpsKm: 0.1,
        gpsLive: true,
        boardKm: 0.1,
        boardLive: true,
        nowMs: 1000,
      );
      fusion.update(
        gpsKm: 0.2,
        gpsLive: true,
        boardKm: 0.2,
        boardLive: true,
        nowMs: 2000,
      );

      expect(fusion.source, RideDistanceSource.board);
      expect(fusion.switchCount, 0);
    });

    test('BLE dropout: GPS covers the gap, board reconnect superseding it', () {
      final fusion = RideDistanceFusion();
      // Ride underway: GPS acquires first, the board counter proves
      // advancement moments later (a few meters), and takes over at 2 km.
      fusion.update(gpsKm: 0, gpsLive: true, boardKm: 0, boardLive: true, nowMs: 0);
      fusion.update(
        gpsKm: 0.01,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 10000,
      );
      fusion.update(
        gpsKm: 0.02,
        gpsLive: true,
        boardKm: 0.01,
        boardLive: true,
        nowMs: 20000,
      );
      fusion.update(
        gpsKm: 2.0,
        gpsLive: true,
        boardKm: 2.0,
        boardLive: true,
        nowMs: 100000,
      );
      expect(fusion.source, RideDistanceSource.board);
      expect(fusion.switchCount, 0);

      // BLE drops. GPS's cumulative total already includes the 2.0 km the
      // board covered, so the fused figure must not jump at the switch.
      final duringDropout = fusion.update(
        gpsKm: 3.0,
        gpsLive: true,
        boardKm: 2.0,
        boardLive: false,
        nowMs: 200000,
      );
      expect(fusion.source, RideDistanceSource.gps);
      expect(duringDropout, closeTo(2.0, 0.001));
      expect(fusion.switchCount, 1);

      // The dropout tail accrues from GPS alone.
      final tail = fusion.update(
        gpsKm: 3.5,
        gpsLive: true,
        boardKm: 2.0,
        boardLive: false,
        nowMs: 300000,
      );
      expect(tail, closeTo(2.5, 0.001));

      // The VESC kept counting while BLE was down: its counter advanced
      // through the gap and is the authoritative whole-ride total (3.5).
      // The GPS-covered 0.5 km must not be double-counted.
      final boardCameBack = fusion.update(
        gpsKm: 3.5,
        gpsLive: true,
        boardKm: 3.5,
        boardLive: true,
        nowMs: 400000,
      );
      expect(fusion.source, RideDistanceSource.board);
      expect(boardCameBack, closeTo(3.5, 0.001));
      expect(fusion.switchCount, 2);
    });

    test('BLE dropout with a powered-off board keeps the GPS tail', () {
      final fusion = RideDistanceFusion();
      // Ride underway: GPS acquires first, the board counter takes over.
      fusion.update(gpsKm: 0, gpsLive: true, boardKm: 0, boardLive: true, nowMs: 0);
      fusion.update(
        gpsKm: 0.01,
        gpsLive: true,
        boardKm: 0,
        boardLive: true,
        nowMs: 10000,
      );
      fusion.update(
        gpsKm: 0.02,
        gpsLive: true,
        boardKm: 0.01,
        boardLive: true,
        nowMs: 20000,
      );
      fusion.update(
        gpsKm: 2.0,
        gpsLive: true,
        boardKm: 2.0,
        boardLive: true,
        nowMs: 100000,
      );
      fusion.update(
        gpsKm: 3.0,
        gpsLive: true,
        boardKm: 2.0,
        boardLive: false,
        nowMs: 200000,
      );
      final withTail = fusion.update(
        gpsKm: 3.5,
        gpsLive: true,
        boardKm: 2.0,
        boardLive: false,
        nowMs: 300000,
      );
      // The board lost power in the gap — its counter resumes where it
      // froze. The GPS-covered tail (1.5 km) stays in the total; the rider
      // is stationary at the reconnect, so the total holds at 2.5.
      final afterReconnect = fusion.update(
        gpsKm: 3.5,
        gpsLive: true,
        boardKm: 2.0,
        boardLive: true,
        nowMs: 400000,
      );

      expect(withTail, closeTo(2.5, 0.001));
      expect(afterReconnect, closeTo(2.5, 0.001));
      // No return transition: the frozen counter is treated as stalled, so
      // GPS remains the distance source for the rest of the ride.
      expect(fusion.switchCount, 1);
    });
  });
}
