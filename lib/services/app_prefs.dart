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
}
