param(
    [string[]]$Devices = @(),
    [switch]$Launch,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repo

if (-not $BuildOnly -and $Devices.Count -eq 0) {
    throw "Specify -Devices <serials> for an in-place update, or use -BuildOnly to compile and verify without touching a device."
}

$keyPropsPath = Join-Path $repo "android\key.properties"
if (-not (Test-Path -LiteralPath $keyPropsPath)) {
    throw "Refusing to build/install: android\key.properties is missing. A differently signed APK cannot update the installed app in place."
}

$props = @{}
Get-Content -LiteralPath $keyPropsPath | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+?)\s*=\s*(.+)\s*$") {
        $props[$matches[1].Trim()] = $matches[2].Trim()
    }
}

foreach ($requiredKey in @("storeFile", "storePassword", "keyAlias", "keyPassword")) {
    if (-not $props.ContainsKey($requiredKey)) {
        throw "Refusing to build/install: android\key.properties does not define $requiredKey."
    }
}

$storeFile = Join-Path (Join-Path $repo "android\app") $props["storeFile"]
if (-not (Test-Path -LiteralPath $storeFile)) {
    throw "Refusing to build/install: release keystore not found at $storeFile."
}

$flutter = "C:\dev\flutter\bin\flutter.bat"
if (-not (Test-Path -LiteralPath $flutter)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -eq $flutterCommand) {
        throw "Flutter was not found at C:\dev\flutter\bin\flutter.bat or on PATH."
    }
    $flutter = $flutterCommand.Source
}

$androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$adb = Join-Path $androidSdk "platform-tools\adb.exe"
if (-not (Test-Path -LiteralPath $adb)) {
    throw "adb.exe not found at $adb."
}

$apksigner = Get-ChildItem -LiteralPath (Join-Path $androidSdk "build-tools") -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName "apksigner.bat" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $apksigner) {
    throw "apksigner.bat was not found under $androidSdk\build-tools."
}

function Get-ApkSignerDigest {
    param([Parameter(Mandatory)][string]$ApkPath)

    $verifyOutput = & $apksigner verify --print-certs $ApkPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed for $ApkPath`n$($verifyOutput -join [Environment]::NewLine)"
    }
    $digestMatch = $verifyOutput |
        Select-String -Pattern "certificate SHA-256 digest:\s*(\S+)" |
        Select-Object -First 1
    if (-not $digestMatch) {
        throw "Could not read the signer certificate digest from $ApkPath."
    }
    return $digestMatch.Matches[0].Groups[1].Value.ToLowerInvariant()
}

function Assert-InstalledSignerMatches {
    param(
        [Parameter(Mandatory)][string]$Device,
        [Parameter(Mandatory)][string]$ExpectedDigest
    )

    $packagePaths = & $adb -s $Device shell pm path com.joenilan.esk8os_mobile 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not query the installed EVEE app on $Device."
    }
    $baseLine = $packagePaths |
        Where-Object { $_ -like "package:*base.apk" } |
        Select-Object -First 1
    if (-not $baseLine) {
        Write-Host "EVEE is not installed on $Device; signature comparison is not needed."
        return
    }

    $remoteApk = $baseLine.Substring("package:".Length).Trim()
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $tempDir = Join-Path $tempRoot ("esk8os-signature-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $installedApk = Join-Path $tempDir "installed-base.apk"
        & $adb -s $Device pull $remoteApk $installedApk | Out-Host
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $installedApk)) {
            throw "Could not copy the installed APK from $Device for signature verification."
        }
        $installedDigest = Get-ApkSignerDigest -ApkPath $installedApk
        if ($installedDigest -ne $ExpectedDigest) {
            throw "Signing certificate mismatch on $Device. Refusing the update; do not uninstall the existing app because that would delete trip data."
        }
        Write-Host "Signing certificate matches the installed app on $Device."
    }
    finally {
        $resolvedTemp = [IO.Path]::GetFullPath($tempDir)
        if ($resolvedTemp.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedTemp).StartsWith("esk8os-signature-", [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}

# Keep Dart AOT symbols outside the APK and archive them per version so field
# crash traces remain symbolizable.
& $flutter build apk --release --split-debug-info=build/symbols
if ($LASTEXITCODE -ne 0) {
    throw "Flutter release build failed."
}

$apk = Join-Path $repo "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -LiteralPath $apk)) {
    throw "Release APK was not produced at $apk."
}

$newDigest = Get-ApkSignerDigest -ApkPath $apk
Write-Host "Signed release APK verified (certificate SHA-256: $newDigest)."

$ver = ((Get-Content -LiteralPath "pubspec.yaml" | Select-String "^version:").Line -split "\s+")[1]
$symDest = Join-Path $repo "symbols_archive\$ver"
New-Item -ItemType Directory -Force -Path $symDest | Out-Null
Copy-Item -Path "build\symbols\*" -Destination $symDest -Force
Write-Host "Symbols archived to symbols_archive\$ver"

if ($BuildOnly) {
    foreach ($device in $Devices) {
        $stateLine = & $adb -s $device get-state 2>$null | Select-Object -First 1
        $state = if ($null -eq $stateLine) { "" } else { $stateLine.Trim() }
        if ($LASTEXITCODE -ne 0 -or $state -ne "device") {
            throw "Device $device is not available to adb."
        }
        Assert-InstalledSignerMatches -Device $device -ExpectedDigest $newDigest
    }
    Write-Host "Build-only verification complete. No device was changed."
    return
}

foreach ($device in $Devices) {
    $stateLine = & $adb -s $device get-state 2>$null | Select-Object -First 1
    $state = if ($null -eq $stateLine) { "" } else { $stateLine.Trim() }
    if ($LASTEXITCODE -ne 0 -or $state -ne "device") {
        throw "Device $device is not available to adb."
    }

    Assert-InstalledSignerMatches -Device $device -ExpectedDigest $newDigest

    Write-Host "Installing the verified APK on $device with adb install -r..."
    & $adb -s $device install -r $apk
    if ($LASTEXITCODE -ne 0) {
        throw "Install failed on $device. Do not uninstall to force the update; stop and inspect the device/version state."
    }

    if ($Launch) {
        & $adb -s $device shell monkey -p com.joenilan.esk8os_mobile -c android.intent.category.LAUNCHER 1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Launch failed on $device."
        }
    }
}

Write-Host "Done. The update was signature-checked and installed in place; no uninstall command was used."
