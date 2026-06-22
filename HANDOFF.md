# ESK8OS Companion — Handoff & App-Overhaul Plan

**Single source of truth for the app.** Last updated 2026-06-22. (Supersedes the old `PROJECT_STATUS.md`, which was deleted — it falsely claimed "mirror display / GPS done.")

---

## Repos, paths, versions
| | Firmware | App |
|---|---|---|
| Repo | github.com/joenilan/Esk8OS | github.com/joenilan/esk8os_mobile |
| Path | `E:\AI\Longboard-Display` | `E:\AI\esk8os_mobile` |
| Branch | `next-dev` | `main` |
| Version | **0.8.4** | **0.1.0** |

⚠️ **Nested-repo hazard:** `E:\AI\esk8os_mobile` lives inside the `E:\AI` repo (holds `.env`/secrets, no remote, NEVER push). The app has its own `.git`; always run git from *inside* `esk8os_mobile`. Never `git add`/commit/push from `E:\AI`.

## Toolchain (ready)
- Flutter 3.44.2 / Dart 3.12.2 at `C:\dev\flutter` (on PATH). Invoke `C:/dev/flutter/bin/flutter`.
- Android SDK 36.1.0, JDK = `C:\Program Files\Android\Android Studio\jbr`, Windows Dev Mode ON.
- Test device: **Samsung S23 `RFCW405TSXD`**. BLE needs a physical device (no emulator BT) + the board powered. Mock device (bug icon on scan page) for UI-only work.
```
cd E:/AI/esk8os_mobile
C:/dev/flutter/bin/flutter analyze
C:/dev/flutter/bin/flutter run -d RFCW405TSXD     # background it; stays attached
C:/dev/flutter/bin/flutter build apk --release    # → build/app/outputs/flutter-apk/app-release.apk
```

## What's working (hardware-verified)
- Scan → connect (MTU 512) → live telemetry → command buttons.
- **Background trip recording** (`lib/services/trip_recorder.dart`): app-level singleton, GPS under an Android foreground service, survives screen-off/page-swipes. (Not yet ride-tested for doze.)
- Trip map/GPS (`trip_view.dart`), SQLite trips (`trip_database.dart`), history/playback pages, WiFi log/OTA page.
- Settings page reads/writes the board (units, theme, battery cells, wheel profile).

## Current app structure
```
lib/
  main.dart                  Esk8App, ScanPage, DashboardPage (PageView of views + tap overlay)
  ble/esk8os_ble.dart        contract: UUIDs, commands, Telemetry + BoardSettings models, Esk8Device interface
  ble/companion_device.dart  flutter_blue_plus impl (License.nonprofit on connect)
  ble/mock_device.dart       synthetic data (bug icon on scan)
  services/trip_recorder.dart  background recording singleton
  database/trip_database.dart   SQLite trips + telemetry
  wifi/wifi_service.dart      HTTP to board AP
  pages/  settings_page, wifi_export_page, trip_history_page, trip_playback_page
  views/  hud_view, dash_view, power_view, trip_view, graphs_view
```

---

# 🎯 THE APP OVERHAUL (next major effort)

## The problem (user's words, confirmed in code)
1. **Pages are redundant** — `HudView`, `DashView`, `PowerView` all show the same few values (speed/watts/volts/temps) in different layouts. They don't mirror the board's distinct pages.
2. **Settings page is missing firmware settings** (pack Ah, stop-cell V, Wh/mi) — *because the BLE settings payload doesn't expose them yet*.
3. **Layout overflow** — the speed value + unit label are on the same `Row` at 96–180 px; they overflow/clip on narrow screens (`hud_view.dart`, `dash_view.dart`).
4. **Inconsistent accent** — `0xFFB950D7` (main/hud) vs `0xFF8B5CF6` (other views). Unify to **`0xFFB950D7`**.
5. Duplicated `_Stat`/`_CamStatCard` widgets across views — no shared kit.

## Vision
Mirror the board's display so the rider reads the **phone in-hand** while moving (only glance at the tiny board screen when stopped) — including paging through the **same pages** the board shows, big and glanceable at arm's length. Dark, high-contrast, BebasNeue numerals, accent `#B950D7`.

## The board's pages = the mirror target (from `Longboard-Display/src/ui/ui.cpp`)
| Board page | Shows |
|---|---|
| **HUD** | big speed, battery cells, 2×2 tiles: watts / volts / range / temp |
| **DASH** | TEMPS (motor/battery/esc) · RANGE (estimated / remaining / avg Wh-per-mi) |
| **POWER** | POWER (motor A / battery A / duty / peak W) · ENERGY (used / regen Wh) · SPEED (max / avg) · SESSION (max pwr / min volt) |
| **TRIP** | THIS TRIP (time / distance / avg speed / max speed / efficiency) · ODOMETER (total) |
| **GRAPHS** | live line graphs over a 3-min history |
| **LOGS** | last 10 ride summaries |
| **SYSTEM** | device / memory / runtime / firmware version |
| **SETTINGS** | wheel profile · display · battery |

## ⛔ Track 1 FIRST — Firmware: expand the BLE payload (prerequisite)
The current telemetry JSON is too thin to mirror the board. **All needed values already exist as globals** in `telemetry.cpp` — it's just adding them to the JSON in `companion_ble.cpp` → `companionBleTick()`:

Add to telemetry JSON (current keys: `spd,bat,v,w,mtr_t,esc_t,rng,max_s,wh`):
- `bata` = `currentAmps` (battery A), `mota` = `currentMotorAmps`, `duty` = `currentDuty`, `pkw` = `peakWatts`
- `whr` = `currentWhRegen`, `avs` = `avgSpeedKmh`*, `minv` = `minVoltageSession`
- `trip` = `tripDistanceKm`*, `odo` = `totalDistanceKm`*, `est` = `estimatedRangeKm`*, `eff` = `avgWhPerKm`*
- `btemp` = `currentBatteryTemp`, `fault` = `vescFault`, `rtime` = `(millis()-rideStartMs)/1000`
- *(\*) convert to display units where the firmware does (mph/mi) for consistency with `spd`/`rng`.*

Expand settings JSON (`buildSettingsJson` + `applySettings` in `companion_ble.cpp`) to add writable:
- `packAh` = `BATTERY_EFFECTIVE_CAPACITY_AH`, `stopCell` = `BATTERY_STOP_CELL_V`, `whmi` = `RANGE_DEFAULT_WH_PER_MILE`, optionally `bright` = `gBrightnessPct`, `demo` = `gDemoMode`.

Then: bump firmware version, **update `docs/companion_api_spec.md`** to match, build + flash. Mind MTU (JSON grows but stays < 512; app already negotiates 512).

## Track 2 — App
1. **Expand models** (`esk8os_ble.dart`): add the new fields to `Telemetry` + `BoardSettings` (+ `writeJson`).
2. **Shared widget kit** (`lib/widgets/`): one stat-card/tile, one page-scaffold; kill the duplicated `_Stat`/`_CamStatCard`.
3. **Fix overflow**: speed hero uses `FittedBox`/`Flexible` (or unit on its own line) so value+unit never clip. Make all cards responsive.
4. **Rebuild each page distinct, mirroring the board** (HUD, Dash=temps+range, Power=power/energy/speed/session, Trip=trip+odometer, Graphs=multi-metric, optional System). Remove the redundant overlap.
5. **Expand Settings** with the new fields once firmware exposes them (pack Ah, stop-cell, Wh/mi, brightness).
6. **Design pass** — use the `frontend-design` skill; unify accent, typography, glanceability.
7. Keep page-swipe → board `pageNext`/`pagePrev` sync (already works).

## Suggested order
Firmware payload+settings expansion → flash → app models → shared widgets + overflow fix → rebuild pages → settings → design pass. Test on device (or mock for UI-only) each step.

---

## Key technical notes (carry forward)
- **flutter_blue_plus 2.x** needs `License.nonprofit` on `device.connect()`.
- **MTU 512** requested on connect (telemetry is one JSON notify; truncates at 20).
- Scan filters by service UUID `5043697a-0000-…`; Android 12+ perms `BLUETOOTH_SCAN`(neverForLocation)+`BLUETOOTH_CONNECT`.
- Settings: **partial writes** (send only changed). `poles`/`wheel`/`gear` are READ-ONLY (derived from `profile`). Theme names are UPPERCASE.
- Telemetry values arrive already in the board's unit (`mph` setting) — don't re-convert.
- Accent **`#B950D7`**.

## BLE contract (current — pre-overhaul)
Service `5043697a-0000-4682-93cb-33bb0a149f7e`; telemetry `…0001` NOTIFY 5 Hz, settings `…0002` R/W, command `…0003` W. Commands: `TRIP_RESET, PAGE_NEXT, PAGE_PREV, BRIDGE_MODE, WIFI_EXPORT_START, WIFI_EXPORT_STOP, REBOOT`. Full spec: `Longboard-Display/docs/companion_api_spec.md`.

## Deferred
- iOS (no Mac/Xcode; Android focus). Merge firmware `next-dev`→`main` (user waiting). Background-recording doze/pocket validation on a real ride.
