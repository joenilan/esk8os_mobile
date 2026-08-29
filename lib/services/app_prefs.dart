import 'package:shared_preferences/shared_preferences.dart';

/// App-local UI preferences that must survive page swipes AND app restarts
/// (board config lives on the board; this is for phone-side toggles like the
/// map style and heading-up mode). Call [init] once in main() before runApp.
class AppPrefs {
  static late SharedPreferences _p;
  static const _rideTrackingDefaultsVersionKey = 'rideTrackingDefaultsVersion';
  static const _rideTrackingDefaultsVersion = 1;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    // Product migration: this is a ride tracker, so existing installs should
    // receive the safer defaults once. The version marker means a rider can
    // deliberately turn either option back off without the next launch
    // silently re-enabling it.
    if ((_p.getInt(_rideTrackingDefaultsVersionKey) ?? 0) <
        _rideTrackingDefaultsVersion) {
      await _p.setBool('autoTrip', true);
      await _p.setBool('overlayEnabled', true);
      await _p.setInt(
        _rideTrackingDefaultsVersionKey,
        _rideTrackingDefaultsVersion,
      );
    }
  }

  static bool get mapHeadingUp => _p.getBool('mapHeadingUp') ?? false;
  static set mapHeadingUp(bool v) => _p.setBool('mapHeadingUp', v);

  static bool get mapLight =>
      _p.getBool('mapLight') ??
      true; // light basemap by default — feels more natural
  static set mapLight(bool v) => _p.setBool('mapLight', v);

  /// Experimental: render playback maps with the MapLibre + OpenFreeMap vector
  /// stack instead of raster tiles (roadmap step-5 prototype). Phone-only
  /// preference; the live ride map keeps the proven raster path until the
  /// prototype is ride-validated.
  static bool get vectorBasemap => _p.getBool('vectorBasemap') ?? false;
  static set vectorBasemap(bool v) => _p.setBool('vectorBasemap', v);

  /// Last display unit reported by a real board/settings frame. This is only a
  /// phone-side presentation cache so disconnected ride history uses the
  /// rider's familiar units; it never changes the board's unit setting.
  static bool get preferredMph => _p.getBool('preferredMph') ?? true;
  static set preferredMph(bool v) => _p.setBool('preferredMph', v);

  /// Auto start/stop a trip from movement.
  static bool get autoTrip => _p.getBool('autoTrip') ?? true;
  static set autoTrip(bool v) => _p.setBool('autoTrip', v);

  /// After a valid recorded trip, update the board Wh/mi model from recent trips.
  static bool get autoLearnRange => _p.getBool('autoLearnRange') ?? true;
  static set autoLearnRange(bool v) => _p.setBool('autoLearnRange', v);

  /// Over-speed alert threshold in the board's display unit (0 = off).
  static double get speedAlert => _p.getDouble('speedAlert') ?? 0;
  static set speedAlert(double v) => _p.setDouble('speedAlert', v);

  /// Floating window over other apps when a recording trip is backgrounded.
  static bool get overlayEnabled => _p.getBool('overlayEnabled') ?? true;
  static set overlayEnabled(bool v) => _p.setBool('overlayEnabled', v);

  /// Phone app theme follows the ESP32 board theme by default.
  static bool get themeSyncWithBoard =>
      _p.getBool('themeSyncWithBoard') ?? true;
  static set themeSyncWithBoard(bool v) => _p.setBool('themeSyncWithBoard', v);

  /// Local phone-only theme used when [themeSyncWithBoard] is off. Also caches
  /// the last applied board theme so the scan screen opens with a familiar look.
  static String get phoneTheme => _p.getString('phoneTheme') ?? 'CAM';
  static set phoneTheme(String v) => _p.setString('phoneTheme', v);
}
