# EVEE Dedicated Development Phone

Current dedicated Android development / ride-validation phone:

- Device: Samsung Galaxy S23
- Model: `SM-S911U`
- ADB serial: `RFCW405TSXD`
- Android: 16 / API 36
- CSC/carrier build: T-Mobile US
- EVEE package: `com.joenilan.esk8os_mobile`
- Expected release signing certificate SHA-256:
  `929ae55957d78da15ca261867f136f6c97228cc7a261b5b5066dead81b2b747f`

This S23 is the normal physical target for EVEE Android development, signed
in-place installs, BLE/GPS testing, ride recording, board Wi-Fi work, and
on-device UI validation.

## Device targeting rule

Always scope ADB commands explicitly to `RFCW405TSXD`.

The user's other Samsung, `RFGL42MHF7Z`, is **not** the normal EVEE
development target. Do not install, uninstall, clear data, change permissions,
or otherwise mutate it unless the user explicitly asks to work on that device.

## EVEE runtime state on this phone

Current validated device-side setup:

- Precise location: granted
- Nearby devices / BLE scan + connect: granted
- Notifications: granted
- Background location: intentionally not required for normal recorder flow
- Overlay permission: opt-in only when floating ride stats are wanted
- Android device-idle whitelist: EVEE present
- App standby bucket: Active
- Background execution AppOps: allowed
- Samsung battery mode: Unrestricted
- USB debugging: enabled
- Wireless debugging: enabled
- USB mode: `mtp,adb`

Normal ride recording uses a location-type foreground service. Do not
automatically grant blanket background-location access unless a future feature
actually requires it.

Do not put EVEE into Samsung Sleeping Apps or Deep Sleeping Apps.

The Blackhole phone profile also keeps Bluetooth/BLE, fused/GPS location,
Wi-Fi/network stack, no-internet local AP behavior, notification/foreground
service infrastructure, DocumentsUI/sharing, compass/sensors, Play services,
and WebView intact because EVEE depends on those paths.

## Installed companion/debug apps

### SMART BMS Pro
Package: `com.smart.bms.pro`

This is the authoritative DALY app for the skateboard battery. Use it for
normal BMS monitoring/configuration: pack voltage, individual cells,
temperatures, current/SOC, MOS state, warnings/protections, and DALY settings.

The user already uses SMART BMS Pro on the other phone, so do not waste time
comparing alternate DALY apps. Before writing BMS protection parameters,
capture/read back the existing values and preserve a known-good baseline.

### nRF Connect
Package: `no.nordicsemi.android.mcp`

Use this for raw BLE/GATT diagnosis when EVEE cannot discover/connect to a
board or when the BLE contract needs independent verification. Useful for:

- confirming the ESK8OS service UUID is advertising
- inspecting characteristics `0001` through `0006`
- checking RSSI / range
- observing notifications
- confirming whether a problem is EVEE-side or board/BLE-side

Do not casually write arbitrary characteristic values to a real board.

### GPSTest
Package: `com.android.gpstest`

Use GPSTest when diagnosing ride-recorder/location problems. It helps separate
an EVEE bug from a poor GNSS fix by showing satellite visibility, signal,
accuracy/fix state, altitude, bearing, and constellation data.

### WiFi Analyzer
Package: `com.vrem.wifianalyzer`

Use it for ESP32/board Wi-Fi troubleshooting, especially 2.4 GHz interference,
channel congestion, AP visibility, and signal strength. This is useful when
the board AP is visible intermittently or local Wi-Fi/OTA behavior changes by
location.

### LocalSend
Package: `org.localsend.localsend_app`

LocalSend is the preferred quick LAN file-transfer utility between this phone
and the development PC. It is useful for APKs, screenshots, logs, exported
rides, GPX/JSON files, firmware files, and camera media without using cloud
storage or messaging apps.

It is not part of EVEE runtime behavior; it is a development/support tool.

### Shizuku
Package: `moe.shizuku.privileged.api`

Installed for optional non-root Android/system tooling. Its privileged service
is not part of the normal EVEE development path and must not become a hidden
runtime dependency. If a task can be done with normal Android APIs/ADB, prefer
that. Configure/start Shizuku only when a specific tool actually requires it.

### IRL Pro
Package: `app.irlpro.android`

IRL Pro is installed because this S23 is also a dedicated content/streaming
phone. It is unrelated to EVEE and must not become an EVEE dependency.

Its camera, microphone, and notification permissions are enabled and Samsung
battery mode is Unrestricted for streaming reliability. Do not change its
streaming configuration as part of ordinary EVEE development.

## Debugging tool choice

Use the smallest tool that answers the question:

- EVEE cannot see/connect to board -> **nRF Connect**
- GPS route/fix/accuracy looks wrong -> **GPSTest**
- ESP32 AP / Wi-Fi / OTA is flaky -> **WiFi Analyzer**
- Need DALY pack truth/settings -> **SMART BMS Pro**
- Need to move APK/log/export/media locally -> **LocalSend**
- Need an app-specific privileged Android bridge -> **Shizuku**, only deliberately

## Signed build/install workflow

The dedicated development phone still contains real ride data once used, so
updates must remain data-preserving.

Read-only build/signature check:

```powershell
.\scripts\install-signed-release.ps1 -BuildOnly -Devices RFCW405TSXD
```

Only when the user explicitly asks to update the phone:

```powershell
.\scripts\install-signed-release.ps1 -Devices RFCW405TSXD -Launch
```

Never use `flutter install`, `flutter run`, `adb uninstall`, or
`pm clear` as an update workaround on this phone. A signature mismatch is a
stop condition, not permission to uninstall.

If more than one Android device is connected, verify `adb devices -l` and
the target model/serial before every mutating command.

## Blackhole phone-profile notes

This phone is intentionally tuned and debloated, but the EVEE-critical Android
stack is preserved.

Important test-environment facts:

- Samsung RAM Plus: off
- Samsung zram: still enabled normally
- UI animation scales: 1.0x for representative app testing
- Blackhole Quiet Mode: active
- DND mode: alarms-only
- heads-up notifications, badges, bubbles, lock-screen notification display,
  and AOD notification indicators are suppressed

Quiet Mode does **not** mean EVEE notification delivery is broken. EVEE's
notification permission and foreground-service infrastructure remain enabled.

When testing notification appearance/heads-up/badges specifically, temporarily
restore normal notification presentation through the Blackhole tooling rather
than changing EVEE code to compensate for this device profile.

Blackhole device-management repo:
`E:\git\blackhole`

## Provisioning snapshot - 2026-09-28

Installed utility versions at provisioning time:

- SMART BMS Pro: V3.3.9
- nRF Connect: 4.29.1
- GPSTest: 3.10.5
- WiFi Analyzer: 3.3.1
- LocalSend: 1.18.2
- Shizuku: 13.6.0.r1086.2650830c
- IRL Pro: 3.5.23

EVEE provisioning baseline:
- app version: 0.2.34+36
- source commit used for the installed provisioning build: `f17b5ba`
- all 72 Flutter tests passed before that install

Treat these versions as a dated snapshot, not application dependencies.
Future app/tool updates are fine as long as the documented workflows remain
compatible.

The S23 camera/content profile is also tuned for this phone's secondary creator
role (UHD/4K30 HEVC quality-priority video), but camera settings are not an EVEE
runtime dependency.
