# ESK8OS Mobile - Agent Instructions

This repository is the Flutter companion app for the ESK8OS longboard display.
Android is the primary target. Treat the connected board, the rider's phone, and
recorded trip history as production systems and data.

## Repository Boundaries

- Work from `E:\AI\esk8os_mobile`, which has its own `.git` repository.
- The firmware lives in the separate repository `E:\AI\Longboard-Display`.
- Run all app `git` commands from `E:\AI\esk8os_mobile`. Never stage, commit, or
  push this app from the parent `E:\AI` repository.
- Do not modify firmware merely to make an app-side assumption work. When the
  BLE contract must change, update both repositories deliberately and keep
  `E:\AI\Longboard-Display\docs\companion_api_spec.md` in sync.
- Preserve unrelated or uncommitted user changes in either repository.

## Product Architecture

The phone normally talks to the ESP32-S3 display over the custom ESK8OS BLE
service. The ESP32 talks to the VESC/FSESC over UART. The app does not own the
VESC configuration and must not invent a second copy of it.

Important app files:

- `lib/ble/esk8os_ble.dart` - BLE UUIDs, commands, and data models
- `lib/ble/companion_device.dart` - real BLE transport
- `lib/ble/mock_device.dart` - mock transport; keep it contract-compatible
- `lib/pages/settings_page.dart` - device and app-local settings
- `lib/services/app_prefs.dart` - phone-only preferences
- `lib/services/trip_recorder.dart` - trip recording and source selection
- `lib/database/trip_database.dart` - persistent ride history
- `lib/overlay/trip_overlay.dart` - Android floating ride window
- `lib/main.dart` - lifecycle, connection, and dashboard integration

BLE characteristics:

- `0001` telemetry notify
- `0002` board settings read/write
- `0003` command write
- `0004` session/trip stats notify
- `0005` read-only VESC base config plus per-field provenance
- `0006` optional Daly BMS data

Request a large MTU on connection. Telemetry is JSON and can exceed the default
20-byte BLE payload.

## Source-of-Truth Policy

The VESC is authoritative for every value its configuration actually supplies.
The app must not present a normal editable setting that silently shadows a valid
VESC value.

Characteristic `0005` is the authority for this decision:

- `BaseConfig.valid == true` means a firmware-matched VESC config was parsed.
- `src[field] == "v"` means the effective value comes from the VESC.
- `src[field] == "r"` means a persisted rider override is currently shadowing
  the VESC.
- `src[field] == "d"` means the firmware is using a generic fallback.

Apply these UI rules:

1. When a value comes from the VESC, show it read-only with a clear `VESC`
   source label. Do not show a slider, picker, or ordinary edit action.
2. For a stale rider override on a VESC-supplied field, show the effective value
   and the VESC value, and offer a deliberate **Use VESC / clear override**
   action. Do not encourage editing the override.
3. When no valid VESC base value exists, a compatibility fallback may remain
   editable if the board genuinely needs it to operate. Label it as a fallback,
   not as VESC configuration.
4. Do not infer authority from a value merely looking plausible. Use
   `BaseConfig.valid` and its provenance map.
5. Actual motor/app configuration changes belong in official VESC Tool, reached
   through bridge mode when appropriate. The companion app is not a replacement
   VESC configuration editor.

The firmware exposes this as `UNSET:<key>` on command characteristic `0003`,
backed by `Settings::removeOverride()`. The app builds it with
`Esk8Commands.unset(key)`. Do not fake "Use VESC" by writing the current VESC
number as another rider override.

Fields that should normally be VESC-authoritative:

- battery series count
- pack capacity
- motor poles
- motor-to-wheel gear ratio
- VESC battery cut-start and cut-end thresholds, from which the firmware derives
  ride-home and limp per-cell floors
- VESC current limits

The settings screen may summarize those values, but it should not duplicate
them as editable controls when their source is VESC.

### Deliberate exceptions

- **Wheel diameter calibration is editable.** Real loaded tire diameter, wear,
  and pneumatic compression make this analogous to an e-bike computer
  calibration. Keep the nominal VESC/preset value visible, allow a small
  rider-tuned override, and provide Reset/Use VESC.
- Phone-only behavior remains editable: auto record, floating window, map style,
  heading-up mode, over-speed alert, and phone theme.
- Display-specific behavior that the VESC does not own may remain editable:
  display brightness, board UI/HUD choices, device identity, and demo mode.
- On-board learned range data is read-only. The board learns Wh/distance,
  deliverable pack energy, typical current, and pack resistance. Do not add a
  competing phone-side override when `hasBoardCal` is true.

Do not confuse ratio conventions. The BLE `BaseConfig.gearRatio` is the
motor-to-wheel pulley ratio, for example `72 / 16 = 4.50`. An inverse UI value
near `0.22` is the same physical ratio expressed backwards; do not let an
inverse preset such as `0.20` override a valid VESC value.

## Current Build Facts and Settings Decision

The current physical build is known to use:

- 10S battery
- 32.0 Ah pack capacity
- 203 mm wheel
- 14 motor poles
- 4.50 motor-to-wheel gear ratio for a 72/16 drive
- approximately 45 mOhm learned pack resistance
- demo mode off

These are verification facts, not values to hard-code into generic app models.
Prefer live board/VESC data and keep mock fixtures explicit.

Current product decision:

- Auto record should be ON for the rider's phone.
- Floating window should be ON when the rider wants background stats and has
  granted Android overlay permission.
- Ride-home and limp values should follow VESC cutoffs. With 32.0 V to 30.0 V
  cutoffs on a 10S pack, the derived values should be 3.20 V/cell and
  3.00 V/cell. Do not manually shadow them in the app.
- A range model that says "not learned yet" is expected until a qualifying ride
  (roughly 10% or more of the pack) has been recorded.
- Over-speed alerts and theme are rider preferences.

`AppPrefs.init()` applies the auto-record/floating-window decision as a
versioned one-time migration. After that migration, a rider who deliberately
turns either option off must stay opted out.

When cleaning the settings screen, favor a compact read-only **VESC / drivetrain
summary** plus a small set of genuine controls. Do not remove diagnostics or
provenance that help explain where a value came from.

## Setup Profile Policy

The fixed firmware `Profile 0` / `Profile 1` selector is not the desired mobile
product. Replace fixed slots with CRUD for named setup profiles.

- Profiles contain only physical setup values the VESC does not own.
- Wheel-diameter calibration is the first definite profile field.
- Never store or restore VESC-authoritative battery, cutoff, motor, gearing, or
  current-limit values in a profile.
- Do not bundle unrelated phone preferences into a physical setup profile
  without an explicit product decision.
- Prefer an app-local, per-board named profile library whose selected values are
  applied to the board's supported overrides. The applied value remains in board
  NVS so the board works without the phone.
- Remove the hard-coded Profile 0/1 picker rather than expanding it to more
  fixed slots.

See `HANDOFF.md` for the current implementation starting point and acceptance
criteria.

## Telemetry and Trip Authority

- The board must work without the phone, so board wheel distance and board
  moving time are canonical while live telemetry is available.
- The phone records GPS route, elevation, and GPS-derived extras.
- While the board is live, do not replace its speed/distance with GPS just
  because both exist.
- If the BLE/VESC source drops, the recorder may use its documented GPS fallback
  and must label the source accurately.
- Never run dashboard VESC polling and raw VESC Tool bridge forwarding at the
  same time. Bridge mode owns the UART.

## VESC Tool Bridge Safety

- Enter bridge mode only while the vehicle is stopped.
- The board AP is `ESK8-BRIDGE`, password `esk8bridge`.
- Desktop endpoint: `192.168.4.1:65102`.
- WiFi TCP bridge support does not imply compatibility with every mobile VESC
  Tool build.

## Ride Data Safety

Trip history is production data. It is stored as `trips.db` in the app documents
directory through `path_provider` and `sqflite`. Android deletes app-private data
when the package is uninstalled.

Never run these against the user's phone or a data-bearing emulator:

- `flutter install`
- `flutter run`
- `adb uninstall`
- `adb shell pm uninstall`

Do not clear app data. Do not recover from a signature mismatch by uninstalling.
If an install cannot proceed in place, stop and report the exact error.

## Safe Build and Install

Analyze and test before producing a release:

```powershell
C:\dev\flutter\bin\flutter.bat analyze
C:\dev\flutter\bin\flutter.bat test
```

Compile and cryptographically verify the signed release without changing any
device:

```powershell
.\scripts\install-signed-release.ps1 -BuildOnly
```

If the phone is connected, this also compares the installed app's certificate
to the new APK while remaining read-only:

```powershell
.\scripts\install-signed-release.ps1 -BuildOnly -Devices RFGL42MHF7Z
```

Only when the user asks to update the phone, use the in-place installer:

```powershell
.\scripts\install-signed-release.ps1 -Devices RFGL42MHF7Z -Launch
```

The script requires the permanent keystore, verifies the release APK with
Android `apksigner`, compares its certificate to an existing installation, and
only then uses `adb install -r`. Both Android `debug` and `release` build types
use this same permanent key when `android/key.properties` is present.

The manual in-place equivalent is:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" `
  -s RFGL42MHF7Z install -r `
  build\app\outputs\flutter-apk\app-release.apk
```

Release signing depends on these gitignored files:

- `android/key.properties`
- `android/app/esk8-release.jks`
- `keyAlias=esk8`

Never commit signing secrets. If signing files are missing or invalid, do not
install to a device that may contain recorded trips.

## Verification Expectations

For normal Dart/UI changes, run `flutter analyze` and the relevant tests. For BLE
model changes, add or update parsing and serialization tests, and keep
`MockEsk8Device` aligned with the real contract.

For settings-authority cleanup, explicitly verify:

- VESC-sourced values are read-only.
- Existing rider overrides can be identified and safely cleared.
- Clearing an override reveals the VESC value rather than a stale UI cache.
- Wheel calibration still changes effective speed/distance and can be reset.
- A missing/older `0005` characteristic degrades safely.
- Demo mode and mock-device flows still work without pretending their data is
  live VESC data.
- Auto record and floating-window preferences survive app restart.

Only install on a physical device when device verification is part of the user
request. An APK build alone does not authorize changing the user's phone.
