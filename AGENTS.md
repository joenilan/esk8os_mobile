# ESK8OS Mobile - Agent Instructions

This repo contains the Flutter Android companion app for ESK8OS. Treat user ride history as production data.

## Critical Install Rule

Never use these commands on the user's phone or emulator:

- `flutter install`
- `flutter run`
- `adb uninstall`
- `adb shell pm uninstall`

Reason: `flutter install` can uninstall the existing app before installing. Uninstalling `com.joenilan.esk8os_mobile` deletes app-private data, including recorded trips.

Trip history is stored in the app documents directory as `trips.db` through `path_provider` / `sqflite`. Android deletes that directory on uninstall.

## Required Safe Install Flow

Use the safe installer script:

```powershell
.\scripts\install-signed-release.ps1 -Devices RFGL42MHF7Z,emulator-5554 -Launch
```

What the script does:

1. Verifies `android/key.properties` exists.
2. Verifies the configured release keystore exists.
3. Runs `flutter build apk --release`.
4. Installs the exact built APK with `adb install -r`.
5. Stops if the install fails. Do not recover by uninstalling.

Manual equivalent:

```powershell
flutter build apk --release
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s RFGL42MHF7Z install -r build\app\outputs\flutter-apk\app-release.apk
```

If Android reports a signature mismatch or install failure, stop and ask the user. Do not uninstall the app to force the update.

## Release Signing

Release builds are expected to use:

- `android/key.properties`
- `android/app/esk8-release.jks`
- `keyAlias=esk8`

If those files are missing or invalid, do not install to a device that may contain user trips.

