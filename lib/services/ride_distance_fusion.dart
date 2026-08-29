enum RideDistanceSource { none, board, gps }

/// Monotonic trip distance selected from board wheel odometry and phone GPS.
///
/// The board becomes authoritative only after its trip counter proves that it
/// advances. GPS therefore keeps a recording useful when firmware reports a
/// live but stuck/reset trip counter. Source changes are offset-aligned so the
/// rider never sees distance jump backwards.
class RideDistanceFusion {
  static const double _progressKm = 0.003;
  static const double _regressionKm = 0.01;
  static const double _stalledGpsGainKm = 0.15;
  static const int _stalledMs = 30000;

  double _effectiveKm = 0;
  double? _lastBoardKm;
  double _gpsAtBoardProgressKm = 0;
  int _lastBoardProgressMs = 0;
  bool _boardQualified = false;
  double _boardOffsetKm = 0;
  double _gpsOffsetKm = 0;
  RideDistanceSource _source = RideDistanceSource.none;
  int _switchCount = 0;
  bool _dropoutActive = false;

  double get distanceKm => _effectiveKm;
  RideDistanceSource get source => _source;

  /// Mid-ride source transitions, persisted as evidence: the number of times
  /// the ride left an established board source for GPS (a dropout — BLE lost,
  /// board off, or a stalled counter) plus each return. The normal startup
  /// path (GPS first fixes, then the board qualifying) never counts, so zero
  /// means the summary distance came from one sensor the whole ride.
  int get switchCount => _switchCount;

  void reset() {
    _effectiveKm = 0;
    _lastBoardKm = null;
    _gpsAtBoardProgressKm = 0;
    _lastBoardProgressMs = 0;
    _boardQualified = false;
    _boardOffsetKm = 0;
    _gpsOffsetKm = 0;
    _source = RideDistanceSource.none;
    _switchCount = 0;
    _dropoutActive = false;
  }

  double update({
    required double gpsKm,
    required bool gpsLive,
    required double boardKm,
    required bool boardLive,
    required int nowMs,
  }) {
    gpsKm = gpsKm.isFinite ? gpsKm.clamp(0, double.infinity) : 0;
    boardKm = boardKm.isFinite ? boardKm.clamp(0, double.infinity) : 0;

    // The board block below advances _lastBoardKm; the reconnect policy needs
    // the counter as it was BEFORE this update to detect gap advancement.
    final lastBoardKmBeforeUpdate = _lastBoardKm;

    if (boardLive) {
      final previous = _lastBoardKm;
      if (previous == null) {
        _lastBoardKm = boardKm;
        _gpsAtBoardProgressKm = gpsKm;
        _lastBoardProgressMs = nowMs;
      } else if (boardKm < previous - _regressionKm) {
        // A board-side reset must not reset the phone recording.
        _boardQualified = false;
        _lastBoardKm = boardKm;
        _gpsAtBoardProgressKm = gpsKm;
        _lastBoardProgressMs = nowMs;
      } else if (boardKm > previous + _progressKm) {
        _boardQualified = true;
        _lastBoardKm = boardKm;
        _gpsAtBoardProgressKm = gpsKm;
        _lastBoardProgressMs = nowMs;
      }

      final stalled =
          _boardQualified &&
          gpsLive &&
          gpsKm - _gpsAtBoardProgressKm >= _stalledGpsGainKm &&
          nowMs - _lastBoardProgressMs >= _stalledMs;
      if (stalled) _boardQualified = false;
    }

    final desired = boardLive && _boardQualified
        ? RideDistanceSource.board
        : gpsLive
        ? RideDistanceSource.gps
        : RideDistanceSource.none;

    if (desired != _source) {
      if (desired == RideDistanceSource.board) {
        // Reconnect policy: if the board's counter advanced through the
        // dropout (BLE lost but the VESC kept riding), it is the authoritative
        // whole-ride total — drop the GPS-coverage offset so no distance is
        // lost or double-counted. If it did not advance (powered off), keep
        // the offset so the GPS-covered tail survives.
        if (_dropoutActive &&
            lastBoardKmBeforeUpdate != null &&
            boardKm > lastBoardKmBeforeUpdate + _progressKm) {
          _boardOffsetKm = 0.0;
        } else {
          _boardOffsetKm = _effectiveKm - boardKm;
        }
      } else if (desired == RideDistanceSource.gps) {
        _gpsOffsetKm = _effectiveKm - gpsKm;
      }
      final previousSource = _source;
      _source = desired;
      // Evidence counting (see [switchCount]): leaving an established board
      // source is a dropout; a return only counts once a dropout is open.
      if (previousSource == RideDistanceSource.board &&
          desired == RideDistanceSource.gps) {
        _dropoutActive = true;
        _switchCount++;
      } else if (_dropoutActive &&
          previousSource == RideDistanceSource.gps &&
          desired == RideDistanceSource.board) {
        _dropoutActive = false;
        _switchCount++;
      }
    }

    final candidate = switch (_source) {
      RideDistanceSource.board => boardKm + _boardOffsetKm,
      RideDistanceSource.gps => gpsKm + _gpsOffsetKm,
      RideDistanceSource.none => _effectiveKm,
    };
    if (candidate.isFinite && candidate > _effectiveKm) {
      _effectiveKm = candidate;
    }
    return _effectiveKm;
  }
}
