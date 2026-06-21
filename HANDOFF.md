# ESK8OS — Session Handoff (2026-06-21)

Clean state to resume hard work next session. Two repos are in play; both are committed and pushed.

---

## TL;DR — where things are

- **Firmware** (`Esk8OS`, branch `next-dev`, v0.8.0): companion BLE service + standalone log/OTA web service are **done and hardware-verified**. Pushed.
- **App** (`esk8os_mobile`, branch `main`, v0.1.0): Flutter companion. Scan → connect → live telemetry → command buttons, **hardware-verified on the user's Samsung S23**. Pushed.
- The full BLE bridge between board and phone **works end-to-end on real hardware**. The hard part is done.
- Next work is on the **app**: build out features in this order (user-agreed): **1) Settings screen → 2) Hybrid WiFi log-download + OTA → 3) UI polish**.

---

## ⭐ Product vision (drives app design — read this first)

The app should **mirror the board's on-screen display**, not just show a flat telemetry grid. The user wants to **ride while looking at the phone in their hand** — including **navigating the same pages the board shows** (HUD, Dash, Power, Trip, Graphs, etc.) — and only glance at the board's tiny screen when stopped. So:

- The phone dashboard should evolve toward **reflecting what the board is showing / letting you page through the same views** from your hand.
- Page commands already exist (`PAGE_NEXT`/`PAGE_PREV` mirror the board); the richer goal is the app showing the same *content* per page, big and readable in-hand.
- Keep this in mind when building the Settings screen and especially when doing the design pass — the layout should be glanceable at arm's length while moving.

---

## Repos, locations, versions

| | Firmware | App |
|---|---|---|
| Repo | github.com/joenilan/Esk8OS | github.com/joenilan/esk8os_mobile |
| Local path | `E:\AI\Longboard-Display` | `E:\AI\esk8os_mobile` |
| Branch | `next-dev` (pushed) | `main` (pushed) |
| Version | 0.8.0 (`version.txt`) | 0.1.0 (`pubspec.yaml`) |

**⚠️ Nested-repo hazard:** `E:\AI\esk8os_mobile` sits INSIDE the `E:\AI` repo, which holds `.env`/secrets, has no remote, and **must never be pushed**. The app has its own nested `.git`; always run git from *inside* `esk8os_mobile`. Never `git add`/commit/push from `E:\AI`. (Likewise the firmware is its own repo at `E:\AI\Longboard-Display`.)

---

## What's DONE and verified

### Firmware (`next-dev`, v0.8.0)
- **Companion BLE service** (`src/services/companion_ble.{h,cpp}`, ArduinoJson): custom service `5043697a-…`, 5 Hz JSON telemetry (NOTIFY), settings READ/WRITE→NVS, ASCII command strings. Spec: `docs/companion_api_spec.md`.
- **One shared NimBLE server**: companion_ble owns `NimBLEDevice::init()` in `setup()`, advertises 100% of the time (device name `ESK8-BLE`; companion UUID in primary adv, name + VESC NUS UUID in scan response). The VESC-Tool bridge co-hosts on the same server via `bleBridgeRegister()` + a forwarding flag — no init/deinit churn. BLE callbacks only enqueue; `companionBleTick()` (UI thread) applies settings/commands/telemetry (GFX+flash single-threaded).
- **Standalone log/OTA web service** (`webexport.cpp` + `wifiApStart/Stop`): raises its own AP (`ESK8-BRIDGE`/`esk8bridge`, `http://192.168.4.1`) for ride-log download + OTA **without** entering VESC bridge mode (telemetry/BLE stay live). Same pages served in bridge mode too → logs/OTA reachable bridged or unbridged. `WIFI_EXPORT_START`/`WIFI_EXPORT_STOP` commands + `wifi on|off` serial console. 10-min idle auto-drop. Hardware-tested.
- ESP-NOW / aux-sensor scaffolding was **removed** (no wireless sensors; everything wired except the phone).
- Benign log noise on WiFi teardown (`netstack cb reg failed` / `timeout when WiFi un-init`) — verified cosmetic, WiFi recovers. Don't chase it.

### App (`main`, v0.1.0) — verified on S23 (SM S911U, Android 16)
- `lib/ble/esk8os_ble.dart` — pure-Dart contract: UUIDs, command strings, `Telemetry` + `BoardSettings` models, WiFi-export constants. Mirrors the firmware spec.
- `lib/ble/companion_device.dart` — `flutter_blue_plus` wrapper: permission request, scan (filtered by service UUID), connect + `requestMtu(512)`, telemetry stream (decodes JSON notifies), `readSettings()`, `writeSettings(partial)`, `sendCommand()`.
- `lib/main.dart` — `ScanPage` (scan list → tap to connect) + `DashboardPage` (telemetry hero/grid + command buttons: Trip Reset, Page ◀▶, WiFi Export on/off, Bridge, Reboot).
- **Verified on-device:** scan, connect, MTU, characteristic discovery, live telemetry, and command writes (page cycling moved the board's display) all work.

---

## Toolchain (already set up — env is ready)

- **Flutter** 3.44.2 / Dart 3.12.2 at `C:\dev\flutter` (on user PATH). Invoke as `C:/dev/flutter/bin/flutter` from tools.
- **Android**: Android Studio + SDK 36.1.0; cmdline-tools installed at `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest`; licenses accepted; Flutter JDK pinned to `C:\Program Files\Android\Android Studio\jbr` via `flutter config --jdk-dir`. Windows Developer Mode is ON.
- **Test device**: Samsung S23, id `RFCW405TSXD`, USB debugging authorized.
- **Build / run / install:**
  ```
  cd E:/AI/esk8os_mobile
  C:/dev/flutter/bin/flutter analyze
  C:/dev/flutter/bin/flutter run -d RFCW405TSXD        # live on the S23 (run in background; it won't exit)
  C:/dev/flutter/bin/flutter build apk --release       # → build/app/outputs/flutter-apk/app-release.apk (43.5 MB)
  ```
  `flutter run` stays attached (no exit) — run it backgrounded and tail the log, or use it for hot reload. First Gradle build was ~3.5 min; subsequent are fast.
- **APKs** (current): `build/app/outputs/flutter-apk/app-release.apk` (43.5 MB, for the second phone) and `app-debug.apk` (141 MB).
- BLE can only be tested on a **physical device** (emulators have no Bluetooth). To test, the **board must be powered** (its flashed firmware already advertises the companion service).

---

## Key gotchas / facts

- **flutter_blue_plus 2.x** requires a `license:` arg on `device.connect()` — using `License.nonprofit` (free/personal tier). Change to commercial only if the app is sold.
- **MTU**: telemetry is one JSON notify; app requests MTU 512 on connect or it would truncate at 20 bytes.
- **Scan**: filter by service UUID; Android 12+ perms `BLUETOOTH_SCAN` (with `neverForLocation`) + `BLUETOOTH_CONNECT`, requested at first scan. (`AndroidManifest.xml` already has these + INTERNET for the WiFi HTTP transfer.)
- **Settings semantics**: `poles`/`wheel`/`gear` are **read-only** (derived from the wheel preset); write `profile` (int index) to switch presets. Writable: `mph` (bool), `theme` (string, case-insensitive — board theme names are UPPERCASE e.g. `CAM`,`CYBER`), `bat_s` (int 6–14), `profile`.
- **Telemetry units**: values are already in the board's configured unit (`mph` setting). The app currently hardcodes the "SPEED" label — should read `BoardSettings.mph` to show mph/kmh.

---

## NEXT TASK (start here): Settings screen

Smallest high-value step; exercises the read/write path not yet tested live.

- **Already exists**: `companion_device.readSettings()` → `BoardSettings`, `companion_device.writeSettings(Map)`, and `BoardSettings.writeJson({mph, theme, batterySeries, profile})` helper.
- **Build**: a Settings page (push from the dashboard via an app-bar action). On open, `readSettings()` and show current values. Editable controls:
  - Units: toggle mph/kmh → `writeSettings(BoardSettings.writeJson(mph: ...))`
  - Theme: dropdown of the 8 board themes (CAM/EMBER/ICE/LIGHT/CYBER/SYNTHWAVE/MONO/FOREST) → `theme:`
  - Battery cells (`bat_s`, 6–14) → `batterySeries:`
  - Wheel profile (`profile`, currently 0/1) → `profile:`; show derived poles/wheel/gear read-only.
- **Verify on device**: change a setting in the app, confirm the board's display updates (it repaints on write) and persists (NVS).
- Watch: writes are partial — only send changed fields. Re-`readSettings()` after a write to confirm round-trip.

### Then: Hybrid WiFi log-download + OTA
- Flow: app sends `WIFI_EXPORT_START` → prompt user to join WiFi `ESK8-BRIDGE`/`esk8bridge` → HTTP GET `http://192.168.4.1/` (ride-log index + `/dl?f=...` downloads; `/update` multipart POST for OTA `.bin`) → `WIFI_EXPORT_STOP` when done. Constants are in `lib/ble/esk8os_ble.dart` (`Esk8WifiExport`). Will need an HTTP client (`http` or `dio`) and likely guidance for the user to switch WiFi (Android won't auto-join a no-internet AP without `WifiNetworkSpecifier` — start with manual join + a "I've joined" button).

### Then: UI polish
- Use the `frontend-design` skill. Match the board's look (accent `#B950D7`, dark) and the **mirror-the-display, glanceable-in-hand** vision above. Page through the same views the board shows.

---

## Deferred / not doing now
- **Merge `next-dev` → main** on the firmware (Option A) — user chose to wait.
- iOS build — Flutter is cross-platform so it's "free-ish" later, but Android is the focus; no Mac/iOS toolchain set up.

## Notes for the resuming agent
- Persistent memory is at the project memory dir and auto-loads: see `longboard-display-status` and `esk8os-mobile-app-plan`.
- An older `E:\AI\Longboard-Display\Handoff.md` exists but is **superseded by this file**.
- Confirm the board is powered before any on-device BLE test; the S23 (`RFCW405TSXD`) is the test phone.
