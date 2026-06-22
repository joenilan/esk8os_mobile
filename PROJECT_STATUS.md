# ESK8OS Mobile — Project Status & Roadmap

> **This document is the single source of truth for any AI agent resuming work on this project.**
> Read this FIRST before doing anything. Last updated: 2026-06-21.

---

## Project Overview

ESK8OS Mobile is a Flutter companion app for the ESK8OS longboard display (ESP32).
The app communicates with the board over BLE and should **mirror the board's on-screen display** —
the user rides looking at the phone in their hand, only glancing at the board's tiny screen when stopped.

---

## Repos & Locations

| | Firmware | App |
|---|---|---|
| **Repo** | github.com/joenilan/esk8os | github.com/joenilan/esk8os_mobile |
| **Local path** | `E:\AI\Longboard-Display` | `E:\AI\esk8os_mobile` |
| **Branch** | `next-dev` | `main` |
| **Version** | 0.8.0 | 0.1.0 |

> ⚠️ `E:\AI\esk8os_mobile` sits inside `E:\AI` which has its own `.git` with secrets. **Never** run git from `E:\AI`. Always `cd E:\AI\esk8os_mobile` first.

---

## Toolchain

- **Flutter** 3.44.2 / Dart 3.12.2 at `C:\dev\flutter`
- **Android SDK** 36.1.0; JDK pinned to `C:\Program Files\Android\Android Studio\jbr`
- **Test device**: Samsung S23 (`RFCW405TSXD`), USB debugging authorized
- **Build commands**:
  ```
  cd E:/AI/esk8os_mobile
  C:/dev/flutter/bin/flutter analyze
  C:/dev/flutter/bin/flutter run -d RFCW405TSXD
  C:/dev/flutter/bin/flutter build apk --release
  ```
- BLE testing requires a **physical device** + the **board powered**

---

## Current App Structure

```
lib/
├── main.dart                      # Esk8App, ScanPage, DashboardPage (PageView)
├── ble/
│   ├── esk8os_ble.dart            # Pure-Dart contract: UUIDs, models, commands
│   └── companion_device.dart      # flutter_blue_plus wrapper: scan, connect, telemetry
├── pages/
│   ├── settings_page.dart         # Board settings (units, theme, battery, profile)
│   └── wifi_export_page.dart      # Hybrid WiFi OTA and log download wizard
├── views/                         # Swipeable display pages (mirror the board)
│   ├── hud_view.dart              # Massive speed + battery bar
│   ├── dash_view.dart             # Speed, watts, volts, motor/esc temps
│   ├── power_view.dart            # Battery %, volts, amps, watts, session Wh
│   ├── trip_view.dart             # Distance, max speed
│   └── graphs_view.dart           # Live power chart (fl_chart)
└── wifi/
    └── wifi_service.dart          # HTTP requests for the board's standalone AP
```

---

## What's DONE ✅

### Firmware (v0.8.0, `next-dev`) — hardware-verified
- Companion BLE service (5 Hz JSON telemetry, settings R/W, commands)
- Standalone WiFi AP log/OTA web service
- Single NimBLE server shared with VESC bridge

### App (v0.1.0, `main`) — hardware-verified on S23
- **Full-Screen Immersive Mode**: `SystemUiMode.immersiveSticky` on app start
- **ScanPage**: scan for boards advertising companion service UUID, tap to connect
- **DashboardPage**: swipeable PageView mirroring the board's 5 display pages:
  - **HudView**: massive speed text + battery bar (minimalist, glanceable)
  - **DashView**: speed, watts, volts, motor/ESC temps
  - **PowerView**: battery %, volts, amps, watts, session Wh
  - **TripView**: trip distance, max speed
  - **GraphsView**: live power chart (fl_chart, rolling 60-point window)
  - Swiping sends `pageNext`/`pagePrev` to the board → both screens stay in sync
  - Tap to reveal overlay: Settings gear + command buttons (Trip Reset, WiFi, Bridge, Reboot)
- **SettingsPage**: read/write board settings over BLE
  - Units toggle (MPH/KM/H)
  - Theme dropdown (8 themes: CAM, EMBER, ICE, LIGHT, CYBER, SYNTHWAVE, MONO, FOREST)
  - Battery cells slider (6–14S)
  - Wheel profile selector (0/1) with read-only derived fields (poles, wheel, gear)
  - Immediate-write-on-change, re-read to confirm round-trip
- **WifiExportPage**: Hybrid WiFi OTA and log download wizard
  - Triggers the board to start its AP over BLE
  - Downloads `.csv` ride logs via HTTP
  - Uploads `.bin` firmware files for OTA updates via multipart POST
  - Ensures the board's AP is stopped upon exit

---

## Key Technical Notes

- **flutter_blue_plus 2.x**: requires `License.nonprofit` on `device.connect()`
- **MTU**: app requests 512 on connect (telemetry JSON would truncate at 20)
- **Scan filter**: by service UUID; Android 12+ perms (`BLUETOOTH_SCAN` neverForLocation + `BLUETOOTH_CONNECT`)
- **Settings writes**: partial updates only — send only changed fields
- **Settings semantics**: `poles`/`wheel`/`gear` are read-only (derived from `profile`); writable: `mph`, `theme`, `bat_s`, `profile`
- **Board accent**: `#B950D7` (purple)

---

## UX Requirements

### Full-Screen / Immersive Mode
- **The app MUST run in full-screen immersive mode** — hide the Android status bar, navigation bar, and all system UI chrome
- Use `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)` in Flutter
- This makes the app feel like a dedicated instrument, not a regular app
- System bars should reappear on swipe from edge, then auto-hide again

### Glanceable Design
- Dashboard should be readable at arm's length while riding
- Large, high-contrast text on dark background
- The phone mirrors the board's display pages (HUD, Dash, Power, Trip, Graphs)

---

## Feature Roadmap (ordered)

### 1. ✅ Settings Screen — DONE
Board settings read/write via BLE.

### 2. ✅ Full-Screen Immersive Mode — DONE
- `SystemUiMode.immersiveSticky` enabled on app start

### 3. ✅ Hybrid WiFi Log-Download + OTA — DONE
- Complete UI flow built in `WifiExportPage` and integrated into the Dashboard.

### 4. ✅ UI Polish / Mirror Display — DONE
- Swipeable PageView (HUD → Dash → Power → Trip → Graphs)
- Page swipes sync with board via `pageNext`/`pagePrev` commands
- Tap-to-reveal controls overlay (no AppBar clutter)
- Live power graph with `fl_chart`

### 5. 🔲 GPS Trip Tracking (BACKLOG — not started)
**Reference**: [GPS Speedometer Odometer](https://play.google.com/store/apps/details?id=gps.speedometer.gpsspeedometer.odometer) — replicate but for electric skateboarding, ad-free.

**Core features**:
- **Live GPS tracking** while riding — record route path using phone GPS
- **Google Maps overlay** — show the entire trip route drawn on a map after the ride
- **Trip statistics** (computed from BLE telemetry + GPS)
- **Trip history** — save past rides with route + stats, browse/review later
- **Export** — GPX export, shareable trip summaries

---

## Deferred / Not Doing Now
- Merge firmware `next-dev` → `main` (user chose to wait)
- iOS build (no Mac/Xcode set up; Android is the focus)

---

## Environment Notes
- Windows Developer Mode is ON
- `flutter run` stays attached (no exit) — run backgrounded and tail log, or use for hot reload
- First Gradle build ~3.5 min; subsequent fast
- APK: `build/app/outputs/flutter-apk/app-release.apk` (43.5 MB)
