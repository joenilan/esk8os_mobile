import 'package:esk8os_mobile/services/app_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ride tracking defaults are enabled on first migrated launch', () async {
    SharedPreferences.setMockInitialValues({
      'autoTrip': false,
      'overlayEnabled': false,
    });

    await AppPrefs.init();

    expect(AppPrefs.autoTrip, isTrue);
    expect(AppPrefs.overlayEnabled, isTrue);
  });

  test('a rider choice survives after the one-time migration', () async {
    SharedPreferences.setMockInitialValues({});
    await AppPrefs.init();
    AppPrefs.autoTrip = false;
    AppPrefs.overlayEnabled = false;

    await AppPrefs.init();

    expect(AppPrefs.autoTrip, isFalse);
    expect(AppPrefs.overlayEnabled, isFalse);
  });

  test('last board unit is cached for disconnected ride history', () async {
    SharedPreferences.setMockInitialValues({});
    await AppPrefs.init();

    expect(AppPrefs.preferredMph, isTrue);
    AppPrefs.preferredMph = false;
    await Future<void>.delayed(Duration.zero);

    expect(AppPrefs.preferredMph, isFalse);
  });
}
