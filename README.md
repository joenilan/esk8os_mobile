# ESK8OS Companion

Flutter companion app for the **ESK8OS** longboard display (LilyGo T-Display-S3 / ESP32-S3). It connects to the board over BLE to show live ride telemetry, change settings, and trigger actions — and uses the board's WiFi AP for bulk ride-log download / OTA firmware updates.

Cross-platform (one codebase). **Android first; iOS later.**

## Firmware contract

The app talks to the firmware's custom companion BLE service. The contract is mirrored in `lib/ble/esk8os_ble.dart` and specified in `docs/companion_api_spec.md` in the firmware repo ([Esk8OS](https://github.com/joenilan/Esk8OS)).

- **Service** `5043697a-0000-4682-93cb-33bb0a149f7e`
  - **Telemetry** `…0001` (NOTIFY) — 5 Hz JSON ride data
  - **Settings** `…0002` (READ/WRITE) — board config (partial writes OK)
  - **Command** `…0003` (WRITE) — ASCII actions (`TRIP_RESET`, `PAGE_NEXT/PREV`, `BRIDGE_MODE`, `WIFI_EXPORT_START/STOP`, `REBOOT`)
- Scan **actively** and filter by the service UUID. Request a large **MTU (512)** on connect — telemetry is one JSON notify and truncates at the 20-byte default.
- `poles` / `wheel` / `gear` settings are read-only (preset-derived); write `profile` to switch wheel presets.

## Status

Early scaffold: scan → connect → live telemetry grid + command buttons. **Not yet run on a device** (BLE requires a physical Android phone — emulators have no Bluetooth).

## Project layout

- `lib/ble/esk8os_ble.dart` — pure-Dart contract: UUIDs, command strings, `Telemetry` / `BoardSettings` models, WiFi-export constants
- `lib/ble/companion_device.dart` — flutter_blue_plus wrapper: scan, connect (MTU), telemetry stream, settings read/write, command send
- `lib/main.dart` — scan page + dashboard page

## Develop

Requires Flutter (stable), Android SDK (via Android Studio), JDK 17, Windows Developer Mode (for plugin symlinks), and a **physical Android device** with USB debugging.

```bash
flutter pub get
flutter analyze
flutter run            # with an Android device attached
```

BLE notes:
- `flutter_blue_plus` 2.x requires a license at `connect()` — this app uses `License.nonprofit` (free/personal tier). Change to commercial if the app is ever sold.
- Android 12+ runtime permissions (`BLUETOOTH_SCAN` with `neverForLocation`, `BLUETOOTH_CONNECT`) are requested at first scan.
