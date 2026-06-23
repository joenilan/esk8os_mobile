# ESK8OS Mobile — Handoff

## NEXT TASK: map inside the floating overlay (Google-nav style)

**Goal:** render a live mini-map inside the floating window (`flutter_overlay_window`
overlay engine), centered on the rider with a heading marker — like Google Maps'
nav card — plus a small stats strip.

**Design DECIDED:** *map fills the bubble, speed + trip in a corner strip.* (Not
map-only.) Confirm with user only if they object.

### How it works today (already wired — build on this)
- Overlay UI: `lib/overlay/trip_overlay.dart` — runs in its own engine via the
  `@pragma('vm:entry-point') void overlayMain()` in `lib/main.dart`
  (`runApp(MaterialApp(home: TripOverlay()))`).
- Data bridge: main app pushes JSON once/sec via `FlutterOverlayWindow.shareData(...)`
  from `_pushOverlay()` in `lib/main.dart`; the overlay reads it in
  `FlutterOverlayWindow.overlayListener.listen(...)` (TripOverlay.initState).
  Currently sends: `spd, unit, trip, tu, time, paused`.
- Overlay shown on background-while-recording (`didChangeAppLifecycleState`) and via
  the **Settings → Ride Tracking → "Test floating window"** button (shows it on
  demand — use this to test without a trip).
- Reverse channel works: overlay tap → `shareData('open_app')` → main isolate →
  native `MethodChannel('esk8os/app')` `bringToFront` (MainActivity.kt) → app to front.

### Implementation steps
1. **Push position to the overlay.** In `_pushOverlay()` (lib/main.dart) add to the
   JSON: `lat`, `lng`, `hdg` from `TripRecorder.instance.currentPosition` (LatLng?)
   and `.heading` (double, GPS course). Guard nulls (rider may have no fix yet).
   Also add a sample `lat/lng` to the **Settings test-button** payload so the map
   shows during a no-trip test.
2. **Render the map** in `trip_overlay.dart`: add `flutter_map` `FlutterMap` with a
   `TileLayer` (CartoDB dark: `https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png`,
   subdomains a–d, same as `trip_view.dart`) + a `MarkerLayer` with the rider dot.
   Keep a `MapController`; on each shareData update call `move(LatLng(lat,lng), zoom)`
   (zoom ~16). Optionally rotate marker by `hdg`. Disable map gestures
   (`InteractionOptions(flags: InteractiveFlag.none)`) so drags move the bubble.
3. **Resize the overlay** bigger in BOTH `showOverlay` calls (lib/main.dart +
   lib/pages/settings_page.dart): currently `height:160,width:420,
   alignment: OverlayAlignment.center, positionGravity: PositionGravity.none`.
   Try ~`height: 360, width: 360`. Keep stats as a small overlaid strip (Stack:
   map full, a translucent Row of speed/trip pinned bottom or top).
4. Build (`flutter build apk --release`), install on **RFGL42MHF7Z**, TEST on device:
   tap "Test floating window" → map should render + recenter as GPS updates.

### RISKS / notes
- `flutter_map` in the overlay engine: it's mostly pure-Dart + HTTP tiles
  (`dart:io`, works in any isolate), so it *should* render without plugin
  registration. **If tiles don't load / it crashes**, fall back to a static
  approach (e.g., a tiny custom-painted breadcrumb of `route` points pushed via
  shareData) — don't block the whole overlay on the map.
- Overlay size has OEM limits; if 360² is rejected, shrink.
- The overlay only updates live while the main isolate runs — i.e. while
  **recording** (the foreground service keeps it alive). Not recording + backgrounded
  = frozen data (fine; test via the Test button which is foreground).

## CURRENT STATE (all pushed to `main`, installed on RFGL42MHF7Z)
- Latest commit: **0027448**. `flutter analyze` clean except **3 cosmetic
  `use_build_context_synchronously` infos in `lib/pages/settings_page.dart`**
  (snackbars after await) — fix by capturing `ScaffoldMessenger.of(context)` before
  the awaits. Harmless; clean up alongside the map work.
- Full ride-tracker shipped: per-trip stats (moving-avg, climb), crash-proof
  recording (10s checkpoint + recoverOrphans), auto start/stop (manual Stop now
  sticks; needs a real standstill to auto-start), pause/resume, over-speed haptic,
  share card, GPX export, per-trip graphs, **collapsible** map-stats card (tap to
  expand), notification Pause/Resume/Stop (flutter_foreground_task owns the FG
  location service), **floating overlay** (works, centered; tap-to-return works),
  mock device persists its settings to prefs (rider no longer resets on update).

## OPEN VERIFICATION (not bugs, just untested)
- Background GPS while app backgrounded + screen locked, under the FGT-owned
  location service (the recording AND overlay depend on it). If it stalls, re-add
  geolocator's `foregroundNotificationConfig` as a fallback (costs a 2nd notif).

## NOTIFICATIONS (answered for the user; structural, mostly not reducible)
While the bubble is up: (1) our Pause/Stop recording notif — essential, only while
recording; (2) the overlay plugin's own FG-service notif — only while bubble shown;
(3) Android's "displaying over other apps" — system-mandated, not removable. Only #1
persists when the bubble is closed.

## HARD CONSTRAINTS (do not violate)
- `E:\AI\esk8os_mobile` is nested inside the `E:\AI` repo (holds secrets, no remote,
  NEVER push). The app has its OWN `.git`. Run git ONLY from inside `esk8os_mobile`.
  Never `git add`/commit/push from `E:\AI`.
- Keystore (`android/app/esk8-release.jks`, `android/key.properties*`) is gitignored
  — never commit. It's the permanent release key; over-the-top installs preserve data.
- Build: `C:/dev/flutter/bin/flutter build apk --release`. Install:
  `adb -s RFGL42MHF7Z install -r build/app/outputs/flutter-apk/app-release.apk`.
  adb/USB is flaky — `adb kill-server && adb start-server` if the device drops.
