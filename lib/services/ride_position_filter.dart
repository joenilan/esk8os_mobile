import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Why a GPS fix was rejected before it could affect a recorded ride.
enum RidePositionRejection { none, invalid, inaccurate, stale, implausibleJump }

/// Plugin-independent position evidence used by [RidePositionFilter].
///
/// Keeping this model free of `geolocator` makes the safety policy deterministic
/// and unit-testable without Android location channels.
class RidePositionSample {
  final double latitude;
  final double longitude;
  final double accuracyM;
  final double speedMps;
  final double speedAccuracyMps;
  final DateTime observedAt;

  const RidePositionSample({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.speedMps,
    required this.speedAccuracyMps,
    required this.observedAt,
  });

  LatLng get point => LatLng(latitude, longitude);
}

class RidePositionAssessment {
  final bool accepted;
  final bool startsNewSegment;
  final RidePositionRejection rejection;

  const RidePositionAssessment._({
    required this.accepted,
    required this.startsNewSegment,
    required this.rejection,
  });

  const RidePositionAssessment.accepted({required bool startsNewSegment})
    : this._(
        accepted: true,
        startsNewSegment: startsNewSegment,
        rejection: RidePositionRejection.none,
      );

  const RidePositionAssessment.rejected(RidePositionRejection rejection)
    : this._(accepted: false, startsNewSegment: false, rejection: rejection);
}

/// Rejects stale/inaccurate fixes and gross GPS teleports while preserving
/// legitimate fast movement and post-coverage recovery.
class RidePositionFilter {
  static const double streamMaxAccuracyM = 20;
  static const double seedMaxAccuracyM = 50;
  static const Duration seedMaxAge = Duration(minutes: 2);
  static const Duration streamMaxAge = Duration(seconds: 15);
  static const Duration continuousGap = Duration(seconds: 10);

  RidePositionSample? _lastAccepted;
  RidePositionRejection _lastRejection = RidePositionRejection.none;

  RidePositionRejection get lastRejection => _lastRejection;

  void reset() {
    _lastAccepted = null;
    _lastRejection = RidePositionRejection.none;
  }

  static bool usableSeed(RidePositionSample sample, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    if (!_finiteSample(sample)) return false;
    if (sample.accuracyM < 0 || sample.accuracyM > seedMaxAccuracyM) {
      return false;
    }
    final age = reference.difference(sample.observedAt);
    return age >= const Duration(seconds: -5) && age <= seedMaxAge;
  }

  RidePositionAssessment assess(RidePositionSample sample, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    if (!_finiteSample(sample)) {
      return _reject(RidePositionRejection.invalid);
    }
    if (sample.accuracyM < 0 || sample.accuracyM > streamMaxAccuracyM) {
      return _reject(RidePositionRejection.inaccurate);
    }

    final age = reference.difference(sample.observedAt);
    if (age < const Duration(seconds: -5) || age > streamMaxAge) {
      return _reject(RidePositionRejection.stale);
    }

    final previous = _lastAccepted;
    var startsNewSegment = previous == null;
    if (previous != null) {
      final elapsed = sample.observedAt.difference(previous.observedAt);
      if (elapsed > continuousGap) startsNewSegment = true;

      final distanceM = const Distance().as(
        LengthUnit.Meter,
        previous.point,
        sample.point,
      );
      final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
      if (elapsedSeconds <= 0) {
        final accuracyAllowance = previous.accuracyM + sample.accuracyM + 10;
        if (distanceM > accuracyAllowance) {
          return _reject(RidePositionRejection.implausibleJump);
        }
      } else {
        // Use reported speed when it is trustworthy, with generous error and
        // distance floors. The independent implied-speed gate prevents a low
        // reported speed from rejecting a legitimate fast PEV fix.
        final reportedMps = math.max(
          0,
          math.max(previous.speedMps, sample.speedMps) +
              math.max(previous.speedAccuracyMps, sample.speedAccuracyMps),
        );
        final dynamicMps = math.max(15.0, reportedMps + 8.0);
        final allowedDistanceM = math.max(
          25.0,
          dynamicMps * elapsedSeconds + previous.accuracyM + sample.accuracyM,
        );
        final impliedMps = distanceM / elapsedSeconds;
        if (distanceM > allowedDistanceM && impliedMps > 30.0) {
          return _reject(RidePositionRejection.implausibleJump);
        }
      }
    }

    _lastAccepted = sample;
    _lastRejection = RidePositionRejection.none;
    return RidePositionAssessment.accepted(startsNewSegment: startsNewSegment);
  }

  RidePositionAssessment _reject(RidePositionRejection reason) {
    _lastRejection = reason;
    return RidePositionAssessment.rejected(reason);
  }

  static bool _finiteSample(RidePositionSample sample) =>
      sample.latitude.isFinite &&
      sample.longitude.isFinite &&
      sample.latitude >= -90 &&
      sample.latitude <= 90 &&
      sample.longitude >= -180 &&
      sample.longitude <= 180 &&
      sample.accuracyM.isFinite &&
      sample.speedMps.isFinite &&
      sample.speedAccuracyMps.isFinite;
}
