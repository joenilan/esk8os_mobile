import 'package:esk8os_mobile/services/ride_position_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 29, 12);

  RidePositionSample sample({
    double lat = 40,
    double lng = -75,
    double accuracy = 5,
    double speed = 5,
    double speedAccuracy = 1,
    Duration offset = Duration.zero,
  }) => RidePositionSample(
    latitude: lat,
    longitude: lng,
    accuracyM: accuracy,
    speedMps: speed,
    speedAccuracyMps: speedAccuracy,
    observedAt: now.add(offset),
  );

  test('cached seed must be recent and reasonably accurate', () {
    expect(RidePositionFilter.usableSeed(sample(), now: now), isTrue);
    expect(
      RidePositionFilter.usableSeed(
        sample(offset: const Duration(minutes: -3)),
        now: now,
      ),
      isFalse,
    );
    expect(
      RidePositionFilter.usableSeed(sample(accuracy: 80), now: now),
      isFalse,
    );
  });

  test('rejects inaccurate and stale stream fixes', () {
    final filter = RidePositionFilter();

    expect(
      filter.assess(sample(accuracy: 30), now: now).rejection,
      RidePositionRejection.inaccurate,
    );
    expect(
      filter
          .assess(sample(offset: const Duration(seconds: -20)), now: now)
          .rejection,
      RidePositionRejection.stale,
    );
  });

  test('rejects a gross teleport without poisoning the next fix', () {
    final filter = RidePositionFilter();
    expect(filter.assess(sample(), now: now).accepted, isTrue);

    final teleport = filter.assess(
      sample(lat: 40.01, offset: const Duration(seconds: 1), speed: 0),
      now: now.add(const Duration(seconds: 1)),
    );
    expect(teleport.rejection, RidePositionRejection.implausibleJump);

    final recovery = filter.assess(
      sample(lat: 40.00005, offset: const Duration(seconds: 2)),
      now: now.add(const Duration(seconds: 2)),
    );
    expect(recovery.accepted, isTrue);
  });

  test('rejects a short stationary spike before it affects distance', () {
    final filter = RidePositionFilter();
    expect(filter.assess(sample(speed: 0), now: now).accepted, isTrue);

    final spike = filter.assess(
      sample(lat: 40.0004, speed: 0, offset: const Duration(seconds: 1)),
      now: now.add(const Duration(seconds: 1)),
    );
    expect(spike.rejection, RidePositionRejection.implausibleJump);
  });

  test(
    'accepts normal fast movement and marks a long gap as a new segment',
    () {
      final filter = RidePositionFilter();
      expect(filter.assess(sample(), now: now).startsNewSegment, isTrue);

      final moving = filter.assess(
        sample(lat: 40.0002, speed: 22, offset: const Duration(seconds: 1)),
        now: now.add(const Duration(seconds: 1)),
      );
      expect(moving.accepted, isTrue);
      expect(moving.startsNewSegment, isFalse);

      final afterGap = filter.assess(
        sample(lat: 40.001, offset: const Duration(seconds: 20)),
        now: now.add(const Duration(seconds: 20)),
      );
      expect(afterGap.accepted, isTrue);
      expect(afterGap.startsNewSegment, isTrue);
    },
  );
}
