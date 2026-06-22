# ESK8OS — Handoff (updated 2026-06-21, session 2)

Two repos in play, both pushed. This supersedes the prior handoff and the other-AI handoff.

- **Firmware** `Esk8OS` — `E:\AI\Longboard-Display`, branch `next-dev`, v0.8.0.
- **App** `esk8os_mobile` — `E:\AI\esk8os_mobile`, branch `main`, v0.1.0, Flutter.

The BLE bridge (scan/connect/telemetry/commands) is **hardware-verified** on the user's Samsung S23 (`RFCW405TSXD`). The app has since grown a lot (maps, GPS, SQLite, mock mode, multiple views).

---

## 🔴 TOP PRIORITY: battery %/range accuracy (root-caused this session)

Real-world symptom: on a ride the board "died at ~30%", and range is only believable when stopped. **This is a firmware estimation bug, not a dead battery, and only partly wheelsize.** Evidence in `Longboard-Display/src/telemetry/telemetry.cpp`:

- `pollVescData()` line ~189 computes SoC as a **linear map of instantaneous (loaded) pack voltage**: `pct = (V−MIN)/(MAX−MIN)`, `MIN=cells×3.30`, `MAX=cells×4.20`. Two failures: (a) voltage **sags under load**, so % and range dive while riding and only recover when stopped; (b) **linear ≠ Li-ion discharge curve**, so it over-reads near empty (≈3.57 V/cell reads "30%" but is ~empty under load).
- `updateRangeEstimate()` lines ~149-173: `remainingRangeKm = usablePackWh × battery% ÷ Wh/km` — inherits the bad %. `Wh/km` is learned only after `RANGE_LEARN_MIN_DISTANCE_KM`/`_WH`, else falls back to `RANGE_DEFAULT_WH_PER_MILE`.
- `BATTERY_EFFECTIVE_CAPACITY_AH` defaults **16.5**, cells **10** — if these don't match the real pack, `configuredUsablePackWh()` is wrong and range is garbage regardless of curve.

**Fix plan (firmware):** replace voltage-linear SoC with **coulomb counting** — VESC already reports Wh used: `SoC ≈ 100×(1 − netWhUsed/usablePackWh)`, smoothed, calibrated to resting voltage; range from that. Minimum viable: low-pass the voltage + a Li-ion piecewise curve. **Blocked on real config values** (pack S/P + cell Ah, VESC cutoff start/end V, firmware CELLS/PACK AH/STOP-CELL/WH-MI, wheel diameter + pulley teeth + pole count). "Cut down at 85%" is a misremembered **VESC battery-cutoff** setting, not firmware.

**Quick app win (independent):** `Telemetry.range`, `.motorTempC`, `.escTempC`, `.wattHours` are ALL already streamed + parsed but NOT displayed in `HudView`. Add a range readout (+ temps) so range is visible while riding immediately. (Correction to the prior handoff: these fields are already parsed — they only need *displaying*. Efficiency/Ah/cell-voltages are the ones that need NEW firmware payload fields.)

---

## Firmware companion BLE contract (what the app talks to)

Spec: `Longboard-Display/docs/companion_api_spec.md`. Mirrored in `lib/ble/esk8os_ble.dart`.

- Service `5043697a-0000-…`; chars: telemetry `…0001` (NOTIFY, 5 Hz JSON), settings `…0002` (READ/WRITE), command `…0003` (WRITE).
- Telemetry JSON keys: `spd, bat, v, w, mtr_t, esc_t, rng, max_s, wh` (units follow the board's mph setting). **Not yet in payload** (would need firmware edit to `companion_ble.cpp` `companionBleTick`): efficiency/avg Wh-per-mi, Ah drawn, duty, fault, cell voltages.
- Settings JSON: `mph` (bool), `theme` (string, board names are UPPERCASE: CAM/EMBER/ICE/LIGHT/CYBER/SYNTHWAVE/MONO/FOREST), `bat_s` (int 6–14), `profile` (int). `poles`/`wheel`/`gear` are READ-ONLY (derived from preset).
- Commands: `TRIP_RESET, PAGE_NEXT, PAGE_PREV, BRIDGE_MODE, WIFI_EXPORT_START, WIFI_EXPORT_STOP, REBOOT`.
- Hybrid log/OTA: send `WIFI_EXPORT_START` → board raises AP `ESK8-BRIDGE`/`esk8bridge` → HTTP `http://192.168.4.1/` (`/dl?f=` log download, `/update` OTA POST) → `WIFI_EXPORT_STOP`. Same pages also served in bridge mode.

---

## App state (`esk8os_mobile`, branch `main`)

**Aesthetic:** NZXT-CAM inspired — dark (`0xFF1E1E1E` panels on near-black), purple accent (note inconsistency: `main.dart` uses `0xFFB950D7`, some views use `0xFF8B5CF6` — unify), BebasNeue (`google_fonts`) for big mechanical numerals.

**Architecture:**
- `lib/ble/esk8os_ble.dart` — pure-Dart contract + `Esk8Device` abstract interface (connectionState as `DeviceConnectionState` enum, telemetry stream, settings read/write, sendCommand) + `Telemetry`/`BoardSettings` models.
- `lib/ble/companion_device.dart` — real board via `flutter_blue_plus` (scan, connect+MTU 512, notify decode, settings, commands). NOTE: `connect()` needs `license: License.nonprofit` (fbp 2.x free tier).
- `lib/ble/mock_device.dart` — synthetic fluctuating data; bug icon on scan page launches it (UI work without hardware).
- `lib/database/trip_database.dart` — SQLite `trips` + high-rate `telemetry` logs.
- `lib/wifi/wifi_service.dart` — WiFi export helper. `lib/pages/`: `settings_page`, `wifi_export_page`, `trip_history_page`, `trip_playback_page`. `lib/views/`: `hud_view`, `dash_view`, `power_view`, `graphs_view`, `trip_view`.
- `lib/main.dart` — `ScanPage` (scan + mock) → `DashboardPage` = `PageView` of views; swiping a page sends `PAGE_NEXT/PREV` to the board; double-tap toggles a control overlay (avoids map gesture conflicts).

**Built:** BLE scan/connect, mock mode, HUD (speed/battery/power/voltage/current), Trip map+GPS (flutter_map CartoDB dark + geolocator) with board-vs-GPS compare, trip history + timeline playback, basic settings (mph toggle r/w), gesture nav.

**Missing / next:** range+temps on HUD (data already there); a detailed Stats view (temps/efficiency/cells); CSV/GPX export of logged trips; OTA UI via the WiFi flow; ride modes/profiles (would need firmware support); unify accent color.

---

## ⭐ Product vision (drives design)
The app should **mirror the board's display so the rider looks at the phone in-hand, not the tiny screen** — including paging through the same views, big and glanceable at arm's length while moving. Only look at the board when stopped. Keep this central for the eventual design pass (`frontend-design` skill).

Agreed feature order (still holds): **1) finish core feature parity (range/stats, settings, export, OTA) → 2) then polish.** User wants everything solid and matching the board before styling.

---

## Toolchain (ready)
Flutter 3.44.2 at `C:\dev\flutter` (on PATH). Android SDK 36.1.0, licenses accepted, JDK = Android Studio JBR (`flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"`), Windows Developer Mode ON. Test device S23 `RFCW405TSXD`.
```
cd E:/AI/esk8os_mobile
C:/dev/flutter/bin/flutter analyze
C:/dev/flutter/bin/flutter run -d RFCW405TSXD      # background it; stays attached
C:/dev/flutter/bin/flutter build apk --release     # → build/app/outputs/flutter-apk/app-release.apk (~43 MB)
```
BLE needs a physical device (no emulator BT) + the board powered.

## Hazards
- **Nested repo:** `E:\AI\esk8os_mobile` lives inside the `E:\AI` repo (holds `.env`/secrets, never push). App has its OWN `.git`; only run git from inside `esk8os_mobile`. Never commit/push from `E:\AI`.
- fbp `License.nonprofit`; MTU 512 or telemetry truncates; scan filters by service UUID; firmware WiFi-teardown log noise is benign.

## Resuming-agent notes
- Auto-loaded memory: `longboard-display-status`, `esk8os-mobile-app-plan`.
- Verify the board is powered before on-device BLE tests.
