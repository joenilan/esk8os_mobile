import 'package:latlong2/latlong.dart';

/// Index-preserving display smoothing for recorded GPS tracks.
///
/// Raw 1 Hz fixes zigzag around the true path (±3-5 m is normal consumer
/// GPS), which is why playback lines look shaky. This applies a two-pass
/// (forward + backward) exponential filter per axis:
///  * zero-phase — the smoothed line does not LAG behind the rider,
///  * strictly 1:1 with the input — every output point keeps its input's
///    index, so playback slicing, keyframes and trail geometry stay
///    index-consistent,
///  * endpoints anchored — start and finish do not drift.
///
/// DISPLAY ONLY: callers pass in-memory geometry; the database keeps the raw
/// recorded fixes untouched (roadmap guardrail — raw ride evidence is never
/// rewritten by a derived layer).
class RidePathSmoother {
  RidePathSmoother._();

  /// [alpha] in (0, 1]: smaller = smoother. 0.35 keeps genuine corners
  /// (switchbacks, turns) readable while erasing per-fix shake.
  static List<LatLng> displayTrack(List<LatLng> route, {double alpha = 0.35}) {
    if (route.length < 3) return List.of(route);
    final lats = _ema(route.map((p) => p.latitude), alpha);
    final lngs = _ema(route.map((p) => p.longitude), alpha);
    // Backward pass over the forward result = zero-phase smoothing.
    final latsB = _ema(lats.reversed, alpha).reversed.toList();
    final lngsB = _ema(lngs.reversed, alpha).reversed.toList();
    final out = [
      for (var i = 0; i < route.length; i++) LatLng(latsB[i], lngsB[i]),
    ];
    // The double pass blurs the endpoints slightly; the true start/finish are
    // where the rider actually was, so anchor them exactly.
    out[0] = route.first;
    out[out.length - 1] = route.last;
    return out;
  }

  static List<double> _ema(Iterable<double> values, double alpha) {
    final out = List<double>.filled(values.length, 0);
    double? acc;
    var i = 0;
    for (final v in values) {
      acc = acc == null ? v : alpha * v + (1 - alpha) * acc;
      out[i++] = acc;
    }
    return out;
  }
}
