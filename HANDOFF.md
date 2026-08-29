# ESK8OS Mobile - Current Handoff

Updated 2026-08-29. Start in `E:\AI\esk8os_mobile` on branch `main`.

Read `AGENTS.md` completely before changing code. It contains the VESC
source-of-truth rules and the data-preserving build/install procedure.

## LATEST — 2026-08-29: distance fusion, segment lines, MapLibre/OpenFreeMap vector stack, offline regions

All committed through `3c549b0` (unpushed — push waits on the rider's
on-device validation + the ESP boards' v0.12.0 flash). The phone runs the
latest signed build (installed in place every round; trip data intact).

**Distance-fusion policy (schema v8, backup v3).** The fused board+GPS
distance is persisted (`fusedDistanceM`, `fusedSource`, `fusionSwitches`)
at checkpoints and stop. Reconnect policy: a board counter that advanced
through a BLE dropout is the authoritative whole-ride total (offset reset,
never double-counted); a frozen counter keeps the GPS-covered tail with GPS
as source. History rows prefer the fused figure and show `BOARD + GPS ·
FUSED ×N` when dropouts occurred. NULL fused fields (pre-policy rides) fall
back to raw GPS distance.

**CARTO enforcement.** CARTO free basemaps now serve an "API KEY REQUIRED"
error IMAGE with HTTP 200 (verified 2026-08-29). The old raster path is
dead. Stopgap shipped: light = OSM standard raster, dark = Esri World Dark
Gray Canvas (no keys). Long-term = the vector stack below.

**Vector stack (MapLibre 0.2.2 + OpenFreeMap, no API key).** `EveeVectorMap`
in `lib/maps/` behind the same seam as raster `EveeMap`. Adopted surfaces,
all behind the persisted `vectorBasemap` beta toggle (layers icon):
playback (scrub trail + marker as native layers, follow camera throttled at
20 m, gesture drops follow), trail detail (POI dots, long-click create via
`MapEventLongClick`, click-to-view nearest, fit bounds), live ride map
(route, position dot, follow, heading-up bearing via `moveCamera`). Light =
OpenFreeMap Liberty, dark = OFM Dark. The overlay isolate stays raster
(native map views can't exist in `flutter_overlay_window`'s engine).

**Smoothing.** `RidePathSmoother.displayTrack` — zero-phase forward+backward
EMA, endpoints anchored, strictly 1:1 with input points (index-consistent
slicing/keyframes). Applied to playback + live display geometry only;
recorded rows keep raw fixes (guardrail).

**Playback segments.** Rows split on >5 s timestamp gaps (pause/kill/GPS
outage): the display line never connects across a break, smoothing is
per-segment, trail base+tip are segment-aware on both map stacks.

**Offline regions.** Trail detail's download action saves the trail's
padded bounding box (z10-14, ~1 km padding, OpenFreeMap Liberty) via the
MapLibre offline manager with a progress dialog. Saved state detected on
load by bounds-center match (the plugin cannot read region metadata back).
KNOWN LIMIT: maplibre 0.2.2 has no per-region delete — long-press offers a
full offline-store reset behind a confirm.

**Pending on-device validation (rider):** vector live map during a real
ride (follow + heading-up under motion), playback segments on a ride with
a pause, offline download + airplane-mode rendering, POI create/view on
vector. **Known cosmetic debt:** POI icon badges on vector (dots only —
symbol icons need asset images), app screenshots on evee.zombie.digital
still show CARTO-era maps, APK grew ~30 MB from MapLibre natives (ABI
splits would slim it).

## Current Product Program: Board-Independent EVEE

The rider requested a product-wide audit and sustained polish program focused
on the trip recorder, maps, ride controls, performance, visual quality, and an
eventual onX-like experience built around rider-created trails.

Read `PRODUCT_ROADMAP.md` before large UI, recorder, map-provider, schema, or
trail changes. It contains the current audit findings, target
Explore/Ride/Library/Board architecture, delivery sequence, and safety
guardrails.

The first board-independent slice is implemented:

- The disconnected home opens the production ride library without BLE.
- The disconnected home is neutral EVEE ecosystem UI: it says no vehicle is
  connected and uses a generic electric mark. Scan results only use a
  vehicle-specific icon when advertised `vtype` metadata is actually present.
- **Start Phone Ride** records a complete GPS-only ride without a connected
  vehicle. It sends no BLE commands and leaves board/BMS fields unavailable.
- A connected dashboard now has a persistent disconnect icon and a labeled
  **Disconnect / Switch Vehicle** Controls action. It returns to the EVEE home
  and immediately scans again. A vehicle-backed recording is deliberately
  finished and saved first; a phone-GPS recording continues uninterrupted.
- Android system Back follows that same disconnect/switch flow at the connected
  dashboard root instead of backgrounding EVEE. Within Settings, Library, and
  Playback it remains ordinary nested-page Back navigation.
- Ride source is immutable once recording starts and is persisted as
  `phone-gps` or `board-assisted`; History and Playback label it explicitly.
- The last real board unit is cached for disconnected ride presentation; this
  cache never writes or shadows board settings.
- Ride count is visible on the disconnected home and refreshes after returning
  from the library.
- Mock Mode moved from the prominent bug icon into an overflow action.
- The board scan is now the clear primary action without making recorded rides
  inaccessible.

The first recorder-reliability slice is also implemented:

- Recording has explicit starting, recording, paused, stopping, and error
  states, with busy controls disabled during transitions.
- Trip-row writes and checkpoints are serialized; Stop drains pending writes
  before saving the final summary.
- Failed starts unwind subscriptions, wake lock, notification service, and
  empty trip shells instead of leaving a phantom ride.
- Fresh GPS fixes are filtered for age, accuracy, invalid coordinates, and
  implausible jumps. Cached fixes center the map but never become route data.
- GPS and BLE freshness now gate live speed and persisted samples so stale
  values are not silently presented as current.
- Finish Ride requires confirmation; Pause remains immediate.
- The ride screen exposes preparing/saving, degraded GPS, and storage-warning
  states.

The first Ride-mode control redesign is implemented:

- One glanceable card now owns recording state, GPS health, speed/source,
  canonical board trip/moving time, and battery/source.
- Coordinates and the full board-versus-GPS evidence grid moved into a Ride
  Details sheet instead of competing with the map.
- Ride Library remains available from that sheet.
- Pause stays immediate and Finish Ride stays deliberate.

The first rider-built Trail/POI slice is implemented locally:

- Schema v7 adds independent `trails`, segmented `trail_points`, and
  `waypoints` tables plus explicit ride source through additive migrations.
- A completed Ride can be copied into a named private Trail without changing
  the raw ride or telemetry.
- Pauses, long GPS gaps, and implausible jumps become explicit trail segment
  breaks instead of false connecting lines.
- Library now separates Rides and Trails and is available with the board off.
- Trail detail supports map fit, metadata editing, surface/difficulty/direction,
  deletion independent of the source Ride, and long-press POI creation.
- Library presents Rides, Trails, and POIs as separate first-class sections;
  selecting a Trail-linked POI returns to its map.
- POI types include trailhead, viewpoint, scenic, hazard, parking, charging,
  water, food, restroom, shelter, repair, and note. The internal `Waypoint`
  model preserves standard GPX/map terminology.
- Trails export as segmented GPX (including POIs as waypoints) or GeoJSON
  `MultiLineString` with metadata and Point features.
- Android system bars are restored on Scan, Library, telemetry, settings, and
  detail pages; immersive mode is now limited to the root Ride map.
- Backup format v2 includes Rides, Trails, segmented geometry, and POIs,
  remaps source IDs on restore, and still accepts format-v1 ride-only backups.
- Real SQLite migration/CRUD/backup tests use an isolated FFI database and
  never touch the phone's production `trips.db`.

Next implementation priority is the shared map-source abstraction and
trail-search/filter polish.
Do not add offline downloads to the existing public CARTO tile URLs; select a
licensed provider or self-hosted/vector extract strategy first.

## Completed Product Task: BMS-Aware Parked Mode

The firmware-side Daly BLE integration is now implemented, flashed, and
bench-verified. The mobile app now consumes the expanded contract and
distinguishes drivetrain availability from battery availability. The detailed
contract and acceptance criteria remain below as regression requirements.

Authoritative firmware contract:

- `E:\AI\Longboard-Display\docs\companion_api_spec.md`
- Firmware repository: `E:\AI\Longboard-Display`, branch `next-dev`
- Physical board is currently running the uncommitted `tdisplay_s3_bms`
  firmware build `v0.11.0 b8b0589-dirty`.

### Verified physical transport and behavior

This is no longer an unverified UART placeholder:

- Module: Daly Bluetooth **UART K**
- Advertised name: `ZOMBIESK8-BMS`
- Static-random address: `D0:18:04:01:39:98`
- Daly service: `FFF0`
- `FFF1`: `READ`, `NOTIFY`, module to ESP32
- `FFF2`: `READ`, `WRITE`, `WRITE_NR`, ESP32 to module
- `FFF3`: present with `READ`, `WRITE`, `WRITE_NR`, unused
- The full additional `02F0...FE00` GATT table is documented in the firmware
  companion spec; ESK8OS does not use it.
- Existing checksum-valid Daly `0x90`-`0x98` requests are written to `FFF2`
  using write-without-response and replies arrive on `FFF1`.
- No BLE pairing, bonding, passkey, or application handshake was required.
- The physical UART K module accepts one central. The Daly app must be fully
  disconnected/force-stopped before ESK8OS can own the BMS link.
- ESP32 dual role is working: central/client to Daly while remaining the
  companion peripheral/server. Reconnect backoff is 2-60 seconds and does not
  rebuild companion advertising or intentionally drop the phone.

BMS settings writes remain intentionally unavailable. A Daly-app HCI capture
established a newer Modbus-like register protocol and showed that the six-digit
password is checked locally by the Daly app, not used as BLE authentication.
Do not add mobile BMS writes from the captured reads alone. Safe writes require
verified register semantics, limits/dependencies, reply validation, and read
back. This task is monitoring and diagnostics only.

### New `0001` drivetrain/battery semantics

`live` continues to mean fresh **drivetrain/VESC** telemetry. The firmware now
also sends:

```json
{
  "live": false,
  "vesc": false,
  "blive": true,
  "bsrc": "daly",
  "bat": 100,
  "v": 41.8,
  "btemp": 21,
  "rng": 21.4,
  "cellv": 4.18
}
```

`bsrc` is one of `none`, `vesc`, `daly`, `fused`, or `demo`. When the board is
USB-powered with the VESC off but Daly reachable, `live:false` and
`blive:true`. Battery, voltage, BMS temperature, range, and cell voltage remain
meaningful. Speed, watts, battery/motor amps, duty, motor/ESC temperatures, and
VESC faults remain drive-only and are zero-filled on the wire for compatibility;
the UI must render those fields as unavailable (`--`), not as real zeroes.

Update `Telemetry` in `lib/ble/esk8os_ble.dart` with battery availability and
source. For older firmware that lacks the new keys, degrade compatibly:

- `batteryLive` should fall back to `live`.
- A missing source should resolve to `vesc` when legacy `live:true`, otherwise
  `none` (do not invent Daly availability).
- Preserve `live` as the trip recorder's board-speed/VESC authority. Do not use
  `blive` to suppress GPS speed fallback or start a ride while merely parked.
- Do not substitute `0006.cur` for VESC `bata`. The 2026-07-30 ride verified
  Daly current as negative discharge / positive charge and its integrated
  discharge agreed with the remaining-Ah decrement to about 1.4%, but the VESC
  remains the live drivetrain, safety, power, and energy-integration authority.

Expected UI behavior:

- Top status: `DRIVE OFF · BMS LIVE` (or equivalent) rather than only
  `NO VESC DATA`.
- HUD continues to show Daly battery %, volts, range, and BMS temperature while
  speed/watts/drive-only values show `--`.
- Dashboard masks drive-only rows but may retain its valid battery/range rows.
- Boards without `0006` or without `blive` retain the original VESC-only flow.

### Expanded `0006` model

Characteristic `0006` still exists and its old keys are unchanged. It now adds:

- `fv`: response-group freshness mask
- `al`: alarm classification
- `fb`: seven raw `0x98` bytes as 14 lowercase hex characters
- `lfb`: optional latest non-zero `0x98` frame this board boot
- `lfa`: optional seconds since `lfb` was observed

Freshness bits are:

```text
bit 0 pack
bit 1 min/max voltage
bit 2 min/max temperature
bit 3 MOS / remaining Ah
bit 4 status / topology
bit 5 cells
bit 6 temperature sensors
bit 7 balance
bit 8 fault bytes
```

`0x1ff` means all nine groups are fresh. Alarm levels are:

```text
0 none
1 physically verified Level-1 warning
2 other/unknown alert (treat as serious)
3 fault response stale
```

Bench evidence on the actual pack:

```text
41.80 V, 100%, 32.000 Ah, 21 C
10 cells, min cell 10 = 4177 mV, max = 4187 mV, delta = 10 mV
charge MOS ON, discharge MOS ON
fv = 0x1ff
al = 1
fb = 11000000000000
```

The two set bits were verified against the captured physical settings:

- raw byte 0 bit 0: cell-high Level 1, threshold 4.150 V
- raw byte 0 bit 4: pack-high Level 1, threshold 41.5 V

The Level-2/protection thresholds are 4.250 V/cell and 42.5 V. Therefore this
pack's current `al:1` is a yellow high-state warning, not a red protection trip;
both MOSFETs remain on. The 10 mV spread is healthy.

Extend `BmsData`, its `toJson`/`fromJson`, trip persistence, playback, and mock
data with these fields. Compatibility rules:

- When `fv` is absent on older firmware, preserve legacy link-based behavior;
  do not mark every value stale merely because the key is missing.
- When `al` is absent, `flt:true` must remain conservatively unclassified/alert,
  while `flt:false` is none.
- Preserve `fb` exactly when supplied.
- Group freshness must control whether a carried-forward value is presented as
  current. Per-cell `st` handling remains in force as well.

Fix these existing misleading BMS page behaviors:

- Do not show every `flt:true` as a red `FAULT`; use `al`.
- Do not paint the mathematical minimum cell red for a normal 10 mV spread.
  Match firmware behavior: reserve the weak-cell treatment for a meaningful
  delta (currently 50 mV), with stronger red treatment above 100 mV/alerts.
- At approximately zero current, label the pack `IDLE`, not `DISCHARGE`.
- Replace `check the UART wiring` with guidance to disconnect the Daly app and
  check UART K module power/range.
- Show warning/alert text, freshness, and raw fault evidence in diagnostics.

Likely implementation files:

- `lib/ble/esk8os_ble.dart`
- `lib/ble/mock_device.dart`
- `lib/main.dart`
- `lib/views/hud_view.dart`
- `lib/views/dash_view.dart`
- `lib/views/bms_view.dart`
- `lib/services/trip_recorder.dart`
- `lib/pages/trip_playback_page.dart`
- `test/telemetry_test.dart`
- `test/bms_data_test.dart`
- `test/mock_device_test.dart`

The database already stores BMS snapshots as JSON, so a schema migration should
not be necessary merely to add `fv`/`al`/`fb`; verify round-trip and backup
behavior before changing schema.

### Mobile tests and acceptance criteria

Update `MockEsk8Device` and add/extend tests for:

1. `Telemetry` parsing with `live:false`, `blive:true`, `bsrc:daly`.
2. Legacy payload fallback when `blive`/`bsrc` are absent.
3. `BmsData` round-trip of `fv`, `al`, and `fb`.
4. Legacy `0006` payloads without the new keys.
5. `al:1` rendering as warning rather than protection fault.
6. Unknown `al:2` and stale `al:3` handling.
7. Normal 10 mV minimum-cell rendering versus a genuinely large delta.
8. Trip database/backup/playback preservation of the expanded BMS snapshot.
9. Boards without characteristic `0006`.

Run:

```powershell
C:\dev\flutter\bin\flutter.bat test
C:\dev\flutter\bin\flutter.bat analyze
.\scripts\install-signed-release.ps1 -BuildOnly
```

Do not install on the phone unless the user separately requests it. Preserve
the phone's trip database with the signed in-place installer described later
in this handoff.

## Deferred Product Task: Named Setup Profiles

The fixed `Profile 0` / `Profile 1` model is not the desired product. The rider
has one wheel setup in use today; another wheel set may return later, but two
hard-coded slots are arbitrary and do not scale.

Replace that model with CRUD for named setup profiles:

- Create a profile.
- List/select saved profiles.
- Rename and edit a profile.
- Delete a profile with confirmation.
- Apply a profile to the connected board.

### Profile ownership rule

A setup profile may store only values the VESC does **not** authoritatively
provide. Never snapshot or restore battery series, pack capacity, cutoffs, motor
poles, gear ratio, or current limits. Those values continue to come live from
the VESC.

Wheel-diameter calibration is the first definite profile field. It is a valid
override because loaded tire diameter/wear can differ from the nominal VESC
value and directly affects speed/distance accuracy.

Do not automatically put unrelated phone preferences such as theme, floating
window, map style, or over-speed alert into a setup profile. Before expanding
the schema beyond wheel calibration, confirm which physical setup-specific
values the rider actually wants grouped together.

### Recommended first implementation

Keep the named profile library app-local unless the user explicitly asks for
on-board profile storage. A small persisted model should be enough:

```text
id
name
wheelOverrideMm
createdAt
updatedAt
```

Applying a profile writes its `wheelOverrideMm` to board settings. Applying a
profile that follows the VESC writes `wheelmm: 0`. The board retains the applied
effective value in NVS and therefore still works without the phone.

Scope profiles per board/device identity so two boards do not accidentally
share physical calibration. Decide the stable key from the existing connection
model before implementing; do not use a mutable display name as the only
identity.

Remove the hard-coded segmented Profile 0/1 control from the mobile UI,
including the legacy/no-`0005` path. Do not add a larger fixed number of slots.
If compatibility with old firmware needs a fallback, use the named app-local
profile to write the supported wheel override rather than selecting a compiled
firmware preset.

Add unit tests for serialization, migration, CRUD, board scoping, and applying
or clearing `wheelmm`. Add widget coverage for empty state, create/edit/delete,
selection, and delete confirmation if practical.

## Work Completed in the Current Uncommitted Change Set

The settings cleanup requested immediately before this handoff is implemented:

- Valid VESC battery/drivetrain values are read-only in the mobile settings.
- Battery cells, pack capacity, ride-home floor, limp floor, motor poles,
  motor-to-wheel ratio, and current limits display their VESC authority.
- A stale rider override shows its effective value, the VESC value, and a
  **Use VESC** action.
- Fixed firmware profile selection is hidden whenever a valid VESC base exists.
- Wheel diameter remains a deliberate calibration control with reset-to-VESC.
- Gear ratio uses the VESC motor-to-wheel convention (`72 / 16 = 4.50`), not the
  inverse value near `0.22`.
- The device-learned range model remains read-only.
- Auto record and floating window are enabled through a versioned one-time
  preference migration. A rider who later disables either stays opted out.
- App version is now `0.2.34+36`.

Sub-page chrome is now uniform. Every pushed page (settings, library, trip
playback, trail detail, phone ride, console, WiFi export/OTA) is built from
`SubPageScaffold` in `lib/widgets/esk8_widgets.dart`, which owns the
background, the `SubPageHeader`, and the `SafeArea`:

- Console and WiFi Export/OTA no longer use a Material `AppBar`, and they now
  push into the dashboard's nested deck navigator through
  `_openContentPage()` like Settings, instead of covering the whole app from
  the root navigator.
- Pages reached from the scan screen as root routes (Ride Library → playback /
  trail detail, Phone Ride) no longer run under the status bar, camera cutout,
  or gesture bar. Inside the deck the shell has already consumed those insets,
  so the shared `SafeArea` costs nothing there — `test/sub_page_scaffold_test.dart`
  pins down both hosts.

The newly installed Daly Smart BMS Bluetooth/UART-K path is implemented on the
mobile side:

- Optional characteristic `0006` was already parsed and shown as a live BMS
  page.
- The trip recorder now subscribes to `0006` when available and stores each
  fresh snapshot with its 1 Hz route row.
- Database schema v5 adds nullable `telemetry.bmsJson`; older trips and boards
  without `0006` remain compatible.
- Trip playback shows BMS pack voltage, min/max cell voltage, cell spread,
  highest temperature, SOC, weakest cell, and link-down gaps.
- JSON trip backups automatically include the stored BMS snapshots.
- Core telemetry parses `blive` and `bsrc`, with safe legacy fallback when
  older firmware omits them.
- Parked mode retains valid Daly battery, voltage, temperature, cell, and range
  values while masking zero-filled drivetrain fields as unavailable.
- Expanded BMS snapshots preserve `fv`, `al`, and `fb`; response-group
  freshness controls live and playback presentation.
- Alarm severity distinguishes Level-1 warnings, serious alerts, and stale
  fault evidence. Healthy cell spread and idle current are no longer
  misrepresented as faults or discharge.
- Mock data and tests cover demo source identity, parked Daly behavior,
  compatibility fallbacks, freshness, severity, persistence, and UI masking.

The companion firmware has a matching change:

- `UNSET:<key>` on BLE command characteristic `0003` calls
  `Settings::removeOverride()`.
- The BLE contract documentation includes the new command.
- The app verifies that provenance actually changed after sending the command;
  older firmware cannot falsely report success.

The old handoff's floating-overlay map and board-authoritative moving-time work
are already present in the codebase. Do not restart those tasks.

## Files Changed

Mobile repository:

- `AGENTS.md`
- `HANDOFF.md`
- `PRODUCT_ROADMAP.md`
- `README.md`
- `lib/ble/esk8os_ble.dart`
- `lib/ble/mock_device.dart`
- `lib/main.dart`
- `lib/pages/settings_page.dart`
- `lib/pages/trip_playback_page.dart`
- `lib/services/app_prefs.dart`
- `lib/services/trip_recorder.dart`
- `lib/database/trip_database.dart`
- `lib/views/bms_view.dart`
- `lib/views/dash_view.dart`
- `lib/views/diag_view.dart`
- `lib/views/graphs_view.dart`
- `lib/views/hud_view.dart`
- `lib/views/trip_view.dart`
- `lib/widgets/esk8_widgets.dart`
- `pubspec.yaml`
- `scripts/install-signed-release.ps1`
- `test/app_prefs_test.dart`
- `test/bms_data_test.dart`
- `test/bms_view_test.dart`
- `test/board_settings_test.dart`
- `test/mock_device_test.dart`
- `test/parked_mode_view_test.dart`
- `test/telemetry_test.dart`

Firmware repository (`E:\AI\Longboard-Display`, branch `next-dev`):

- `platformio.ini`
- `src/main.cpp`
- `src/app/App.cpp`
- `src/board/StatusLed.cpp`
- `src/logging/sessionlog.cpp`
- `src/services/companion_ble.cpp`
- `src/telemetry/BatteryView.cpp` / `.h`
- `src/telemetry/telemetry.cpp` / `.h`
- `src/transports/DalyBms.cpp` / `.h`
- `src/ui/UiRenderer.cpp`
- `src/ui/ui.cpp`
- `src/util/console.cpp`
- `docs/companion_api_spec.md`
- `docs/serial_console.md`
- `README.md`
- `AGENTS.md`

The firmware repository also has pre-existing user changes in `package.json`
and `package-lock.json`. They are unrelated; preserve them and do not include
them accidentally in this task.

## Verification Already Completed

- `flutter test`: 53 tests passed.
- `flutter analyze`: no issues.
- Signed release APK built successfully at
  `build\app\outputs\flutter-apk\app-release.apk`.
- APK package: `com.joenilan.esk8os_mobile`.
- Installed review build: `0.2.33`, version code `35`, installed in place and
  launched on `RFGL42MHF7Z` with the signing certificate matched and app data
  preserved.
- Previous installed build was `0.2.32`, version code `34`.
- Signing certificate SHA-256:
  `929ae55957d78da15ca261867f136f6c97228cc7a261b5b5066dead81b2b747f`.
- Firmware `tdisplay_s3_debug_usb` PlatformIO build succeeded.
- Firmware `tdisplay_s3_bms` PlatformIO build succeeded and was flashed to
  COM5 after archiving the board session logs.
- Live serial verification confirmed the parked Daly battery view, all nine
  fresh response groups, classified Level-1 warnings, and masked VESC fields.
- On-device schema-3 CSV verification confirmed 43 columns on every row,
  immediate `bms_link_up`, and stable parked rows at 10-second intervals.
- PowerShell installer syntax and build-only flow were verified.

The phone-GPS commute build is installed for rider testing. No changes have
been committed.

## Safe Start Sequence for the Next Agent

```powershell
Set-Location E:\AI\esk8os_mobile
Get-Content -Raw .\AGENTS.md
Get-Content -Raw .\HANDOFF.md
git status --short
C:\dev\flutter\bin\flutter.bat test
C:\dev\flutter\bin\flutter.bat analyze
```

Preserve the existing uncommitted work. Continue from it; do not reset or
recreate the settings cleanup, BMS-aware parked mode, first board-independent
home slice, or recorder-reliability work. Follow `PRODUCT_ROADMAP.md`; the Ride
control redesign is next. Named-profile CRUD remains valid but is deferred
behind the rider's product-wide app/ride/map program.

After implementing named-profile work:

```powershell
C:\dev\flutter\bin\flutter.bat test
C:\dev\flutter\bin\flutter.bat analyze
.\scripts\install-signed-release.ps1 -BuildOnly
```

The last command requires the permanent signing files and verifies a signed APK
without touching a device.

## Data-Preserving Device Update

Never use `flutter run`, `flutter install`, `adb uninstall`, or package-data
clearing on the rider's phone. Trip history is app-private data and is deleted
on uninstall.

When the phone is connected, compare signatures without installing:

```powershell
.\scripts\install-signed-release.ps1 -BuildOnly -Devices RFGL42MHF7Z
```

Only when the user explicitly requests the update:

```powershell
.\scripts\install-signed-release.ps1 -Devices RFGL42MHF7Z -Launch
```

The script verifies the new APK, pulls the installed base APK read-only,
compares signing certificates, and only then uses `adb install -r`. A mismatch
stops the process. Never recover by uninstalling.

## Firmware Dependency

The connected physical board now runs the authorized BMS firmware containing
both `UNSET:<key>` and the verified Daly NimBLE central transport. Do not
re-flash it as part of the mobile task unless the user explicitly requests
another firmware change.

The firmware intentionally keeps VESC safety, sag detection, energy
integration, bridge ownership, and adaptive consumption learning on the
VESC-aligned path. The 2026-07-30 ride verified the Daly counter from
32.00 Ah/100% to 20.19 Ah/63%; its 11.81 Ah decrement agreed with 11.64 Ah
integrated Daly current. Fresh Daly SOC is now the rider-facing battery/range
input, with voltage SOC only a provisional fallback. The legacy pack-energy
learner remains disabled on BMS builds because its endpoints are a different,
voltage-derived SOC domain. The mobile app must not implement a competing
range-learning model.

The same ride exposed a board trip-reset defect: the raw board trip repeatedly
returned to zero while phone GPS recorded 13.08 mi. The app recorder now uses a
monotonic distance fusion: board odometry becomes authoritative only after it
proves progress; a stuck, reset, or unavailable board counter falls back to GPS
without reducing the displayed trip. Raw board and GPS distances remain visible
as separate evidence. Keep this fallback even after the firmware reset fix.

The cutoff in that ride was identified from raw `0x98` evidence and DALY's
official K/M/S BMSTool: `00000400000000` is discharge-overcurrent warning and
`00000800000000` is discharge-overcurrent protection 1. The protection opened
the discharge MOS for about 10 seconds; cells, temperature, and VESC fault code
did not indicate another cause. `BmsData` decodes these exact labels and shows
the optional latched `lfb`/`lfa` evidence after the live bit clears.
