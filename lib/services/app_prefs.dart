import 'package:shared_preferences/shared_preferences.dart';

/// App-local UI preferences that must survive page swipes AND app restarts
/// (board config lives on the board; this is for phone-side toggles like the
/// map style and heading-up mode). Call [init] once in main() before runApp.
class AppPrefs {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static bool get mapHeadingUp => _p.getBool('mapHeadingUp') ?? false;
  static set mapHeadingUp(bool v) => _p.setBool('mapHeadingUp', v);

  static bool get mapLight => _p.getBool('mapLight') ?? false;
  static set mapLight(bool v) => _p.setBool('mapLight', v);

  /// Auto start/stop a trip from movement.
  static bool get autoTrip => _p.getBool('autoTrip') ?? false;
  static set autoTrip(bool v) => _p.setBool('autoTrip', v);

  /// After a valid recorded trip, update the board Wh/mi model from recent trips.
  static bool get autoLearnRange => _p.getBool('autoLearnRange') ?? true;
  static set autoLearnRange(bool v) => _p.setBool('autoLearnRange', v);

  /// Over-speed alert threshold in the board's display unit (0 = off).
  static double get speedAlert => _p.getDouble('speedAlert') ?? 0;
  static set speedAlert(double v) => _p.setDouble('speedAlert', v);

  /// Floating window over other apps when a recording trip is backgrounded.
  static bool get overlayEnabled => _p.getBool('overlayEnabled') ?? false;
  static set overlayEnabled(bool v) => _p.setBool('overlayEnabled', v);
}
