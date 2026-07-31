# EVEE Mobile Product Roadmap

Updated 2026-07-29. This roadmap treats the board, phone, trip history, maps,
and rider-created trails as one product. `AGENTS.md` remains authoritative for
data safety and board/VESC ownership.

## North Star

EVEE should be useful before, during, and after a ride:

- **Explore** nearby paths, the rider's own tracks, saved trails, and waypoints.
- **Ride** with a glanceable map, trustworthy board/GPS source labels, resilient
  recording, and controls that are difficult to trigger accidentally.
- **Library** recorded rides, curated trails, waypoints, offline regions, and
  exports without requiring a live board connection.
- **Board** connect to ESK8OS for authoritative telemetry, battery diagnostics,
  settings, logs, and bridge tools.

BLE enhances the ride experience; it must not be the front-door lock for maps
or production trip history.

## Audit Findings

### Product structure

- The current app opens on a BLE scan page and places the entire product behind
  a successful board or mock connection. Saved rides and maps are unavailable
  while the board is off or elsewhere.
- `main.dart`, `settings_page.dart`, `trip_view.dart`, and
  `trip_playback_page.dart` are large feature monoliths. This raises regression
  risk and makes visual iteration unnecessarily expensive.
- Mock Mode is presented as a prominent bug icon on the production home screen.

### Trip recorder

- The recorder has good foundations: app-level lifetime, Android foreground
  service, pause/resume, one-second checkpoints, board/GPS source awareness,
  BMS snapshots, and crash-orphan recovery.
- Start/stop has no explicit state machine. Partial failures can leave
  `_starting`, wakelock, the foreground service, subscriptions, or a new trip
  row in an ambiguous state.
- A cached last-known GPS point is accepted without checking its age or
  accuracy. A stale seed can create an unrealistic first route segment.
- GPS filtering checks horizontal accuracy but not impossible jumps, reported
  speed accuracy, or stale timestamps.
- Database writes are started from a periodic timer without a serialized write
  queue or surfaced failure state.
- Once any board frame has been live, summary distance prefers the board trip
  for the whole ride, while live speed can fall back to GPS. Dropout distance
  needs an explicit segment/fusion policy rather than silently freezing.
- Pause creates the correct distance behavior but the route is one continuous
  point list, so playback can visually draw across a paused relocation.

### Maps and trails

- Live, playback, and overlay maps duplicate basemap URLs, attribution, and
  styling.
- The current CARTO raster tiles are an online basemap, not an offline-map
  contract. CARTO requires an appropriate license/grant for application use;
  bulk downloads must not be added to the current public URLs.
- `flutter_map` has useful built-in best-effort caching, but its documentation
  explicitly says that cache is not a safety-grade offline map.
- No first-class `Trail`, `Waypoint`, `TrailReport`, or `OfflineRegion` model
  exists. A recorded trip and a curated trail must remain different entities.
- OpenStreetMap can seed path geometry and metadata, but missing access,
  surface, visibility, or difficulty tags cannot be interpreted as permission
  or safety. Rider-created verification must preserve that uncertainty.

### Ride controls and presentation

- The live map contains strong implementation work—smooth marker motion,
  heading-up behavior, board/GPS comparison, source labels, and long-route
  rebuild avoidance.
- Map chrome competes for four corners, GPS coordinates are promoted above more
  useful ride actions, and the recording state is split across a banner,
  expandable stats, and bottom controls.
- Stop is a single tap. It needs confirmation or a deliberate hold/slide action
  while keeping pause instantly accessible.
- Immersive mode is applied to the entire app. Full-screen treatment is useful
  in Ride mode but removes normal phone context from scanning, history, and
  settings.

### Quality and performance

- Static analysis and the existing 37 tests pass, but recorder, database
  migration/import, trip history, maps, and navigation have little direct
  coverage.
- Several dependencies have safe patch/minor updates available. Larger
  foreground-task, overlay, internationalization, and map-stack upgrades need
  isolated migrations and device verification.
- A native vector map stack such as MapLibre is a plausible long-term fit for
  custom trail styling and offline regions. It should be prototyped behind a
  map abstraction before replacing the stable live ride map.

## Target Architecture

```text
App shell
├── Explore   map, trail layers, search, waypoints, offline regions
├── Ride      GPS-only or board-enhanced recorder and ride controls
├── Library   rides, trails, waypoints, downloads, import/export
└── Board     connection, telemetry deck, BMS, settings, logs, bridge

Domain
├── Ride      immutable recorded activity and raw evidence
├── Trail     curated reusable route derived from a ride/import/drawing
├── Waypoint  named rider marker with type, notes, and optional media
└── Region    offline map/trail package with provider/license metadata
```

The recorder must not depend on a page being mounted. Board telemetry remains
authoritative while fresh; GPS supplies route/elevation and a documented
fallback. A trail derived from a ride copies selected geometry and metadata so
editing a trail never rewrites production ride evidence.

## Delivery Sequence

### 1. Board-independent foundation

- Make Library available while disconnected.
- Remember the last real unit preference for offline ride presentation.
- Replace the debug-looking Mock button with a deliberate overflow action.
- Introduce an app shell incrementally without rewriting the connected
  dashboard in one change.

### 2. Recorder reliability and evidence

- Add explicit idle/starting/recording/paused/stopping/error states.
- Validate the first GPS anchor and reject impossible position jumps.
- Serialize database writes and expose recording/storage health.
- Persist source/freshness evidence needed for honest playback.
- Model route segment breaks for pauses and GPS gaps.
- Add recorder and schema-migration tests before changing live behavior.

### 3. Ride-mode redesign

- Consolidate primary speed, source, recording health, distance, time, and
  battery into one glanceable ride card.
- Make pause immediate and stop deliberate.
- Move coordinates and comparison diagnostics behind a details sheet.
- Add GPS accuracy, offline-map readiness, and recording-health indicators.
- Restrict immersive mode to active Ride mode.

### 4. Rider-built trails

- Create a Trail from a completed ride or imported GPX.
- Name, describe, rate, tag surface/direction, trim, split, and simplify it.
- Add waypoints for hazards, trailheads, parking, charging, water, and notes.
- Show repeated rides as heat/coverage evidence without automatically declaring
  them public or legal trails.
- Add local search/filtering and shareable GPX/GeoJSON packages.

### 5. Trail discovery and offline maps

- Add an OSM-derived path overlay with explicit access/data-quality states.
- Support difficulty/surface/visibility metadata when present; label unknowns.
- Choose a licensed vector-tile provider or self-hosted extracts before
  implementing region downloads.
- Prototype MapLibre behind the map abstraction for vector styling, offline
  regions, terrain, and future route snapping.
- Test downloaded regions in forced-offline mode before presenting them as
  navigation-ready.

### 6. Community features, only after local ownership is solid

- Trail reports, closures, conditions, photos, and revision history.
- Optional account/sync, collaborative folders, and crew location sharing.
- Moderation, privacy, safety, and data provenance must be designed before
  publishing rider-generated trails.

## Product Guardrails

- Never delete or rewrite raw ride history as a side effect of editing a trail.
- Never imply that an unverified path is legal, open, safe, or rideable.
- Never bulk-download from a public tile endpoint without explicit permission.
- Never require a board connection to view/export the rider's own data.
- Never hide whether speed, distance, battery, or route data came from the board,
  Daly BMS, GPS, demo mode, import, or a fallback.
- Every schema change is additive, migration-tested, and backup-compatible.
