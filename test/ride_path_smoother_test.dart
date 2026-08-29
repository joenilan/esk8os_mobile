import 'dart:math';

import 'package:esk8os_mobile/services/ride_path_smoother.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RidePathSmoother', () {
    test('short tracks pass through unchanged in content', () {
      const two = [LatLng(40.0, -75.0), LatLng(40.001, -75.001)];
      final out = RidePathSmoother.displayTrack(two);
      expect(out, hasLength(2));
      expect(out[0], two[0]);
      expect(out[1], two[1]);

      expect(RidePathSmoother.displayTrack(const []), isEmpty);
    });

    test('preserves point count and anchors both endpoints', () {
      final route = [
        for (var i = 0; i < 100; i++)
          LatLng(40.0 + i * 0.0001, -75.0 + i * 0.0002),
      ];
      final out = RidePathSmoother.displayTrack(route);
      expect(out, hasLength(route.length));
      expect(out.first.latitude, route.first.latitude);
      expect(out.first.longitude, route.first.longitude);
      expect(out.last.latitude, route.last.latitude);
      expect(out.last.longitude, route.last.longitude);
    });

    test('reduces cross-track jitter on a straight noisy ride', () {
      // A rider heading due north; GPS shake alternates +/-5 m in longitude.
      // 5 m longitude at this latitude ~= 0.0000595 deg.
      const jitterDeg = 0.00006;
      final noisy = [
        for (var i = 0; i < 200; i++)
          LatLng(
            40.0 + i * 0.0001,
            -75.0 + (i.isEven ? jitterDeg : -jitterDeg),
          ),
      ];
      final smooth = RidePathSmoother.displayTrack(noisy);

      double maxDev(List<LatLng> track) =>
          track.map((p) => (p.longitude - -75.0).abs()).reduce(max);

      // Interior points (skip the anchored endpoints) get measurably tighter.
      double interiorMaxDev(List<LatLng> track) => track
          .skip(3)
          .take(track.length - 6)
          .map((p) => (p.longitude - -75.0).abs())
          .reduce(max);
      expect(interiorMaxDev(smooth), lessThan(maxDev(noisy) * 0.6));
    });

    test('smooths without freezing at a genuine turn', () {
      // An L-shaped ride: east then north. The corner must remain BETWEEN
      // the two legs, not rounded into a diagonal shortcut.
      final route = [
        for (var i = 0; i < 50; i++) LatLng(40.0, -75.0 + i * 0.0001),
        for (var i = 1; i <= 50; i++) LatLng(40.0 + i * 0.0001, -75.005),
      ];
      final out = RidePathSmoother.displayTrack(route);
      // The midpoint of the track is still near the corner.
      final mid = out[out.length ~/ 2];
      expect(mid.latitude, lessThan(40.0 + 0.0005));
      expect(mid.longitude, greaterThan(-75.005 - 0.0005));
      // And the line still reaches both legs' ends.
      expect(out.last.latitude, closeTo(40.0050, 0.0005));
      expect(out.last.longitude, closeTo(-75.005, 0.0005));
    });
  });
}
