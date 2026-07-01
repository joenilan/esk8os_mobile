param(
    [string[]]$Devices = @("RFGL42MHF7Z", "emulator-5554"),
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repo

$keyPropsPath = Join-Path $repo "android\key.properties"
if (-not (Test-Path $keyPropsPath)) {
    throw "Refusing to build/install: android\key.properties is missing. Installing without the permanent release key can break updates or wipe data."
}

$props = @{}
Get-Content $keyPropsPath | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+?)\s*=\s*(.+)\s*$") {
        $props[$matches[1].Trim()] = $matches[2].Trim()
    }
}

if (-not $props.ContainsKey("storeFile")) {
    throw "Refusing to build/install: android\key.properties does not define storeFile."
}

$storeFile = Join-Path (Join-Path $repo "android\app") $props["storeFile"]
if (-not (Test-Path $storeFile)) {
    throw "Refusing to build/install: release keystore not found at $storeFile."
}

$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    throw "adb.exe not found at $adb."
}

flutter build apk --release

$apk = Join-Path $repo "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
    throw "Release APK was not produced at $apk."
}

foreach ($device in $Devices) {
    Write-Host "Installing signed release APK on $device with adb install -r..."
    & $adb -s $device install -r $apk
    if ($LASTEXITCODE -ne 0) {
        throw "Install failed on $device. Do not uninstall to force the update; stop and inspect the signing/device state."
    }

    if ($Launch) {
        & $adb -s $device shell monkey -p com.joenilan.esk8os_mobile -c android.intent.category.LAUNCHER 1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Launch failed on $device."
        }
    }
}

Write-Host "Done. No uninstall command was used."

