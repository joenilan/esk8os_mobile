# EVEE Companion

Flutter companion app for the **EVEE** electric-vehicle ecosystem. ESK8OS on a
LilyGo T-Display-S3 / ESP32-S3 is the first supported vehicle integration; the
disconnected app stays vehicle-neutral and connected products identify their
vehicle type over BLE.

Cross-platform (one codebase). **Android first; iOS later.**

## Firmware contract

The app talks to the firmware's custom companion BLE service. The contract is mirrored in `lib/ble/esk8os_ble.dart` and specified in `docs/companion_api_spec.md` in the firmware repo ([Esk8OS](https://github.com/joenilan/Esk8OS)).

- **Service** `5043697a-0000-4682-93cb-33bb0a149f7e`
  - **Telemetry** `…0001` (NOTIFY) — 5 Hz core ride data, including independent
    drivetrain (`live`) and battery (`blive` / `bsrc`) availability
  - **Settings** `…0002` (READ/WRITE) — board config (partial writes OK)
  - **Command** `…0003` (WRITE) — ASCII actions (`TRIP_RESET`, `PAGE_NEXT/PREV`, `BRIDGE_MODE`, `WIFI_EXPORT_START/STOP`, `REBOOT`)
  - **Session** `…0004` (NOTIFY) — 1 Hz trip/session statistics
  - **BaseConfig** `…0005` (READ) — VESC config and per-field provenance
  - **BMS** `…0006` (NOTIFY, optional) — 1 Hz Daly pack/per-cell data with
    response-group freshness and classified alarm evidence
- Scan **actively** and filter by the service UUID. Request a large **MTU (512)** on connect — telemetry is one JSON notify and truncates at the 20-byte default.
- Treat a valid `BaseConfig` as authoritative for VESC-owned values. Wheel
  diameter remains an explicit rider calibration exception.
- When `0006` is present, the live BMS page subscribes to it and trip recording
  stores fresh snapshots with the 1 Hz route log for playback and JSON backup.
- With the VESC off and Daly still reachable, battery fields remain available
  while speed, power, current, duty, drivetrain temperature, and VESC faults
  are displayed as unavailable rather than misleading zeroes.

## Status

Android-first companion with BLE telemetry, source-aware settings, phone-GPS
or vehicle-assisted trip recording, BMS diagnostics and playback, floating
ride view, WiFi export, private rider-built Trails/POIs, complete library
backup, and signed in-place release updates. BLE validation requires a physical Android phone;
ordinary development and release builds must not replace or clear its
production trip database.

The Ride/Trail Library remains available while the board is disconnected.
Recorded Rides remain immutable evidence; curated Trails own a separate,
editable segmented geometry copy and export as segmented GPX or GeoJSON with
POIs (stored internally as standard map/GPX waypoints). The product-wide
mapping, recorder, trail-building, performance, and
UI program is tracked in `PRODUCT_ROADMAP.md`.

## Project layout

- `lib/ble/esk8os_ble.dart` — pure-Dart contract: UUIDs, command strings, `Telemetry`, `BmsData`, `BaseConfig`, and `BoardSettings`
- `lib/ble/companion_device.dart` — flutter_blue_plus wrapper: scan, connect (MTU), telemetry stream, settings read/write, command send
- `lib/services/trip_recorder.dart` — phone-GPS or vehicle-assisted trip capture, including optional BMS snapshots
- `lib/models/trail.dart` — typed Trail, TrailPoint, and POI/Waypoint ownership models
- `lib/database/trip_database.dart` — ride evidence plus independent Trail/POI persistence
- `lib/main.dart` — scan page + dashboard integration

## Develop

Requires Flutter (stable), Android SDK (via Android Studio), JDK 17, Windows Developer Mode (for plugin symlinks), and a **physical Android device** with USB debugging.

```bash
flutter pub get
flutter analyze
flutter test
```

Do not use `flutter run` or `flutter install` on a phone containing trip data;
those flows can replace the installed package in a way that loses app-private
data. Build/verify the permanently signed APK with
`.\scripts\install-signed-release.ps1 -BuildOnly`, and use the same script with
an explicit `-Devices` value for a signature-checked `adb install -r` update.

BLE notes:
- `flutter_blue_plus` 2.x requires a license at `connect()` — this app uses `License.nonprofit` (free/personal tier). Change to commercial if the app is ever sold.
- Android 12+ runtime permissions (`BLUETOOTH_SCAN` with `neverForLocation`, `BLUETOOTH_CONNECT`) are requested at first scan.
